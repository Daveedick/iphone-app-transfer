package bridge

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
)

var accountIDPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

type operation struct {
	ctx       context.Context
	cancel    context.CancelFunc
	accountID string
	code      chan string
	auth      bool
	awaiting  bool
	committed bool
}
type Server struct {
	secrets    SecretStore
	factory    CoreFactory
	output     *Writer
	mu         sync.Mutex
	operations map[string]*operation
	seen       map[string]struct{}
	registryMu sync.Mutex
	wg         sync.WaitGroup
}

func NewServer(s SecretStore, factory CoreFactory, out io.Writer) *Server {
	return &Server{secrets: s, factory: factory, output: NewWriter(out), operations: map[string]*operation{}, seen: map[string]struct{}{}}
}
func (s *Server) Run(in io.Reader) error {
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 4096), MaxMessageBytes)
	for scanner.Scan() {
		line := scanner.Bytes()
		var r Request
		if err := json.Unmarshal(line, &r); err != nil {
			s.output.Send("", "failed", nil, invalid("Invalid JSON message."))
			continue
		}
		if r.ProtocolVersion != ProtocolVersion || r.RequestID == "" || len(r.RequestID) > 128 {
			s.output.Send(r.RequestID, "failed", nil, invalid("Unsupported protocol or invalid request identifier."))
			continue
		}
		s.mu.Lock()
		_, duplicate := s.seen[r.RequestID]
		if !duplicate {
			if len(s.seen) > 4096 {
				s.seen = map[string]struct{}{}
				for id := range s.operations {
					s.seen[id] = struct{}{}
				}
			}
			s.seen[r.RequestID] = struct{}{}
		}
		s.mu.Unlock()
		if duplicate {
			s.output.Send(r.RequestID, "failed", nil, invalid("Request identifier was already used."))
			continue
		}
		s.handle(r)
	}
	s.mu.Lock()
	for _, op := range s.operations {
		op.cancel()
	}
	s.mu.Unlock()
	// Login's upstream API has no context: leave at process exit after a bounded wait.
	done := make(chan struct{})
	go func() { s.wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(250 * time.Millisecond):
	}
	return scanner.Err()
}
func invalid(message string) *BridgeError {
	return &BridgeError{Code: "request.invalid", Message: message, Retryable: false}
}
func decode(r Request, out any) error {
	if len(r.Payload) == 0 {
		return json.Unmarshal([]byte("{}"), out)
	}
	return json.Unmarshal(r.Payload, out)
}
func (s *Server) fail(r Request, err error) { s.output.Send(r.RequestID, "failed", nil, classify(err)) }
func (s *Server) handle(r Request) {
	switch r.Command {
	case "hello":
		s.output.Send(r.RequestID, "ready", map[string]any{"helperVersion": HelperVersion, "upstreamVersion": UpstreamVersion, "protocolVersion": ProtocolVersion, "capabilities": []string{"account.list", "account.remove", "auth.begin", "auth.submitCode", "auth.cancel", "app.versionInfo", "app.versions", "app.download", "operation.cancel"}}, nil)
	case "account.list":
		s.registryMu.Lock()
		accounts, err := loadAccounts(s.secrets)
		s.registryMu.Unlock()
		if err != nil {
			s.fail(r, err)
			return
		}
		for i := range accounts {
			b, e := s.secrets.Get("account/" + accounts[i].ID + "/account")
			accounts[i].Authenticated = e == nil && len(b) > 0
		}
		s.output.Send(r.RequestID, "completed", map[string]any{"accounts": accounts}, nil)
	case "account.remove":
		s.remove(r)
	case "auth.begin":
		s.beginAuth(r)
	case "auth.submitCode":
		s.submitCode(r)
	case "auth.cancel":
		var p struct {
			AccountID string `json:"accountId"`
		}
		if decode(r, &p) != nil || !validAccountID(p.AccountID) {
			s.fail(r, invalid("Invalid account identifier."))
			return
		}
		s.mu.Lock()
		p.AccountID = strings.ToLower(p.AccountID)
		count := 0
		for _, op := range s.operations {
			if op.accountID == p.AccountID && op.auth {
				if !op.committed {
					op.cancel()
					count++
				}
			}
		}
		s.mu.Unlock()
		s.output.Send(r.RequestID, "completed", map[string]any{"cancelRequested": count > 0}, nil)
	case "operation.cancel":
		var p struct {
			OperationID string `json:"operationId"`
		}
		if decode(r, &p) != nil || p.OperationID == "" {
			s.fail(r, invalid("Missing operation identifier."))
			return
		}
		s.mu.Lock()
		op := s.operations[p.OperationID]
		requested := op != nil && !op.committed
		if requested {
			op.cancel()
		}
		s.mu.Unlock()
		s.output.Send(r.RequestID, "completed", map[string]any{"cancelRequested": requested}, nil)
	case "app.versionInfo", "app.versions", "app.download":
		s.appOperation(r)
	default:
		s.fail(r, invalid("Unsupported command."))
	}
}
func validAccountID(id string) bool { return accountIDPattern.MatchString(id) }
func uuid() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	h := hex.EncodeToString(b[:])
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}
func (s *Server) start(r Request, id string) (*operation, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, op := range s.operations {
		if op.accountID == id {
			return nil, &BridgeError{Code: "account.busy", Message: "Wait for this account's current operation to finish.", Retryable: true}
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	op := &operation{ctx: ctx, cancel: cancel, accountID: id, code: make(chan string, 1)}
	s.operations[r.RequestID] = op
	return op, nil
}
func (s *Server) finish(id string, op *operation) {
	op.cancel()
	s.mu.Lock()
	delete(s.operations, id)
	s.mu.Unlock()
	s.wg.Done()
}
func (s *Server) terminal(r Request, op *operation, event string, payload any, err error) {
	// Release the account before publishing a terminal response: the parent may
	// immediately begin its next request after reading that line.
	s.mu.Lock()
	delete(s.operations, r.RequestID)
	canceled := op.ctx.Err() != nil && !op.committed
	s.mu.Unlock()
	if canceled {
		s.output.Send(r.RequestID, "canceled", nil, nil)
		return
	}
	if err != nil {
		s.fail(r, err)
		return
	}
	s.output.Send(r.RequestID, event, payload, nil)
}
func (s *Server) beginAuth(r Request) {
	var p struct {
		AccountID string `json:"accountId"`
		Email     string `json:"email"`
		Password  string `json:"password"`
	}
	if decode(r, &p) != nil || strings.TrimSpace(p.Email) == "" || p.Password == "" {
		s.fail(r, invalid("Email and password are required."))
		return
	}
	p.AccountID = strings.ToLower(p.AccountID)
	if p.AccountID == "" {
		s.registryMu.Lock()
		accounts, e := loadAccounts(s.secrets)
		s.registryMu.Unlock()
		if e != nil {
			s.fail(r, e)
			return
		}
		for _, a := range accounts {
			if strings.EqualFold(strings.TrimSpace(a.Email), strings.TrimSpace(p.Email)) {
				p.AccountID = a.ID
				break
			}
		}
		if p.AccountID == "" {
			p.AccountID = uuid()
		}
	}
	if !validAccountID(p.AccountID) {
		s.fail(r, invalid("Invalid account identifier."))
		return
	}
	op, err := s.start(r, p.AccountID)
	if err != nil {
		s.fail(r, err)
		return
	}
	s.mu.Lock()
	op.auth = true
	s.mu.Unlock()
	s.output.Send(r.RequestID, "auth.preparing", map[string]any{"accountId": p.AccountID, "message": "Preparing Apple authentication; first sign-in may download verified runtime components."}, nil)
	s.wg.Add(1)
	go func() {
		defer s.finish(r.RequestID, op)
		// Keep auth writes private until the entire login succeeds and remains uncanceled.
		tx := newSecretTransaction(s.secrets)
		core, err := s.factory(op.ctx, p.AccountID, tx)
		if err != nil {
			s.terminal(r, op, "", nil, err)
			return
		}
		code := ""
		for attempt := 0; attempt <= 5; attempt++ {
			if op.ctx.Err() != nil {
				s.terminal(r, op, "", nil, op.ctx.Err())
				return
			}
			a, e := core.Login(strings.TrimSpace(p.Email), p.Password, code)
			if e == nil {
				p.Password = ""
				code = ""
				s.mu.Lock()
				if op.ctx.Err() == nil {
					err = tx.Commit(op.ctx)
					if err == nil {
						op.committed = true
					}
				} else {
					err = op.ctx.Err()
				}
				s.mu.Unlock()
				if err != nil {
					s.terminal(r, op, "", nil, err)
					return
				}
				s.registryMu.Lock()
				accounts, e := loadAccounts(s.secrets)
				if e == nil {
					found := false
					for i := range accounts {
						if accounts[i].ID == a.ID {
							accounts[i] = a
							found = true
						}
					}
					if !found {
						accounts = append(accounts, a)
					}
					e = saveAccounts(s.secrets, accounts)
				}
				s.registryMu.Unlock()
				s.terminal(r, op, "auth.succeeded", map[string]any{"account": a}, e)
				return
			}
			needsCode := errors.Is(e, appstore.ErrAuthCodeRequired) || code != "" && strings.Contains(strings.ToLower(e.Error()), "fresh 2fa code")
			if !needsCode {
				p.Password = ""
				code = ""
				s.terminal(r, op, "", nil, e)
				return
			}
			if attempt == 5 {
				p.Password = ""
				code = ""
				s.terminal(r, op, "", nil, &BridgeError{Code: "auth.tooManyAttempts", Message: "Too many verification attempts. Sign in again later.", Retryable: true})
				return
			}
			s.mu.Lock()
			op.awaiting = true
			s.mu.Unlock()
			s.output.Send(r.RequestID, "auth.codeRequired", map[string]any{"accountId": p.AccountID, "invalidPreviousCode": code != ""}, nil)
			timer := time.NewTimer(10 * time.Minute)
			select {
			case code = <-op.code:
				s.mu.Lock()
				op.awaiting = false
				s.mu.Unlock()
				timer.Stop()
			case <-op.ctx.Done():
				timer.Stop()
				p.Password = ""
				s.terminal(r, op, "", nil, op.ctx.Err())
				return
			case <-timer.C:
				p.Password = ""
				s.terminal(r, op, "", nil, &BridgeError{Code: "auth.timeout", Message: "Verification timed out. Sign in again.", Retryable: true})
				return
			}
		}
		p.Password = ""
		code = ""
		s.terminal(r, op, "", nil, &BridgeError{Code: "auth.tooManyAttempts", Message: "Too many verification attempts. Sign in again later.", Retryable: true})
	}()
}
func (s *Server) submitCode(r Request) {
	var p struct {
		AccountID string `json:"accountId"`
		Code      string `json:"code"`
	}
	if decode(r, &p) != nil || !validAccountID(p.AccountID) || len(p.Code) != 6 || strings.Trim(p.Code, "0123456789") != "" {
		s.fail(r, invalid("Enter a six-digit verification code."))
		return
	}
	p.AccountID = strings.ToLower(p.AccountID)
	s.mu.Lock()
	var op *operation
	for _, v := range s.operations {
		if v.accountID == p.AccountID && v.auth && v.awaiting && v.ctx.Err() == nil {
			op = v
			break
		}
	}
	if op == nil {
		s.mu.Unlock()
		s.fail(r, invalid("There is no authentication awaiting verification."))
		return
	}
	// Reserve this verification while holding the same lock used to inspect it.
	// A second UI submission must not queue an OTP for a future retry prompt.
	op.awaiting = false
	accepted := false
	select {
	case op.code <- p.Code:
		accepted = true
	default:
	}
	s.mu.Unlock()
	if accepted {
		s.output.Send(r.RequestID, "completed", map[string]any{"accepted": true}, nil)
	} else {
		s.fail(r, &BridgeError{Code: "auth.busy", Message: "Verification is already running.", Retryable: true})
	}
}
func (s *Server) remove(r Request) {
	var p struct {
		AccountID string `json:"accountId"`
	}
	if decode(r, &p) != nil || !validAccountID(p.AccountID) {
		s.fail(r, invalid("Invalid account identifier."))
		return
	}
	p.AccountID = strings.ToLower(p.AccountID)
	op, err := s.start(r, p.AccountID)
	if err != nil {
		s.fail(r, err)
		return
	}
	s.wg.Add(1)
	defer s.finish(r.RequestID, op)
	for _, name := range []string{"account", "cookies", "kbsync-v1"} {
		if err := s.secrets.Delete("account/" + p.AccountID + "/" + name); err != nil {
			s.fail(r, err)
			return
		}
	}
	s.registryMu.Lock()
	accounts, err := loadAccounts(s.secrets)
	if err == nil {
		updated := make([]Account, 0, len(accounts))
		for _, a := range accounts {
			if a.ID != p.AccountID {
				updated = append(updated, a)
			}
		}
		err = saveAccounts(s.secrets, updated)
	}
	s.registryMu.Unlock()
	if err != nil {
		s.fail(r, err)
		return
	}
	s.output.Send(r.RequestID, "completed", map[string]any{"removed": true, "accountId": p.AccountID}, nil)
}
func (s *Server) appOperation(r Request) {
	var p AppRequest
	if decode(r, &p) != nil || !validAccountID(p.AccountID) || p.StoreItemID <= 0 || p.BundleID == "" {
		s.fail(r, invalid("Account, store item identifier and bundle identifier are required."))
		return
	}
	p.AccountID = strings.ToLower(p.AccountID)
	if r.Command == "app.download" && p.ExternalVersionID == "" {
		s.fail(r, invalid("Choose an explicit external version identifier before downloading."))
		return
	}
	op, err := s.start(r, p.AccountID)
	if err != nil {
		s.fail(r, err)
		return
	}
	s.wg.Add(1)
	go func() {
		defer s.finish(r.RequestID, op)
		core, err := s.factory(op.ctx, p.AccountID, s.secrets)
		if err != nil {
			s.terminal(r, op, "", nil, err)
			return
		}
		var result any
		switch r.Command {
		case "app.versionInfo":
			result, err = core.VersionInfo(p)
		case "app.versions":
			result, err = core.Versions(p)
		case "app.download":
			result, err = core.Download(p, func(progress Progress) {
				if op.ctx.Err() == nil {
					s.output.Send(r.RequestID, "download.progress", progress, nil)
				}
			})
		}
		s.terminal(r, op, "completed", result, err)
	}()
}
