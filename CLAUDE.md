# CLAUDE.md — Campfire Hosting

> OS-level instructions (session protocol, model routing, blog pipeline, rules) are inherited from `~/.claude/CLAUDE.md`. This file contains only project-specific configuration.

## Project

**Campfire Hosting**: Azure-hosted campfire coordination service. Three sovereign regions (East, West, Central). Live at mcp.getcampfire.dev. Metered through Forge's billing pipeline.

## Executive Owner

**CIO** (agent spec: `~/projects/ceo/.claude/agents/cio.md`). The CIO owns platform operations for this repo: deployment health, metering accuracy, forge integration, service key management. Operational work routes to CIO. Implementation work routes to implementer.

## Work Tracking — rd

**This project uses `rd` for all work tracking.**

```bash
rd list                    # All items
rd list --status active    # Active items
rd ready                   # Ready queue
rd show <id>               # Item details
rd create "Title" --type task  # New item
rd update <id> --status active # Change status
rd done <id> --reason "..."    # Close with reason
```

## Agent Roster

| Agent | Spec | Role |
|-------|------|------|
| CIO | `~/projects/ceo/.claude/agents/cio.md` | Platform ops owner — deployment, metering, forge integration |
| implementer | .claude/agents/implementer.md | Build one work unit |
| reviewer | .claude/agents/reviewer.md | Review for correctness + integration |
| designer | .claude/agents/designer.md | Architecture decisions |

**Routing rules:**
- Deployment ops, metering health, forge integration → CIO (sonnet)
- Azure infra (Bicep, ACA, Tables) → implementer (sonnet)
- Auth/metering middleware → implementer (sonnet)
- Store backend (Azure Tables) → implementer (opus)
- CI/CD workflows → implementer (sonnet)
- Architecture decisions → designer (opus)

## Task-Type → Model Mapping

| Task Type | Model | Rationale |
|-----------|-------|-----------|
| Store interface, auth architecture | **Opus** | Novel design, multi-factor trade-offs |
| Bicep templates, middleware, CI/CD | **Sonnet** | Structured implementation |
| Config edits, env var updates | **Haiku** | Mechanical |

## Architecture

```
infra/                    Azure Bicep templates
  aca/                    Container Apps deployment (hosted service)
  shared/                 Shared infra (storage account, app insights)
cmd/
  operator/               Sysop management CLI (sign-up, API keys, metering)
pkg/
  store/azure/            Azure Table Storage backend (implements campfire store interface)
  auth/                   Sysop API key + agent session auth middleware
  meter/                  Per-sysop message metering + Forge billing client integration
  cache/                  In-memory cache + write-through layer
docs/
  runbooks/               Operational runbooks (deployment, metering, incident response)
.github/workflows/        CI/CD: build → GHCR → deploy ACA
```

## Forge Integration

Campfire-hosting emits usage events to Forge via `pkg/billingclient`. Every metered operation (message send/read, campfire_init, join, beacon ops) generates a `UsageEvent` posted to `POST /v1/usage/ingest`.

| Config | Source | Description |
|--------|--------|-------------|
| `FORGE_BASE_URL` | env | Forge API base URL |
| `FORGE_SERVICE_KEY` | env / Key Vault | RoleService key for authentication |

**Fail-open**: Metering failures are logged but do not block campfire operations. A broken forge connection degrades billing accuracy, not service availability.

## Source of Truth

1. Design doc: campfire repo `docs/design-hosted-deployment.md`
2. Bicep templates: `infra/`
3. Implementation: `cmd/`, `pkg/`
4. Operational runbooks: `docs/runbooks/`

## Conventions

- Go standard style: `gofmt`, `go vet`
- Azure Bicep for all infra (no Terraform, no ARM JSON)
- One change per commit, descriptive message
- All Azure resources tagged with `project: campfire-hosting`

## Don't

- Don't put protocol-level changes here — those go in the campfire repo
- Don't hardcode Azure credentials — use managed identity everywhere
- Don't weaken tests to make them pass
- Don't block campfire operations on forge unavailability (fail-open metering)
