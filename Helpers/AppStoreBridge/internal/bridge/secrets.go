package bridge

import (
	"encoding/json"
	"errors"
	"sync"
)

var ErrSecretNotFound = errors.New("secret not found")

const keychainService = "com.apptransfer.AppStoreBridge.v1"

type SecretStore interface {
	Get(string) ([]byte, error)
	Set(string, []byte) error
	Delete(string) error
}

type memorySecrets struct {
	mu   sync.Mutex
	data map[string][]byte
}

func newMemorySecrets() *memorySecrets { return &memorySecrets{data: map[string][]byte{}} }
func (m *memorySecrets) Get(k string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	b, ok := m.data[k]
	if !ok {
		return nil, ErrSecretNotFound
	}
	return append([]byte(nil), b...), nil
}
func (m *memorySecrets) Set(k string, b []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[k] = append([]byte(nil), b...)
	return nil
}
func (m *memorySecrets) Delete(k string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.data, k)
	return nil
}

func loadAccounts(s SecretStore) ([]Account, error) {
	b, err := s.Get("accounts")
	if errors.Is(err, ErrSecretNotFound) {
		return []Account{}, nil
	}
	if err != nil {
		return nil, err
	}
	var result []Account
	if err = json.Unmarshal(b, &result); err != nil {
		return nil, err
	}
	return result, nil
}
func saveAccounts(s SecretStore, a []Account) error {
	b, err := json.Marshal(a)
	if err != nil {
		return err
	}
	return s.Set("accounts", b)
}
