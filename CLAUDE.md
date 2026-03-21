# CLAUDE.md — Campfire Hosting

> OS-level instructions (session protocol, model routing, blog pipeline, rules) are inherited from `~/.claude/CLAUDE.md`. This file contains only project-specific configuration.

## Project

**Campfire Hosting**: Azure-native hosting infrastructure for the campfire coordination protocol. Runs the hosted cf-mcp service at mcp.getcampfire.dev (Azure Container Apps) and provides operator identity, metering, and CI/CD.

## Work Tracking — rd (not bd)

**This project uses `rd` for all work tracking.** The `bd` CLI is NOT used in this project.

```bash
rd list                    # All items
rd list --status active    # Active items
rd ready                   # Ready queue
rd show <id>               # Item details
rd create "Title" --type task  # New item
rd update <id> --status active # Change status
rd close <id> --reason "..."   # Close with reason
```

## Agent Roster

| Agent | Spec | Role |
|-------|------|------|
| PM | CLAUDE.md | Prioritize, track, route work |
| implementer | .claude/agents/implementer.md | Build one work unit |
| reviewer | .claude/agents/reviewer.md | Review for correctness + integration |
| designer | .claude/agents/designer.md | Architecture decisions |

**Routing rules:**
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
  operator/               Operator management CLI (sign-up, API keys, metering)
pkg/
  store/azure/            Azure Table Storage backend (implements campfire store interface)
  auth/                   Operator API key + agent session auth middleware
  meter/                  Per-operator message metering
  cache/                  In-memory cache + write-through layer
.github/workflows/        CI/CD: build → GHCR → deploy ACA
```

## Source of Truth

1. Design doc: campfire repo `docs/design-hosted-deployment.md`
2. Bicep templates: `infra/`
3. Implementation: `cmd/`, `pkg/`

## Conventions

- Go standard style: `gofmt`, `go vet`
- Azure Bicep for all infra (no Terraform, no ARM JSON)
- One change per commit, descriptive message
- All Azure resources tagged with `project: campfire-hosting`

## Don't

- Don't put protocol-level changes here — those go in the campfire repo
- Don't hardcode Azure credentials — use managed identity everywhere
- Don't weaken tests to make them pass
