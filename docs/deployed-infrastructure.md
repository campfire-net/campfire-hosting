# Deployed Infrastructure — Hosted Campfire Service

**Status:** Live (2026-03-24)
**Environment:** Production
**Region:** East US 2

---

## Resource Group

| Property | Value |
|----------|-------|
| Name | `rg-campfire-hosting` |
| Subscription | `169efd95-5e00-42f9-8e65-a1892791ed9a` (Azure subscription 1) |
| Location | East US 2 |

## Resources

| Resource | Name | Type | Notes |
|----------|------|------|-------|
| Function App | `func-campfire-bpjpsl` | Microsoft.Web/sites (Consumption Y1, Windows) | Custom handler runtime |
| Storage Account | `stcampfirebpjpsl` | Standard_LRS | Table Storage (campfire data) + Functions runtime |
| Key Vault | `kv-cf-host-prod` | RBAC-enabled | Holds `cf-session-token` secret |
| App Insights | `appi-campfire-bpjpsl` | Workspace-based | Connected to Log Analytics |
| Log Analytics | `log-campfire-bpjpsl` | Per-GB pricing | Monitoring backend |

## Endpoints

| Endpoint | URL |
|----------|-----|
| Custom domain | `https://mcp.getcampfire.dev` |
| Default hostname | `https://func-campfire-bpjpsl.azurewebsites.net` |
| Health check | `GET /api/health` |
| MCP endpoint | `POST /api/mcp` |
| Payment | `POST /api/payment` |
| SSE | `GET /api/sse` |

## DNS

Zone `getcampfire.dev` is hosted in Azure DNS within `rg-campfire-hosting`.

| Record | Type | Value |
|--------|------|-------|
| `@` | A | 185.199.108.153, 109, 110, 111 (GitHub Pages — public site) |
| `mcp` | CNAME | `func-campfire-bpjpsl.azurewebsites.net` |

## TLS

Managed certificate issued by GeoTrust TLS RSA CA G1. Auto-renews.
Thumbprint: `9948F84AA166850D4EA260AE169C2B439B63A704`
Expires: 2026-09-24

## Service Principal

Deleted after initial setup — was `sp-campfire-hosting` (`5e396633-ffb1-4f6c-8c41-1100665581c8`). Bicep deployment used CLI auth directly.

## Function App Configuration

| Setting | Value |
|---------|-------|
| `FUNCTIONS_WORKER_RUNTIME` | `custom` |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` |
| `CF_DOMAIN` | `mcp.getcampfire.dev` |
| `CF_SESSION_TOKEN` | Key Vault ref: `@Microsoft.KeyVault(VaultName=kv-cf-host-prod;SecretName=CF_SESSION_TOKEN)` |
| `CF_MCP_BIN` | `C:\home\site\wwwroot\cf-mcp.exe` |
| `AZURE_STORAGE_CONNECTION_STRING` | (auto from Bicep — points to `stcampfirebpjpsl`) |

## RBAC Grants

| Principal | Role | Scope |
|-----------|------|-------|
| Function App managed identity (`05b0064d-f10d-4e82-8c0d-603b25767bbd`) | Key Vault Secrets User | `kv-cf-host-prod` |

## Deployment

Code is deployed via zip push:
```bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o cf-functions.exe ./cmd/cf-functions/
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o cf-mcp.exe ./cmd/cf-mcp/
# Package with host.json + api/function.json → zip → az functionapp deployment source config-zip
```

CI/CD workflow at `.github/workflows/deploy-functions.yml` in the campfire repo triggers on push to main. Requires `AZURE_FUNCTIONAPP_PUBLISH_PROFILE` secret in GitHub repo settings.

## Known Issues

1. **Windows Consumption plan** — the Bicep deploys Windows (not Linux). Binary must be `.exe`, paths use `C:\`. Would prefer Linux Consumption but the subscription had no Dynamic VM quota when we deployed.
2. **CF_MCP_BIN hardcoded** — the binary lookup in cf-functions doesn't append `.exe` on Windows. We set `CF_MCP_BIN` as an app setting as a workaround.
3. **Azurite CI** — Table Storage integration tests are gated behind `//go:build azurite`. Need Azurite in CI (tracked: `campfire-agent-k66`).
