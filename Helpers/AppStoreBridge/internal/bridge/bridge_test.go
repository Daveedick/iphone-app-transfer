package bridge

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
)

const alice = "11111111-1111-4111-8111-111111111111"
const bob = "22222222-2222-4222-8222-222222222222"

func TestScopedCredentialsStripPasswordAndSeparateAccounts(t *testing.T) {
	s := newMemorySecrets()
	a := scopedKeychain{ctx: context.Background(), secrets: s, prefix: "account/" + alice + "/"}
	b := scopedKeychain{ctx: context.Background(), secrets: s, prefix: "account/" + bob + "/"}
	if err := a.Set("account", []byte(`{"email":"alice@example.invalid","password":"secret-password","passwordToken":"token-A"}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Get("account"); !errors.Is(err, ErrSecretNotFound) {
		t.Fatalf("Bob can see Alice credentials: %v", err)
	}
	value, err := a.Get("account")
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(value, []byte("secret-password")) {
		t.Fatal("password persisted")
	}
	var result appstore.Account
	if err = json.Unmarshal(value, &result); err != nil || result.Password != "" || result.PasswordToken != "token-A" {
		t.Fatalf("session serialization broken: %v", err)
	}
}
func TestCookieIsolationRoundTripAndDeletion(t *testing.T) {
	s := newMemorySecrets()
	ctx := context.Background()
	a, err := newSecureJar(ctx, s, alice)
	if err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse("https://buy.itunes.apple.com/WebObjects/login")
	a.SetCookies(u, []*http.Cookie{{Name: "session", Value: "private-A", Secure: true, Path: "/"}})
	if err = a.Save(); err != nil {
		t.Fatal(err)
	}
	reloaded, err := newSecureJar(ctx, s, alice)
	if err != nil {
		t.Fatal(err)
	}
	if cs := reloaded.Cookies(u); len(cs) != 1 || cs[0].Value != "private-A" {
		t.Fatal("account cookie not restored")
	}
	b, err := newSecureJar(ctx, s, bob)
	if err != nil {
		t.Fatal(err)
	}
	if len(b.Cookies(u)) != 0 {
		t.Fatal("cookies shared between accounts")
	}
	reloaded.SetCookies(u, []*http.Cookie{{Name: "session", MaxAge: -1, Path: "/"}})
	if err = reloaded.Save(); err != nil {
		t.Fatal(err)
	}
	clean, _ := newSecureJar(ctx, s, alice)
	if len(clean.Cookies(u)) != 0 {
		t.Fatal("deleted cookie restored")
	}
}
func TestCanceledAuthenticationTransactionDoesNotPersist(t *testing.T) {
	s := newMemorySecrets()
	tx := newSecretTransaction(s)
	if err := tx.Set("account/"+alice+"/account", []byte("secret-token")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if !errors.Is(tx.Commit(ctx), context.Canceled) {
		t.Fatal("canceled transaction committed")
	}
	if _, err := s.Get("account/" + alice + "/account"); !errors.Is(err, ErrSecretNotFound) {
		t.Fatal("canceled auth persisted secret")
	}
}
func TestDownloadPathRejectsOverwriteSymlinkAndRelative(t *testing.T) {
	root := t.TempDir()
	existing := filepath.Join(root, "existing.partial")
	if err := os.WriteFile(existing, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	linked := filepath.Join(root, "link")
	if err := os.Symlink(root, linked); err != nil {
		t.Fatal(err)
	}
	// Resolve the system /var alias so the valid path itself contains no symlink ancestors.
	canonical, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"relative.partial", existing, filepath.Join(linked, "new.partial"), filepath.Join(root, "missing", "new.partial")} {
		if validateOutputPath(path) == nil {
			t.Fatalf("unsafe path accepted: %s", path)
		}
	}
	if err = validateOutputPath(filepath.Join(canonical, "new.partial")); err != nil {
		t.Fatalf("safe new staging path rejected: %v", err)
	}
	data, _ := os.ReadFile(existing)
	if string(data) != "keep" {
		t.Fatal("validation changed existing file")
	}
}
func TestSafeErrorDoesNotEchoUpstreamSecrets(t *testing.T) {
	for _, err := range []error{errors.New("password=secret otp=123456 https://apple.com/?token=private"), appstore.ErrLicenseRequired, appstore.ErrPasswordTokenExpired} {
		b, e := json.Marshal(classify(err))
		if e != nil {
			t.Fatal(e)
		}
		for _, secret := range []string{"secret", "123456", "?token=", "private"} {
			if strings.Contains(string(b), secret) {
				t.Fatalf("diagnostic leaked %q", secret)
			}
		}
	}
}

type eventSink struct {
	mu   sync.Mutex
	data []byte
	wake chan struct{}
}

func newSink() *eventSink { return &eventSink{wake: make(chan struct{}, 64)} }
func (e *eventSink) Write(b []byte) (int, error) {
	e.mu.Lock()
	e.data = append(e.data, b...)
	e.mu.Unlock()
	select {
	case e.wake <- struct{}{}:
	default:
	}
	return len(b), nil
}
func (e *eventSink) events() []Event {
	e.mu.Lock()
	defer e.mu.Unlock()
	var result []Event
	for _, line := range bytes.Split(e.data, []byte("\n")) {
		if len(line) > 0 {
			var v Event
			if json.Unmarshal(line, &v) == nil {
				result = append(result, v)
			}
		}
	}
	return result
}
func (e *eventSink) wait(t *testing.T, id, event string) Event {
	t.Helper()
	timer := time.NewTimer(3 * time.Second)
	defer timer.Stop()
	for {
		for _, v := range e.events() {
			if v.RequestID == id && v.Event == event {
				return v
			}
		}
		select {
		case <-e.wake:
		case <-timer.C:
			t.Fatalf("missing event %s %s: %+v", id, event, e.events())
		}
	}
}
func request(t *testing.T, w io.Writer, id, cmd string, payload any) {
	t.Helper()
	b, err := json.Marshal(map[string]any{"protocolVersion": 1, "requestId": id, "command": cmd, "payload": payload})
	if err != nil {
		t.Fatal(err)
	}
	b = append(b, '\n')
	if _, err = w.Write(b); err != nil {
		t.Fatal(err)
	}
}

type fakeCore struct {
	id      string
	ctx     context.Context
	secrets SecretStore
	login   func(string, string, string) (Account, error)
}

func (f *fakeCore) Login(e, p, c string) (Account, error) { return f.login(e, p, c) }
func (f *fakeCore) VersionInfo(AppRequest) (any, error)   { return map[string]any{"version": "1.0"}, nil }
func (f *fakeCore) Versions(AppRequest) (any, error) {
	return map[string]any{"externalVersionIds": []string{"123"}}, nil
}
func (f *fakeCore) Download(_ AppRequest, progress func(Progress)) (any, error) {
	progress(Progress{BytesReceived: 12})
	<-f.ctx.Done()
	return nil, f.ctx.Err()
}
func TestJSONProtocolAuthFlowCancellationAndNoSecretEvents(t *testing.T) {
	secrets := newMemorySecrets()
	out := newSink()
	factory := func(ctx context.Context, id string, s SecretStore) (Core, error) {
		f := &fakeCore{id: id, ctx: ctx, secrets: s}
		f.login = func(email, password, code string) (Account, error) {
			if password != "secret-password" {
				return Account{}, errors.New("bad-password")
			}
			if code == "" {
				return Account{}, appstore.ErrAuthCodeRequired
			}
			if err := s.Set("account/"+id+"/account", []byte(`{"email":"alice@example.invalid","passwordToken":"private-token"}`)); err != nil {
				return Account{}, err
			}
			return Account{ID: id, Email: email, Authenticated: true}, nil
		}
		return f, nil
	}
	in, w := io.Pipe()
	server := NewServer(secrets, factory, out)
	done := make(chan error, 1)
	go func() { done <- server.Run(in) }()
	defer w.Close()
	request(t, w, "hello", "hello", map[string]any{})
	out.wait(t, "hello", "ready")
	request(t, w, "login", "auth.begin", map[string]any{"accountId": alice, "email": "alice@example.invalid", "password": "secret-password"})
	out.wait(t, "login", "auth.codeRequired")
	request(t, w, "code", "auth.submitCode", map[string]any{"accountId": alice, "code": "123456"})
	out.wait(t, "code", "completed")
	out.wait(t, "login", "auth.succeeded")
	request(t, w, "accounts", "account.list", map[string]any{})
	event := out.wait(t, "accounts", "completed")
	b, _ := json.Marshal(event.Payload)
	if !strings.Contains(string(b), "alice@example.invalid") {
		t.Fatal("saved identity missing")
	}
	request(t, w, "download", "app.download", map[string]any{"accountId": alice, "bundleId": "org.example.app", "storeItemId": 123, "externalVersionId": "456", "outputPath": "/private/tmp/test.partial"})
	out.wait(t, "download", "download.progress")
	request(t, w, "cancel", "operation.cancel", map[string]any{"operationId": "download"})
	out.wait(t, "cancel", "completed")
	out.wait(t, "download", "canceled")
	request(t, w, "remove", "account.remove", map[string]any{"accountId": alice})
	out.wait(t, "remove", "completed")
	if _, err := secrets.Get("account/" + alice + "/account"); !errors.Is(err, ErrSecretNotFound) {
		t.Fatal("removed account still has credentials")
	}
	for _, event := range out.events() {
		b, _ := json.Marshal(event)
		for _, value := range []string{"secret-password", "123456", "private-token"} {
			if bytes.Contains(b, []byte(value)) {
				t.Fatalf("protocol leaked %q", value)
			}
		}
	}
	_ = w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
func TestCancelLoginBeforeUpstreamBoundaryNeverCommits(t *testing.T) {
	secrets := newMemorySecrets()
	out := newSink()
	release := make(chan struct{})
	entered := make(chan struct{})
	factory := func(ctx context.Context, id string, s SecretStore) (Core, error) {
		f := &fakeCore{id: id, ctx: ctx, secrets: s}
		f.login = func(e, p, c string) (Account, error) {
			close(entered)
			<-release
			_ = s.Set("account/"+id+"/account", []byte("sensitive-token"))
			return Account{ID: id, Email: e, Authenticated: true}, nil
		}
		return f, nil
	}
	in, w := io.Pipe()
	server := NewServer(secrets, factory, out)
	done := make(chan error, 1)
	go func() { done <- server.Run(in) }()
	request(t, w, "login", "auth.begin", map[string]any{"accountId": alice, "email": "alice@example.invalid", "password": "secret"})
	<-entered
	request(t, w, "cancel", "auth.cancel", map[string]any{"accountId": alice})
	out.wait(t, "cancel", "completed")
	close(release)
	out.wait(t, "login", "canceled")
	if _, err := secrets.Get("account/" + alice + "/account"); !errors.Is(err, ErrSecretNotFound) {
		t.Fatal("canceled login persisted token")
	}
	_ = w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestIdentityCannotReplaceDifferentLicenseOwner(t *testing.T) {
	secrets := newMemorySecrets()
	k := scopedKeychain{ctx: context.Background(), secrets: secrets, prefix: "account/" + alice + "/"}
	if err := k.Set("account", []byte(`{"email":"first@example.invalid","directoryServicesIdentifier":"person-1","passwordToken":"original-session"}`)); err != nil {
		t.Fatal(err)
	}
	err := k.Set("account", []byte(`{"email":"other@example.invalid","directoryServicesIdentifier":"person-2","passwordToken":"other-session"}`))
	var typed *BridgeError
	if !errors.As(err, &typed) || typed.Code != "account.mismatch" {
		t.Fatal("different license owner replaced existing identity")
	}
	b, _ := k.Get("account")
	if !bytes.Contains(b, []byte("original-session")) {
		t.Fatal("original identity lost")
	}
}

func TestUppercaseUUIDFromSwiftUsesSameNamespace(t *testing.T) {
	const id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	secrets := newMemorySecrets()
	_ = secrets.Set("account/"+id+"/account", []byte("original"))
	_ = saveAccounts(secrets, []Account{{ID: id, Email: "sample@example.invalid", Authenticated: true}})
	out := newSink()
	factory := func(ctx context.Context, accountID string, s SecretStore) (Core, error) {
		if accountID != id {
			t.Error("UUID not normalized")
		}
		return &fakeCore{id: accountID, ctx: ctx}, nil
	}
	in, w := io.Pipe()
	server := NewServer(secrets, factory, out)
	done := make(chan error, 1)
	go func() { done <- server.Run(in) }()
	request(t, w, "version", "app.versionInfo", map[string]any{"accountId": strings.ToUpper(id), "storeItemId": 123, "bundleId": "org.example"})
	out.wait(t, "version", "completed")
	request(t, w, "remove", "account.remove", map[string]any{"accountId": strings.ToUpper(id)})
	out.wait(t, "remove", "completed")
	if _, err := secrets.Get("account/" + id + "/account"); !errors.Is(err, ErrSecretNotFound) {
		t.Fatal("uppercase UUID left credentials behind")
	}
	_ = w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestVerificationReservesCodeUntilNewPrompt(t *testing.T) {
	secrets := newMemorySecrets()
	out := newSink()
	release := make(chan struct{})
	factory := func(ctx context.Context, id string, s SecretStore) (Core, error) {
		f := &fakeCore{id: id, ctx: ctx, secrets: s}
		f.login = func(e, p, c string) (Account, error) {
			if c == "" {
				return Account{}, appstore.ErrAuthCodeRequired
			}
			<-release
			return Account{ID: id, Email: e, Authenticated: true}, nil
		}
		return f, nil
	}
	in, w := io.Pipe()
	server := NewServer(secrets, factory, out)
	done := make(chan error, 1)
	go func() { done <- server.Run(in) }()
	request(t, w, "login", "auth.begin", map[string]any{"accountId": alice, "email": "alice@example.invalid", "password": "secret"})
	out.wait(t, "login", "auth.codeRequired")
	request(t, w, "first-code", "auth.submitCode", map[string]any{"accountId": alice, "code": "123456"})
	out.wait(t, "first-code", "completed")
	request(t, w, "duplicate-code", "auth.submitCode", map[string]any{"accountId": alice, "code": "654321"})
	out.wait(t, "duplicate-code", "failed")
	close(release)
	out.wait(t, "login", "auth.succeeded")
	_ = w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestInvalidCodesStopAfterFiveActualVerifications(t *testing.T) {
	secrets := newMemorySecrets()
	out := newSink()
	calls := 0
	factory := func(ctx context.Context, id string, s SecretStore) (Core, error) {
		f := &fakeCore{id: id, ctx: ctx, secrets: s}
		f.login = func(e, p, c string) (Account, error) {
			calls++
			if c == "" {
				return Account{}, appstore.ErrAuthCodeRequired
			}
			return Account{}, errors.New("apple did not complete verification; try a fresh 2FA code")
		}
		return f, nil
	}
	in, w := io.Pipe()
	server := NewServer(secrets, factory, out)
	done := make(chan error, 1)
	go func() { done <- server.Run(in) }()
	request(t, w, "login", "auth.begin", map[string]any{"accountId": alice, "email": "alice@example.invalid", "password": "secret"})
	out.wait(t, "login", "auth.codeRequired")
	for i := 0; i < 5; i++ {
		// Wait for each distinct prompt rather than matching the initial prompt again.
		deadline := time.Now().Add(3 * time.Second)
		for {
			count := 0
			for _, event := range out.events() {
				if event.RequestID == "login" && event.Event == "auth.codeRequired" {
					count++
				}
			}
			if count == i+1 {
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("verification prompt missing")
			}
			time.Sleep(time.Millisecond)
		}
		id := string(rune('a' + i))
		request(t, w, id, "auth.submitCode", map[string]any{"accountId": alice, "code": "123456"})
		out.wait(t, id, "completed")
	}
	failed := out.wait(t, "login", "failed")
	if failed.Error == nil || failed.Error.Code != "auth.tooManyAttempts" {
		t.Fatal("wrong terminal state")
	}
	_ = w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if calls != 6 {
		t.Fatalf("got %d login calls, need initial + five actual OTP verifications", calls)
	}
}
