//go:build darwin

package bridge

import (
	"bytes"
	"errors"
	"os"
	"testing"
)

// Explicit opt-in only: creates then deletes a synthetic item in our own service.
func TestSystemKeychainRoundTrip(t *testing.T) {
	if os.Getenv("APP_TRANSFER_RUN_KEYCHAIN_TEST") != "1" {
		t.Skip("opt-in native Keychain integration check")
	}
	key := "self-test/" + uuid()
	store := NewSystemSecrets()
	defer store.Delete(key)
	if err := store.Set(key, []byte("synthetic-public-test-data")); err != nil {
		t.Fatal(err)
	}
	b, err := store.Get(key)
	if err != nil || !bytes.Equal(b, []byte("synthetic-public-test-data")) {
		t.Fatalf("Keychain data roundtrip failed: %v", err)
	}
	if err = store.Set(key, []byte("updated-public-test-data")); err != nil {
		t.Fatal(err)
	}
	b, err = store.Get(key)
	if err != nil || !bytes.Equal(b, []byte("updated-public-test-data")) {
		t.Fatalf("Keychain update failed: %v", err)
	}
	if err = store.Delete(key); err != nil {
		t.Fatal(err)
	}
	if _, err = store.Get(key); !errors.Is(err, ErrSecretNotFound) {
		t.Fatalf("Keychain deletion failed: %v", err)
	}
}
