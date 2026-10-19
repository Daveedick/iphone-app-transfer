package bridge

import (
	"encoding/json"
	"io"
	"sync"
)

const ProtocolVersion = 1
const HelperVersion = "0.1.0"
const UpstreamVersion = "2.7.0"
const MaxMessageBytes = 1024 * 1024

type Request struct {
	ProtocolVersion int             `json:"protocolVersion"`
	RequestID       string          `json:"requestId"`
	Command         string          `json:"command"`
	Payload         json.RawMessage `json:"payload"`
}

type Event struct {
	ProtocolVersion int          `json:"protocolVersion"`
	RequestID       string       `json:"requestId"`
	OperationID     string       `json:"operationId,omitempty"`
	Event           string       `json:"event"`
	Payload         any          `json:"payload,omitempty"`
	Error           *BridgeError `json:"error,omitempty"`
}

type BridgeError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

func (e *BridgeError) Error() string { return e.Code }

type Writer struct {
	mu      sync.Mutex
	encoder *json.Encoder
}

func NewWriter(out io.Writer) *Writer { return &Writer{encoder: json.NewEncoder(out)} }
func (w *Writer) Send(id, event string, payload any, err *BridgeError) {
	w.mu.Lock()
	defer w.mu.Unlock()
	_ = w.encoder.Encode(Event{ProtocolVersion: ProtocolVersion, RequestID: id, OperationID: id, Event: event, Payload: payload, Error: err})
}

type Account struct {
	ID            string `json:"id"`
	Email         string `json:"email"`
	Name          string `json:"name"`
	Storefront    string `json:"storefront"`
	Authenticated bool   `json:"authenticated"`
}

type AppRequest struct {
	AccountID         string `json:"accountId"`
	StoreItemID       int64  `json:"storeItemId"`
	BundleID          string `json:"bundleId"`
	ExternalVersionID string `json:"externalVersionId"`
	OutputPath        string `json:"outputPath"`
}

type Progress struct {
	BytesReceived int64    `json:"bytesReceived"`
	TotalBytes    int64    `json:"totalBytes,omitempty"`
	Fraction      *float64 `json:"fraction,omitempty"`
}
