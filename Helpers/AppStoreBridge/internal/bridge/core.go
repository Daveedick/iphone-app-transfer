package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/majd/ipatool/v2/pkg/util/machine"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
)

type Core interface {
	Login(email, password, code string) (Account, error)
	VersionInfo(AppRequest) (any, error)
	Versions(AppRequest) (any, error)
	Download(AppRequest, func(Progress)) (any, error)
}
type CoreFactory func(context.Context, string, SecretStore) (Core, error)
type upstreamCore struct {
	ctx   context.Context
	id    string
	store appstore.AppStore
	jar   *secureJar
}
type scopedKeychain struct {
	ctx     context.Context
	secrets SecretStore
	prefix  string
}

func (k scopedKeychain) Get(key string) ([]byte, error) { return k.secrets.Get(k.prefix + key) }
func (k scopedKeychain) Set(key string, b []byte) error {
	if err := k.ctx.Err(); err != nil {
		return err
	}
	// Upstream persists the original password. Keep only renewable session credentials.
	if key == "account" {
		var a appstore.Account
		if err := json.Unmarshal(b, &a); err != nil {
			return err
		}
		if previous, e := k.secrets.Get(k.prefix + key); e == nil {
			var old appstore.Account
			if json.Unmarshal(previous, &old) == nil && old.DirectoryServicesID != "" && a.DirectoryServicesID != "" && old.DirectoryServicesID != a.DirectoryServicesID {
				return &BridgeError{Code: "account.mismatch", Message: "This is a different Apple Account. Add it as a new account to preserve existing app ownership.", Retryable: false}
			}
		}
		a.Password = ""
		clean, err := json.Marshal(a)
		if err != nil {
			return err
		}
		b = clean
	}
	return k.secrets.Set(k.prefix+key, b)
}
func (k scopedKeychain) Remove(key string) error { return k.secrets.Delete(k.prefix + key) }
func NewCoreFactory() CoreFactory {
	return func(ctx context.Context, id string, secrets SecretStore) (Core, error) {
		jar, err := newSecureJar(ctx, secrets, id)
		if err != nil {
			return nil, err
		}
		operatingSystem := operatingsystem.New()
		return &upstreamCore{ctx: ctx, id: id, jar: jar, store: appstore.NewAppStore(appstore.Args{Keychain: scopedKeychain{ctx: ctx, secrets: secrets, prefix: "account/" + id + "/"}, CookieJar: jar, OperatingSystem: operatingSystem, Machine: machine.New(machine.Args{OS: operatingSystem})})}, nil
	}
}
func (u *upstreamCore) Login(email, password, code string) (Account, error) {
	result, err := u.store.Login(appstore.LoginInput{Email: email, Password: password, AuthCode: code})
	if err != nil {
		return Account{}, err
	}
	if err = u.ctx.Err(); err != nil {
		return Account{}, err
	}
	if err = u.jar.Save(); err != nil {
		return Account{}, err
	}
	a := result.Account
	result.Account.Password = ""
	return Account{ID: u.id, Email: a.Email, Name: a.Name, Storefront: a.StoreFront, Authenticated: true}, nil
}
func (u *upstreamCore) account() (appstore.Account, error) {
	a, err := u.store.AccountInfo()
	if err != nil {
		return appstore.Account{}, &BridgeError{Code: "account.required", Message: "Sign in to this Apple Account again.", Retryable: true}
	}
	return a.Account, nil
}
func (r AppRequest) app() appstore.App { return appstore.App{ID: r.StoreItemID, BundleID: r.BundleID} }
func (u *upstreamCore) VersionInfo(r AppRequest) (any, error) {
	a, err := u.account()
	if err != nil {
		return nil, err
	}
	v, err := u.store.GetVersionMetadata(appstore.GetVersionMetadataInput{Context: u.ctx, Account: a, App: r.app(), VersionID: r.ExternalVersionID, Platform: appstore.PlatformIPhone})
	if err != nil {
		return nil, err
	}
	return map[string]any{"accountId": u.id, "storeItemId": r.StoreItemID, "bundleId": r.BundleID, "externalVersionId": r.ExternalVersionID, "version": v.DisplayVersion, "releaseDate": v.ReleaseDate.UTC().Format(time.RFC3339)}, nil
}
func (u *upstreamCore) Versions(r AppRequest) (any, error) {
	a, err := u.account()
	if err != nil {
		return nil, err
	}
	v, err := u.store.ListVersions(appstore.ListVersionsInput{Context: u.ctx, Account: a, App: r.app(), Platform: appstore.PlatformIPhone})
	if err != nil {
		return nil, err
	}
	return map[string]any{"externalVersionIds": v.ExternalVersionIdentifiers, "latestExternalVersionId": v.LatestExternalVersionID}, nil
}
func (u *upstreamCore) Download(r AppRequest, progress func(Progress)) (any, error) {
	a, err := u.account()
	if err != nil {
		return nil, err
	}
	if err = validateOutputPath(r.OutputPath); err != nil {
		return nil, err
	}
	done := make(chan struct{})
	progressStopped := make(chan struct{})
	go func() {
		defer close(progressStopped)
		ticker := time.NewTicker(200 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if stat, e := os.Stat(r.OutputPath + ".tmp"); e == nil {
					progress(Progress{BytesReceived: stat.Size()})
				}
			case <-done:
				return
			}
		}
	}()
	out, err := u.store.Download(appstore.DownloadInput{Context: u.ctx, Account: a, App: r.app(), OutputPath: r.OutputPath, Progress: nil, ExternalVersionID: r.ExternalVersionID, Platform: appstore.PlatformIPhone})
	close(done)
	<-progressStopped
	if err != nil {
		return nil, err
	}
	if err = u.ctx.Err(); err != nil {
		return nil, err
	}
	// Download returns license data separately; match the official CLI's required
	// final IPA rewrite/SINF injection before reporting a usable archive.
	if err = u.store.ReplicateSinf(appstore.ReplicateSinfInput{Sinfs: out.Sinfs, PackagePath: out.DestinationPath}); err != nil {
		return nil, err
	}
	if err = u.ctx.Err(); err != nil {
		return nil, err
	}
	_ = os.Chmod(out.DestinationPath, 0600)
	st, err := os.Stat(out.DestinationPath)
	if err != nil {
		return nil, err
	}
	return map[string]any{"destinationPath": out.DestinationPath, "accountId": u.id, "storeItemId": r.StoreItemID, "bundleId": r.BundleID, "externalVersionId": r.ExternalVersionID, "bytes": st.Size()}, nil
}
func validateOutputPath(path string) error {
	invalid := func() error {
		return &BridgeError{Code: "output.invalid", Message: "Choose a new absolute path in the managed library staging directory.", Retryable: false}
	}
	if path == "" || !filepath.IsAbs(path) || filepath.Clean(path) != path || strings.ContainsRune(path, 0) {
		return invalid()
	}
	parent, err := os.Lstat(filepath.Dir(path))
	if err != nil || !parent.IsDir() || parent.Mode()&os.ModeSymlink != 0 {
		return invalid()
	}
	for dir := filepath.Dir(path); dir != "/"; dir = filepath.Dir(dir) {
		info, e := os.Lstat(dir)
		if e != nil || info.Mode()&os.ModeSymlink != 0 {
			return invalid()
		}
	}
	for _, p := range []string{path, path + ".tmp"} {
		if _, e := os.Lstat(p); !errors.Is(e, os.ErrNotExist) {
			return invalid()
		}
	}
	return nil
}
func classify(err error) *BridgeError {
	var typed *BridgeError
	if errors.As(err, &typed) {
		return typed
	}
	if errors.Is(err, context.Canceled) {
		return &BridgeError{Code: "operation.canceled", Message: "Operation canceled.", Retryable: true}
	}
	if errors.Is(err, appstore.ErrLicenseRequired) {
		return &BridgeError{Code: "license.required", Message: "This Apple Account does not have a download license for this app. Choose the account that obtained it.", Retryable: true}
	}
	if errors.Is(err, appstore.ErrPasswordTokenExpired) {
		return &BridgeError{Code: "account.expired", Message: "Apple Account session expired. Sign in again.", Retryable: true}
	}
	var n net.Error
	if errors.As(err, &n) {
		return &BridgeError{Code: "network.failed", Message: "Could not reach Apple. Check the connection and try again.", Retryable: true}
	}
	// Do not return err.Error(): upstream wraps raw Apple payloads, URL query strings and auth metadata.
	return &BridgeError{Code: "apple.requestFailed", Message: "Apple did not complete this request. Check the account and app version, then try again. First sign-in may also need to download authentication components.", Retryable: true}
}
