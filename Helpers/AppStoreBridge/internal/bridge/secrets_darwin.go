//go:build darwin

package bridge

import (
	"errors"
	"fmt"
	keychain "github.com/byteness/go-keychain"
)

type systemSecrets struct{}

func NewSystemSecrets() SecretStore { return systemSecrets{} }
func (systemSecrets) Get(k string) ([]byte, error) {
	b, err := keychain.GetGenericPassword(keychainService, k, "", "")
	if errors.Is(err, keychain.ErrorItemNotFound) || (err == nil && len(b) == 0) {
		return nil, ErrSecretNotFound
	}
	return b, safeKeychainError(err)
}
func (systemSecrets) Set(k string, b []byte) error {
	item := keychain.NewGenericPassword(keychainService, k, "iPhone App Transfer App Store session", b, "")
	item.SetAccessible(keychain.AccessibleWhenUnlockedThisDeviceOnly)
	err := keychain.AddItem(item)
	if !errors.Is(err, keychain.ErrorDuplicateItem) {
		return safeKeychainError(err)
	}
	query := keychain.NewItem()
	query.SetSecClass(keychain.SecClassGenericPassword)
	query.SetService(keychainService)
	query.SetAccount(k)
	update := keychain.NewItem()
	update.SetData(b)
	return safeKeychainError(keychain.UpdateItem(query, update))
}
func (systemSecrets) Delete(k string) error {
	err := keychain.DeleteGenericPasswordItem(keychainService, k)
	if errors.Is(err, keychain.ErrorItemNotFound) {
		return nil
	}
	return safeKeychainError(err)
}

func safeKeychainError(err error) error {
	if err == nil {
		return nil
	}
	message := "macOS Keychain is unavailable. Try again from the installed app; unlock the login keychain if prompted."
	var status keychain.Error
	if errors.As(err, &status) {
		message = fmt.Sprintf("macOS Keychain is unavailable (OSStatus %d). Try again from the installed app; unlock the login keychain if prompted.", int(status))
	}
	return &BridgeError{Code: "keychain.unavailable", Message: message, Retryable: true}
}
