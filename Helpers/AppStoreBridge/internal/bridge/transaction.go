package bridge

import (
	"context"
	"sync"
)

type secretTransaction struct {
	mu      sync.Mutex
	parent  SecretStore
	pending map[string][]byte
	deleted map[string]bool
}

func newSecretTransaction(s SecretStore) *secretTransaction {
	return &secretTransaction{parent: s, pending: map[string][]byte{}, deleted: map[string]bool{}}
}
func (t *secretTransaction) Get(k string) ([]byte, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.deleted[k] {
		return nil, ErrSecretNotFound
	}
	if b, ok := t.pending[k]; ok {
		return append([]byte(nil), b...), nil
	}
	return t.parent.Get(k)
}
func (t *secretTransaction) Set(k string, b []byte) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.pending[k] = append([]byte(nil), b...)
	delete(t.deleted, k)
	return nil
}
func (t *secretTransaction) Delete(k string) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.pending, k)
	t.deleted[k] = true
	return nil
}
func (t *secretTransaction) Commit(ctx context.Context) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	for k, b := range t.pending {
		if err := t.parent.Set(k, b); err != nil {
			return err
		}
	}
	for k := range t.deleted {
		if err := t.parent.Delete(k); err != nil {
			return err
		}
	}
	return nil
}
