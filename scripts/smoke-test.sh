#!/usr/bin/env bash
# smoke-test.sh — Smoke tests for mcp.getcampfire.dev hosted service
#
# Tests:
#   1. Health check  — GET /api/health → 200 OK with {"status":"ok"}
#   2. MCP init      — POST /mcp with campfire_init → valid session token + Ed25519 pubkey
#   3. Message round-trip — create campfire, send message, read it back
#   4. Rate limit    — send messages until cap, verify 429 response
#
# Usage:
#   ./scripts/smoke-test.sh                          # Test https://mcp.getcampfire.dev
#   BASE_URL=http://localhost:8080 ./scripts/smoke-test.sh  # Test local instance
#   API_KEY=<your-key> ./scripts/smoke-test.sh       # Use your operator API key
#   SKIP_RATE_LIMIT=true ./scripts/smoke-test.sh     # Skip rate limit test (slow)
#
# Requirements:
#   - curl, jq
#   - Service must be deployed and responding

set -euo pipefail

BASE_URL="${BASE_URL:-https://mcp.getcampfire.dev}"
API_KEY="${API_KEY:-test-smoke-key}"
SKIP_RATE_LIMIT="${SKIP_RATE_LIMIT:-false}"

PASS=0
FAIL=0
SKIP=0

log()  { echo "[smoke-test] $*"; }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }

require() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: $1 is required but not installed." >&2
    exit 1
  fi
}

require curl
require jq

echo ""
echo "Campfire Hosted Service Smoke Tests"
echo "Target: ${BASE_URL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Test 1: Health check ──────────────────────────────────────────────────────
echo ""
echo "Test 1: Health check"
HEALTH_RESP=$(curl -sf -w "\n%{http_code}" "${BASE_URL}/api/health" 2>/dev/null || echo -e "\n000")
HEALTH_STATUS=$(echo "${HEALTH_RESP}" | tail -1)
HEALTH_BODY=$(echo "${HEALTH_RESP}" | head -1)

if [[ "${HEALTH_STATUS}" == "200" ]]; then
  STATUS_VAL=$(echo "${HEALTH_BODY}" | jq -r '.status // empty' 2>/dev/null || echo "")
  if [[ "${STATUS_VAL}" == "ok" ]]; then
    pass "GET /api/health → 200 {status: ok}"
  else
    fail "GET /api/health → 200 but body missing {status: ok}: ${HEALTH_BODY}"
  fi
else
  fail "GET /api/health → ${HEALTH_STATUS} (expected 200)"
fi

# ── Test 2: MCP campfire_init ─────────────────────────────────────────────────
echo ""
echo "Test 2: MCP campfire_init"
INIT_PAYLOAD=$(cat <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "campfire_init",
    "arguments": {}
  }
}
EOF
)

INIT_RESP=$(curl -sf -w "\n%{http_code}" \
  -X POST "${BASE_URL}/mcp" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "${INIT_PAYLOAD}" 2>/dev/null || echo -e "\n000")

INIT_STATUS=$(echo "${INIT_RESP}" | tail -1)
INIT_BODY=$(echo "${INIT_RESP}" | head -1)

if [[ "${INIT_STATUS}" == "200" ]]; then
  SESSION_TOKEN=$(echo "${INIT_BODY}" | jq -r '.result.content[0].text // empty' 2>/dev/null | jq -r '.session_token // empty' 2>/dev/null || echo "")
  PUBKEY=$(echo "${INIT_BODY}" | jq -r '.result.content[0].text // empty' 2>/dev/null | jq -r '.public_key // empty' 2>/dev/null || echo "")

  if [[ -n "${SESSION_TOKEN}" ]] && [[ -n "${PUBKEY}" ]]; then
    pass "campfire_init → 200, session_token and public_key present"
  else
    # Try alternate response shape
    SESSION_TOKEN=$(echo "${INIT_BODY}" | jq -r '.. | .session_token? // empty' 2>/dev/null | head -1 || echo "")
    if [[ -n "${SESSION_TOKEN}" ]]; then
      pass "campfire_init → 200, session_token present"
    else
      fail "campfire_init → 200 but no session_token in response: ${INIT_BODY}"
    fi
  fi
else
  fail "campfire_init → ${INIT_STATUS} (expected 200): ${INIT_BODY}"
  SESSION_TOKEN=""
fi

# ── Test 3: Message round-trip ────────────────────────────────────────────────
echo ""
echo "Test 3: Message round-trip (create campfire, send, receive)"

if [[ -z "${SESSION_TOKEN:-}" ]]; then
  skip "Message round-trip (no session token from campfire_init)"
else
  # Create a campfire
  CREATE_PAYLOAD=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "campfire_create",
    "arguments": {}
  }
}
EOF
)
  CREATE_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "${BASE_URL}/mcp" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SESSION_TOKEN}" \
    -d "${CREATE_PAYLOAD}" 2>/dev/null || echo -e "\n000")

  CREATE_STATUS=$(echo "${CREATE_RESP}" | tail -1)
  CREATE_BODY=$(echo "${CREATE_RESP}" | head -1)

  CAMPFIRE_ID=$(echo "${CREATE_BODY}" | jq -r '.. | .campfire_id? // empty' 2>/dev/null | head -1 || echo "")

  if [[ "${CREATE_STATUS}" == "200" ]] && [[ -n "${CAMPFIRE_ID}" ]]; then
    pass "campfire_create → 200, campfire_id=${CAMPFIRE_ID}"

    # Send a message
    TEST_MSG="smoke-test-$(date +%s)"
    SEND_PAYLOAD=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "campfire_send",
    "arguments": {
      "campfire_id": "${CAMPFIRE_ID}",
      "message": "${TEST_MSG}"
    }
  }
}
EOF
)
    SEND_RESP=$(curl -sf -w "\n%{http_code}" \
      -X POST "${BASE_URL}/mcp" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SESSION_TOKEN}" \
      -d "${SEND_PAYLOAD}" 2>/dev/null || echo -e "\n000")
    SEND_STATUS=$(echo "${SEND_RESP}" | tail -1)

    if [[ "${SEND_STATUS}" == "200" ]]; then
      pass "campfire_send → 200"

      # Read messages back
      READ_PAYLOAD=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "campfire_read",
    "arguments": {
      "campfire_id": "${CAMPFIRE_ID}"
    }
  }
}
EOF
)
      READ_RESP=$(curl -sf -w "\n%{http_code}" \
        -X POST "${BASE_URL}/mcp" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${SESSION_TOKEN}" \
        -d "${READ_PAYLOAD}" 2>/dev/null || echo -e "\n000")
      READ_STATUS=$(echo "${READ_RESP}" | tail -1)
      READ_BODY=$(echo "${READ_RESP}" | head -1)

      if [[ "${READ_STATUS}" == "200" ]]; then
        if echo "${READ_BODY}" | grep -q "${TEST_MSG}"; then
          pass "campfire_read → 200, sent message present in response"
        else
          fail "campfire_read → 200 but sent message not found in response: ${READ_BODY}"
        fi
      else
        fail "campfire_read → ${READ_STATUS} (expected 200)"
      fi
    else
      fail "campfire_send → ${SEND_STATUS} (expected 200)"
    fi
  else
    fail "campfire_create → ${CREATE_STATUS} (campfire_id not found): ${CREATE_BODY}"
    CAMPFIRE_ID=""
  fi
fi

# ── Test 4: Rate limit enforcement ───────────────────────────────────────────
echo ""
echo "Test 4: Rate limit enforcement"

if [[ "${SKIP_RATE_LIMIT}" == "true" ]]; then
  skip "Rate limit test (SKIP_RATE_LIMIT=true)"
elif [[ -z "${SESSION_TOKEN:-}" ]] || [[ -z "${CAMPFIRE_ID:-}" ]]; then
  skip "Rate limit test (no session or campfire from previous tests)"
else
  log "Sending messages until rate limit hit (or 200 attempts)..."
  GOT_429=false
  for i in $(seq 1 200); do
    RL_PAYLOAD=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": $((100 + i)),
  "method": "tools/call",
  "params": {
    "name": "campfire_send",
    "arguments": {
      "campfire_id": "${CAMPFIRE_ID}",
      "message": "rate-limit-probe-${i}"
    }
  }
}
EOF
)
    RL_STATUS=$(curl -so /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/mcp" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SESSION_TOKEN}" \
      -d "${RL_PAYLOAD}" 2>/dev/null || echo "000")

    if [[ "${RL_STATUS}" == "429" ]]; then
      GOT_429=true
      pass "Rate limit enforced after ${i} messages (HTTP 429)"
      break
    elif [[ "${RL_STATUS}" != "200" ]]; then
      fail "Unexpected status ${RL_STATUS} at message ${i}"
      break
    fi
  done

  if [[ "${GOT_429}" == "false" ]]; then
    fail "Rate limit not triggered after 200 messages (expected HTTP 429)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "SMOKE TEST FAILED"
  exit 1
else
  echo "SMOKE TEST PASSED"
  exit 0
fi
