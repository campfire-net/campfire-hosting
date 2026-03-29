package meter

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/3dl-dev/forge/pkg/billingclient"
)

// capturedEvent holds a decoded ingest request for test assertions.
type capturedEvent struct {
	AccountID      string  `json:"account_id"`
	ServiceID      string  `json:"service_id"`
	UnitType       string  `json:"unit_type"`
	Quantity       float64 `json:"quantity"`
	Status         string  `json:"status"`
	IdempotencyKey string  `json:"idempotency_key"`
	SessionID      string  `json:"session_id,omitempty"`
	AgentType      string  `json:"agent_type,omitempty"`
}

func newTestServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, *billingclient.Client) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	client := &billingclient.Client{
		BaseURL:     srv.URL,
		ServiceKey:  "forge-sk-test",
		RetryDelays: []time.Duration{time.Millisecond}, // minimal retry delay in tests
	}
	return srv, client
}

func TestRecord_Success(t *testing.T) {
	var mu sync.Mutex
	var events []capturedEvent

	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		var ev capturedEvent
		if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
			t.Errorf("decode request: %v", err)
			http.Error(w, "bad request", 400)
			return
		}
		mu.Lock()
		events = append(events, ev)
		mu.Unlock()
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "created"})
	})

	m := New(client, "acct-test-123", nil)
	m.Record(context.Background(), OpMessageSend, 1.0)

	mu.Lock()
	defer mu.Unlock()
	if len(events) != 1 {
		t.Fatalf("got %d events, want 1", len(events))
	}

	ev := events[0]
	if ev.AccountID != "acct-test-123" {
		t.Errorf("account_id = %q, want %q", ev.AccountID, "acct-test-123")
	}
	if ev.ServiceID != "campfire-hosting" {
		t.Errorf("service_id = %q, want %q", ev.ServiceID, "campfire-hosting")
	}
	if ev.UnitType != "message_send" {
		t.Errorf("unit_type = %q, want %q", ev.UnitType, "message_send")
	}
	if ev.Quantity != 1.0 {
		t.Errorf("quantity = %f, want 1.0", ev.Quantity)
	}
	if ev.IdempotencyKey == "" {
		t.Error("idempotency_key should not be empty")
	}

	emitted, failures := m.Stats()
	if emitted != 1 || failures != 0 {
		t.Errorf("stats: emitted=%d failures=%d, want 1/0", emitted, failures)
	}
}

func TestRecord_FailOpen(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})

	m := New(client, "acct-test-123", nil)
	m.Record(context.Background(), OpCampfireInit, 1.0)

	// Should not panic or return error — fail-open.
	emitted, failures := m.Stats()
	if emitted != 0 || failures != 1 {
		t.Errorf("stats: emitted=%d failures=%d, want 0/1", emitted, failures)
	}
}

func TestRecordAsync(t *testing.T) {
	var mu sync.Mutex
	received := false

	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		received = true
		mu.Unlock()
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "created"})
	})

	m := New(client, "acct-test-123", nil)
	m.RecordAsync(OpMessageRead, 5.0)

	// Wait for async goroutine to complete.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		done := received
		mu.Unlock()
		if done {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	mu.Lock()
	if !received {
		t.Error("RecordAsync did not send event within timeout")
	}
	mu.Unlock()
}

func TestRecordWithDetails(t *testing.T) {
	var mu sync.Mutex
	var events []capturedEvent

	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		var ev capturedEvent
		json.NewDecoder(r.Body).Decode(&ev)
		mu.Lock()
		events = append(events, ev)
		mu.Unlock()
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "created"})
	})

	m := New(client, "acct-test-123", nil)
	m.RecordWithDetails(context.Background(), OpCampfireJoin, 1.0, "sess-abc", "implementer")

	mu.Lock()
	defer mu.Unlock()
	if len(events) != 1 {
		t.Fatalf("got %d events, want 1", len(events))
	}
	if events[0].SessionID != "sess-abc" {
		t.Errorf("session_id = %q, want %q", events[0].SessionID, "sess-abc")
	}
	if events[0].AgentType != "implementer" {
		t.Errorf("agent_type = %q, want %q", events[0].AgentType, "implementer")
	}
}

func TestClassifyOperation(t *testing.T) {
	tests := []struct {
		tool   string
		wantOp Operation
		wantOk bool
	}{
		{"campfire_send", OpMessageSend, true},
		{"campfire_read", OpMessageRead, true},
		{"campfire_init", OpCampfireInit, true},
		{"campfire_join", OpCampfireJoin, true},
		{"beacon_register", OpBeaconRelay, true},
		{"campfire_discover", OpBeaconRelay, true},
		{"campfire_ls", "", false},
		{"campfire_members", "", false},
		{"unknown_tool", "", false},
	}

	for _, tt := range tests {
		op, ok := ClassifyOperation(tt.tool)
		if op != tt.wantOp || ok != tt.wantOk {
			t.Errorf("ClassifyOperation(%q) = (%q, %v), want (%q, %v)",
				tt.tool, op, ok, tt.wantOp, tt.wantOk)
		}
	}
}

func TestNewFromEnv_Validation(t *testing.T) {
	tests := []struct {
		name       string
		baseURL    string
		serviceKey string
		accountID  string
		wantErr    bool
	}{
		{"all set", "https://forge.3dl.dev", "forge-sk-test", "acct-123", false},
		{"missing baseURL", "", "forge-sk-test", "acct-123", true},
		{"missing serviceKey", "https://forge.3dl.dev", "", "acct-123", true},
		{"missing accountID", "https://forge.3dl.dev", "forge-sk-test", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewFromEnv(tt.baseURL, tt.serviceKey, tt.accountID, nil)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewFromEnv() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
