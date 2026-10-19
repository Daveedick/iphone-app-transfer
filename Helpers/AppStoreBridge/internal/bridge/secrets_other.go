//go:build !darwin

package bridge

import "errors"

type unavailableSecrets struct{}

func NewSystemSecrets() SecretStore { return unavailableSecrets{} }
func (unavailableSecrets) Get(string) ([]byte, error) {
	return nil, errors.New("macOS Keychain required")
}
func (unavailableSecrets) Set(string, []byte) error { return errors.New("macOS Keychain required") }
func (unavailableSecrets) Delete(string) error      { return errors.New("macOS Keychain required") }
