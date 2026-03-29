// Package meter provides metering middleware for campfire-hosting operations.
// It emits UsageEvents to Forge via the billingclient for every metered
// cf-mcp operation (campfire_init, campfire_send, campfire_read, campfire_join,
// beacon operations).
//
// Metering is fail-open: errors are logged but never block campfire operations.
package meter

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/3dl-dev/forge/pkg/billingclient"
	"github.com/google/uuid"
)

// Operation identifies a metered cf-mcp operation.
type Operation string

const (
	OpMessageSend  Operation = "message_send"
	OpMessageRead  Operation = "message_read"
	OpCampfireInit Operation = "campfire_init"
	OpCampfireJoin Operation = "campfire_join"
	OpBeaconRelay  Operation = "beacon_relay"
)

// Meter emits usage events to Forge for metered campfire-hosting operations.
// All methods are safe for concurrent use.
type Meter struct {
	client    *billingclient.Client
	accountID string
	logger    *slog.Logger

	mu       sync.Mutex
	emitted  int64
	failures int64
}

// New creates a Meter. The client must have BaseURL and ServiceKey configured.
// accountID is the Forge account to bill usage against.
func New(client *billingclient.Client, accountID string, logger *slog.Logger) *Meter {
	if logger == nil {
		logger = slog.Default()
	}
	return &Meter{
		client:    client,
		accountID: accountID,
		logger:    logger,
	}
}

// Record emits a usage event for the given operation. It is fire-and-forget:
// errors are logged but never returned, per the fail-open metering policy.
// The call is synchronous — use RecordAsync for non-blocking emission.
func (m *Meter) Record(ctx context.Context, op Operation, quantity float64) {
	event := billingclient.UsageEvent{
		AccountID:      m.accountID,
		ServiceID:      "campfire-hosting",
		UnitType:       string(op),
		Quantity:       quantity,
		Status:         "ok",
		Timestamp:      time.Now().UTC(),
		IdempotencyKey: uuid.NewString(),
	}

	if err := m.client.Ingest(ctx, event); err != nil {
		m.mu.Lock()
		m.failures++
		m.mu.Unlock()
		m.logger.Warn("metering: failed to emit usage event",
			"op", string(op),
			"quantity", quantity,
			"error", err,
		)
		return
	}

	m.mu.Lock()
	m.emitted++
	m.mu.Unlock()
}

// RecordAsync emits a usage event in a background goroutine.
// Uses a detached context so the emission completes even if the request
// context is cancelled.
func (m *Meter) RecordAsync(op Operation, quantity float64) {
	go m.Record(context.WithoutCancel(context.Background()), op, quantity)
}

// Stats returns the number of successfully emitted and failed events.
func (m *Meter) Stats() (emitted, failures int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.emitted, m.failures
}

// RecordWithDetails emits a usage event with additional attribution fields.
func (m *Meter) RecordWithDetails(ctx context.Context, op Operation, quantity float64, sessionID, agentType string) {
	event := billingclient.UsageEvent{
		AccountID:      m.accountID,
		ServiceID:      "campfire-hosting",
		UnitType:       string(op),
		Quantity:       quantity,
		Status:         "ok",
		SessionID:      sessionID,
		AgentType:      agentType,
		Timestamp:      time.Now().UTC(),
		IdempotencyKey: uuid.NewString(),
	}

	if err := m.client.Ingest(ctx, event); err != nil {
		m.mu.Lock()
		m.failures++
		m.mu.Unlock()
		m.logger.Warn("metering: failed to emit usage event",
			"op", string(op),
			"quantity", quantity,
			"session_id", sessionID,
			"error", err,
		)
		return
	}

	m.mu.Lock()
	m.emitted++
	m.mu.Unlock()
}

// ClassifyOperation maps a cf-mcp tool name to a metered Operation.
// Returns the Operation and true if the tool is metered, or ("", false) if not.
func ClassifyOperation(toolName string) (Operation, bool) {
	switch toolName {
	case "campfire_send":
		return OpMessageSend, true
	case "campfire_read":
		return OpMessageRead, true
	case "campfire_init":
		return OpCampfireInit, true
	case "campfire_join":
		return OpCampfireJoin, true
	case "beacon_register", "campfire_discover":
		return OpBeaconRelay, true
	default:
		return "", false
	}
}

// NewFromEnv creates a Meter from environment variable conventions:
//   - FORGE_BASE_URL: Forge API base URL
//   - FORGE_SERVICE_KEY: RoleService API key
//   - FORGE_ACCOUNT_ID: Account to bill against
func NewFromEnv(baseURL, serviceKey, accountID string, logger *slog.Logger) (*Meter, error) {
	if baseURL == "" {
		return nil, fmt.Errorf("meter: FORGE_BASE_URL is required")
	}
	if serviceKey == "" {
		return nil, fmt.Errorf("meter: FORGE_SERVICE_KEY is required")
	}
	if accountID == "" {
		return nil, fmt.Errorf("meter: FORGE_ACCOUNT_ID is required")
	}

	client := &billingclient.Client{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
	}
	return New(client, accountID, logger), nil
}
