package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strings"
	"sync"
	"time"
)

type storedCookie struct {
	Origin string      `json:"origin"`
	Cookie http.Cookie `json:"cookie"`
}
type secureJar struct {
	mu      sync.Mutex
	jar     *cookiejar.Jar
	records map[string]storedCookie
	secrets SecretStore
	key     string
	ctx     context.Context
}

func newSecureJar(ctx context.Context, s SecretStore, id string) (*secureJar, error) {
	j, _ := cookiejar.New(nil)
	r := &secureJar{jar: j, records: map[string]storedCookie{}, secrets: s, key: "account/" + id + "/cookies", ctx: ctx}
	b, err := s.Get(r.key)
	if errors.Is(err, ErrSecretNotFound) {
		return r, nil
	}
	if err != nil {
		return nil, err
	}
	var stored []storedCookie
	if err = json.Unmarshal(b, &stored); err != nil {
		return nil, err
	}
	for _, v := range stored {
		u, e := url.Parse(v.Origin)
		if e == nil && (v.Cookie.Expires.IsZero() || v.Cookie.Expires.After(time.Now())) {
			r.jar.SetCookies(u, []*http.Cookie{&v.Cookie})
			r.records[cookieKey(u, &v.Cookie)] = v
		}
	}
	return r, nil
}
func (j *secureJar) Cookies(u *url.URL) []*http.Cookie {
	j.mu.Lock()
	defer j.mu.Unlock()
	return j.jar.Cookies(u)
}
func cookieKey(u *url.URL, c *http.Cookie) string {
	domain := c.Domain
	if domain == "" {
		domain = u.Hostname()
	}
	return strings.TrimPrefix(strings.ToLower(domain), ".") + "\n" + c.Path + "\n" + c.Name
}
func (j *secureJar) SetCookies(u *url.URL, cookies []*http.Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.jar.SetCookies(u, cookies)
	for _, v := range cookies {
		c := *v
		if c.Path == "" {
			i := strings.LastIndex(u.Path, "/")
			if i <= 0 {
				c.Path = "/"
			} else {
				c.Path = u.Path[:i]
			}
		}
		k := cookieKey(u, &c)
		if c.MaxAge < 0 || (!c.Expires.IsZero() && c.Expires.Before(time.Now())) {
			delete(j.records, k)
			continue
		}
		if c.MaxAge > 0 {
			c.Expires = time.Now().Add(time.Duration(c.MaxAge) * time.Second)
			c.MaxAge = 0
		}
		j.records[k] = storedCookie{Origin: u.Scheme + "://" + u.Host + c.Path, Cookie: c}
	}
}
func (j *secureJar) Save() error {
	j.mu.Lock()
	defer j.mu.Unlock()
	if err := j.ctx.Err(); err != nil {
		return err
	}
	values := make([]storedCookie, 0, len(j.records))
	for _, v := range j.records {
		if v.Cookie.Expires.IsZero() || v.Cookie.Expires.After(time.Now()) {
			values = append(values, v)
		}
	}
	b, err := json.Marshal(values)
	if err != nil {
		return err
	}
	return j.secrets.Set(j.key, b)
}
