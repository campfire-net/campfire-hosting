// Integration test — runs against a live Forge instance.
// Requires environment variables: FORGE_BASE_URL, FORGE_SERVICE_KEY, FORGE_ACCOUNT_ID.
// Skipped automatically when env vars are missing.
//
//	go test ./pkg/meter/ -run TestIntegration -v
package meter

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/3dl-dev/forge/pkg/billingclient"
)

func skipUnlessIntegration(t *testing.T) (baseURL, serviceKey, accountID string) {
	t.Helper()
	baseURL = os.Getenv("FORGE_BASE_URL")
	serviceKey = os.Getenv("FORGE_SERVICE_KEY")
	accountID = os.Getenv("FORGE_ACCOUNT_ID")
	if baseURL == "" || serviceKey == "" || accountID == "" {
		t.Skip("FORGE_BASE_URL, FORGE_SERVICE_KEY, FORGE_ACCOUNT_ID required for integration test")
	}
	return
}

func TestIntegration_IngestAccepted(t *testing.T) {
	baseURL, serviceKey, accountID := skipUnlessIntegration(t)

	client := &billingclient.Client{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
	}
	m := New(client, accountID, nil)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Emit one of each metered operation.
	ops := []Operation{OpMessageSend, OpMessageRead, OpCampfireInit, OpCampfireJoin, OpBeaconRelay}
	for _, op := range ops {
		m.Record(ctx, op, 1.0)
	}

	emitted, failures := m.Stats()
	if failures > 0 {
		t.Errorf("expected 0 failures, got %d (emitted %d)", failures, emitted)
	}
	if emitted != int64(len(ops)) {
		t.Errorf("expected %d emitted, got %d", len(ops), emitted)
	}
}

func TestIntegration_DeduplicationWorks(t *testing.T) {
	baseURL, serviceKey, accountID := skipUnlessIntegration(t)

	client := &billingclient.Client{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Send same idempotency key twice — both should succeed (server deduplicates).
	event := billingclient.UsageEvent{
		AccountID:      accountID,
		ServiceID:      "campfire-hosting",
		UnitType:       "message_send",
		Quantity:       1.0,
		Status:         "ok",
		Timestamp:      time.Now().UTC(),
		IdempotencyKey: "smoke-test-dedup-" + time.Now().Format("20060102-150405"),
	}

	err1 := client.Ingest(ctx, event)
	err2 := client.Ingest(ctx, event)

	if err1 != nil {
		t.Errorf("first ingest failed: %v", err1)
	}
	if err2 != nil {
		t.Errorf("second ingest (dedup) failed: %v", err2)
	}
}
