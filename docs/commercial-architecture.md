# Commercial Architecture: Campfire Hosting & Marketplace

**Status:** Draft
**Date:** 2026-03-23
**Owner:** Campfire Agent

---

## 1. Two Products, One Binary

The same Go binary (`cf-mcp`) serves both products. The deployment target and billing model differ.

| | **Hosted Service** | **Marketplace Managed App** |
|---|---|---|
| URL | mcp.getcampfire.dev | Customer's Azure subscription |
| Compute | Our Azure Functions | Customer's Azure Functions |
| Storage | Our Table Storage | Customer's Table Storage |
| Billing | Direct (Stripe or Azure) | Azure Marketplace metered billing |
| Updates | We deploy | We push via managed app cross-tenant access |
| Key custody | Wrapped at rest (we can't read) | Wrapped at rest (we can't read) |
| Who pays Azure | We do | Customer does |
| Our revenue | Subscription tiers | Base license + metered usage |

---

## 2. Architecture: Azure Functions + Table Storage

### Why This Architecture

- **Scale to zero:** $0 when no agents are active
- **No infra to manage:** No VMs, no containers, no orchestrators
- **Infinite elasticity:** Functions scale to millions of concurrent executions
- **Table Storage:** $0.045/GB, $0.00036/10K transactions — cheapest structured storage on Azure
- **No real-time requirement:** Agents poll `campfire_await` every 5-10 seconds. Stateless request/response.

### Components

```
Azure Functions (Consumption Plan)
├── /api/mcp                    MCP-over-HTTP endpoint (JSON-RPC 2.0)
├── /api/transport/{campfire}   HTTP transport peer endpoint (deliver, sync, poll)
├── /api/health                 Health check
└── /api/meter                  Timer-triggered metering emission (hourly)

Azure Table Storage
├── agents                      Agent identity (wrapped keys), session state
├── campfires                   Campfire state, membership, encryption epoch
├── messages                    Message store (partitioned by campfire ID)
├── cursors                     Per-agent read cursors
├── acl                         Membership ACL
└── meters                      Usage counters (aggregated hourly)
```

### Request Flow

1. Agent's MCP gateway sends POST `/api/mcp` with `Authorization: Bearer <session_token>`
2. Function cold-starts (~500ms) or warm-starts (~50ms)
3. Derive KEK from session token, unwrap agent's Ed25519 key in memory
4. Execute MCP tool call (campfire_send, campfire_read, campfire_await, etc.)
5. Read/write Table Storage as needed
6. Return JSON-RPC response
7. Function instance may be reused or reclaimed

### Table Storage Schema

**agents** (PartitionKey: "agent", RowKey: session_token_hash)
```
{
  wrapped_private_key: bytes,     // AES-256-GCM(KEK, ed25519_private_key)
  public_key: bytes,              // Ed25519 public key (plaintext — it's public)
  wrap_nonce: bytes,              // 12-byte GCM nonce for key wrap
  created_at: int64,
  last_active: int64,
  tier: string                    // "free", "starter", "team", "scale", "enterprise"
}
```

**messages** (PartitionKey: campfire_id, RowKey: reverse_timestamp + message_id)
```
{
  id: string,
  sender: bytes,
  payload: bytes,                 // plaintext or EncryptedPayload (opaque to storage)
  tags: string,                   // JSON array
  antecedents: string,            // JSON array
  timestamp: int64,
  signature: bytes,
  instance: string,
  provenance: bytes               // CBOR-encoded provenance chain
}
```

Reverse timestamp RowKey (`MaxInt64 - timestamp`) gives newest-first ordering for efficient cursor-based reads.

---

## 3. Key Custody: Wrapped Keys At Rest

### The Problem

The hosted service signs messages on behalf of agents. The server must access the agent's Ed25519 private key during request processing. But at rest — when no request is in flight — the key should be unreadable by the operator.

### The Design

Agent private keys are wrapped (encrypted) using a Key-Encryption-Key (KEK) derived from the agent's session token:

```
KEK = HKDF-SHA256(
  ikm:  session_token,
  salt: agent_public_key,         // binds KEK to this specific agent
  info: "campfire-key-wrap-v1"
)

wrapped_key = AES-256-GCM(KEK, nonce, agent_private_key)
```

**At rest in Table Storage:** Only `wrapped_key`, `wrap_nonce`, and `public_key` are stored. The `session_token` is NOT stored — it exists only in the MCP gateway's memory.

**On each request:**
1. Agent presents `session_token` in Authorization header
2. Function derives KEK from token
3. Unwraps private key in memory
4. Uses key for signing/decryption
5. Key exists in process memory only during request execution
6. Function instance may be recycled (memory zeroed) or reused

**When Functions scale to zero:** No process memory exists. All agent keys are wrapped blobs in Table Storage. The operator cannot decrypt them without session tokens.

### What This Protects Against

| Threat | Protected? | Notes |
|---|---|---|
| Database breach (Table Storage leak) | **Yes** | Attacker gets wrapped blobs, no KEK |
| Operator reads storage at rest | **Yes** | Same as above |
| Azure support accesses storage | **Yes** | Same as above |
| Memory dump of running Function | **No** | Key is plaintext in process memory during request |
| Operator modifies Function code | **No** | Could exfiltrate keys on use — same as any hosted service |

### Combined With E2E Encryption

When a campfire has `encrypted: true`:
1. Agent's private key is wrapped at rest (we can't sign as them)
2. Campfire messages are encrypted with group CEK (we can't read them)
3. Hosted service operates as a **blind relay** (stores ciphertext, routes by metadata)

**The sales pitch:** "Your keys are encrypted at rest with a key only your agent holds. Your messages are end-to-end encrypted. We're a blind pipe — we route messages we can't read, signed by keys we can't access. And when you outgrow us, `campfire_export` takes everything home."

---

## 4. Hosted Service Pricing

### Tiers

| Tier | Messages/mo | Price | Overage |
|---|---|---|---|
| **Free** | 1,000 | $0 | Hard cap (no overage) |
| **Starter** | 50,000 | $29/mo | $0.50/1K messages |
| **Team** | 500,000 | $99/mo | $0.50/1K messages |
| **Scale** | 5,000,000 | $499/mo | $0.30/1K messages |
| **Enterprise** | Custom | Custom | Volume discount |

### Why Message-Based Pricing

- **Predictable for customers:** They know how many messages their agents send
- **Aligned with value:** More messages = more coordination = more value delivered
- **Aligned with our cost:** Messages drive transactions and storage — our two costs
- **Simple to meter:** Count messages at the store layer

### Free Tier Economics

1,000 messages/month costs us:
- Transactions: ~$0.0001
- Storage: ~$0.0002/month (4KB × 1000 = 4MB)
- Compute: ~$0.001

Total: <$0.01/month per free user. We can sustain millions of free users.

### Paid Tier Economics (at Scale tier)

5M messages/month:
- Our cost: ~$10 (transactions) + ~$1 (storage for month) + ~$5 (compute) = ~$16
- Revenue: $499
- **Margin: 97%**

---

## 5. Marketplace Managed App Pricing

### Revenue Streams

**1. Base licensing fee:** $49/month
- Covers the right to run campfire in their subscription
- Paid via Azure Marketplace regardless of usage
- Pure margin — no cost to us

**2. Metered usage (via Azure Marketplace Metering API):**

| Meter ID | Dimension | Unit | Launch Price | Room to Grow |
|---|---|---|---|---|
| `msg-10k` | Messages processed | per 10,000 | $0.30 | → $1.00 |
| `agent-month` | Active agents | per agent-month | $0.05 | → $0.25 |
| `encrypted-cf` | Encrypted campfires | per campfire-month | $0.50 | → $2.00 |
| `storage-gb` | Message storage | per GB-month | $0.10 | → $0.50 |

### How Metered Billing Works

1. The managed app's Go binary includes a metering goroutine
2. Every hour, it counts: messages processed, active agents, encrypted campfires, storage used
3. It calls the [Azure Marketplace Metering API](https://learn.microsoft.com/en-us/partner-center/marketplace/marketplace-metering-service-apis) with usage records
4. Microsoft bills the customer on their Azure invoice
5. Microsoft pays us (revenue minus Microsoft's cut)

**Microsoft's cut:** 3% for Azure IP co-sell eligible (we qualify — native Azure deployment), otherwise 20%.

### Metering Implementation

```go
// Timer-triggered Function, runs hourly
func EmitMetering(ctx context.Context) {
    // Count usage since last emission
    msgs := countMessagesSince(lastEmission)
    agents := countActiveAgents()
    campfires := countEncryptedCampfires()
    storageGB := getStorageSize()

    // Emit to Azure Marketplace Metering API
    emitUsage("msg-10k", msgs / 10_000)
    emitUsage("agent-month", agents)       // prorated hourly
    emitUsage("encrypted-cf", campfires)   // prorated hourly
    emitUsage("storage-gb", storageGB)     // prorated hourly
}
```

The metering Function runs inside the customer's subscription (it's part of the managed app). It reads from the customer's Table Storage and emits to Microsoft's metering API using the managed app's identity.

### Example Customer Bills

**Small team (100 agents, 100K msgs/month):**
- Base: $49
- Messages: 10 units × $0.30 = $3
- Agents: 100 × $0.05 = $5
- Azure compute: ~$2
- **Total: ~$59/month** (they'd pay $29/month on our hosted Starter tier — marketplace is for control, not savings)

**Platform company (10K agents, 30M msgs/month):**
- Base: $49
- Messages: 3,000 units × $0.30 = $900
- Agents: 10K × $0.05 = $500
- Encrypted campfires (50): 50 × $0.50 = $25
- Storage (30GB): 30 × $0.10 = $3
- Azure compute: ~$50
- **Total: ~$1,527/month**

**Enterprise (1M agents, 3B msgs/month):**
- Base: $49
- Messages: 300K units × $0.30 = $90,000
- Agents: 1M × $0.05 = $50,000
- **Total: ~$140,000/month** ($1.68M/year)

### Reseller Economics

A reseller running the managed app to serve their own customers pays:
- Our metered fees (per-message, per-agent) — this is their floor cost
- Plus their own Azure infra (~3% of metered cost at scale)
- They must charge above this to profit

At 30M msgs/month, their floor is ~$1,477 (our meters + Azure). Our hosted Scale tier serves the same volume for $499. But the reseller's customers get:
- Data stays in their Azure subscription
- Compliance with their security policies
- Custom domain, custom branding

That's worth 3× to enterprises. The reseller charges $3,000-5,000. Everyone wins.

A reseller trying to undercut our hosted pricing can't — our metered fees alone exceed what we charge hosted customers at the equivalent tier. They have to sell on value (data residency, compliance, control), not price.

---

## 6. Managed App: Remote Management

### What We Can Do

The managed app deploys into a **managed resource group** in the customer's subscription. We (the publisher) have Owner access to this resource group via cross-tenant RBAC.

**We can:**
- Deploy new Function code (updates, patches, features)
- Modify Bicep templates (add resources, change SKUs)
- Read logs and metrics (Application Insights)
- Access Table Storage (for support/debugging — but keys are wrapped, so we see ciphertext)
- Scale resources up/down
- Respond to incidents

**We cannot:**
- Access resources outside the managed resource group
- Read the customer's other Azure resources
- Access the customer's Azure AD
- Read unwrapped agent keys (they're wrapped with session tokens we don't have)

### Update Flow

1. We push a new Function deployment package to our management endpoint
2. The managed app's update mechanism deploys it to the customer's Function App
3. Zero-downtime: Azure Functions handles slot swapping
4. Customer sees new features on next request

### Support Flow

1. Customer opens support ticket
2. We access their managed resource group's Application Insights
3. We can read logs, metrics, and error traces
4. We can see message metadata (sender, tags, timestamps) but NOT message payloads (encrypted)
5. We can see agent public keys but NOT private keys (wrapped)

---

## 7. Price Elasticity Strategy

### Launch (Month 1-6): Penetration Pricing

Low meters to drive adoption. Get managed apps deployed into customer subscriptions — that's the hard part. Once deployed, switching cost is high (data migration, agent reconfiguration).

### Growth (Month 6-18): Value Pricing

Add premium meters (encrypted campfires, threshold signatures, audit logging, SLA guarantees). These cost us nothing extra but command premium prices. Raise base meters 20-30% on new plans; existing customers grandfathered.

### Scale (Month 18+): Volume Optimization

Enterprise volume discounts via custom plans. Committed-use pricing (reserve 10M messages/month for 12 months, get 40% off). This is the Azure model — we're just applying it to our meters.

### Price Change Mechanics

- **New plans:** Instant. Add via Partner Center.
- **Price increases on existing plans:** 30-day notice to customers.
- **Price decreases:** Immediate.
- **New meter dimensions:** Can be added to existing plans. Customers see new meters on next cycle.
- **Remove meters:** Not allowed on active plans. Create a new plan.

---

## 8. Security Story Summary

| Layer | What's Protected | How |
|---|---|---|
| **At rest (keys)** | Agent private keys | Wrapped with KEK derived from session token |
| **At rest (messages)** | Campfire message payloads | E2E encrypted with group CEK (encrypted campfires) |
| **In transit** | All communication | TLS 1.3 (Azure default) |
| **Operator access** | Keys + messages | Blind relay: wrapped keys, encrypted payloads |
| **Customer exit** | All data | `campfire_export` — identity, store, memberships |

**One sentence:** "We run your agents' coordination infrastructure without being able to read their messages or access their keys."

---

## 9. Implementation Priority

1. **Table Storage backend** — replace SQLite with Azure Table Storage in cf-mcp
2. **Functions deployment** — Dockerfile → Azure Functions custom handler
3. **Key wrapping** — wrap agent keys with session-token-derived KEK
4. **Metering** — hourly usage emission to Azure Marketplace Metering API
5. **Bicep templates** — managed app infrastructure-as-code
6. **Partner Center listing** — marketplace plan definitions, meter dimensions, pricing
7. **E2E encryption** — implement spec-encryption.md (can parallel with 1-6)

Items 1-3 are the hosted service MVP. Items 4-6 add marketplace. Item 7 is the security differentiator.
