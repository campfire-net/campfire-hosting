# Deployed Infrastructure — Hosted Campfire Service

**Status:** Live (2026-03-27)
**Architecture:** 3 sovereign peers, content replication in-band via campfire protocol
**Subscription:** `169efd95-5e00-42f9-8e65-a1892791ed9a` (Azure subscription 1)

---

## Instance 1 — East US 2 (canary)

| Property | Value |
|----------|-------|
| Resource Group | `rg-campfire-hosting` |
| Location | East US 2 |
| Function App | `func-campfire-bpjpsl` (Consumption Y1) |
| Storage Account | `stcampfirebpjpsl` (Standard_LRS, Table Storage) |
| Key Vault | `kv-cf-host-prod` (RBAC-enabled) |
| App Insights | `appi-campfire-bpjpsl` |
| Log Analytics | `log-campfire-bpjpsl` |
| Managed Identity | `05b0064d-f10d-4e82-8c0d-603b25767bbd` |
| Ed25519 Public Key | `HiJMFLx5Wb9r7H1OVjOJtsPT6SVa0gbfG6YM3FIZf/0=` |

## Instance 2 — West US 2

| Property | Value |
|----------|-------|
| Resource Group | `rg-campfire-hosting-west2` |
| Location | West US 2 |
| Function App | `func-campfire-nkjj23` (Consumption Y1) |
| Storage Account | `stcampfirenkjj23` (Standard_LRS, Table Storage) |
| Key Vault | `kv-cf-host-west2` (RBAC-enabled) |
| App Insights | `appi-campfire-nkjj23` |
| Log Analytics | `log-campfire-nkjj23` |
| Managed Identity | `49bd9bd9-6926-45d0-be28-2022056f0f81` |
| Ed25519 Public Key | `kZ+ihl5CGH0oMZnfDAv6yZBkksqAwxxYFI4tq+gp9fs=` |

## Instance 3 — Central US

| Property | Value |
|----------|-------|
| Resource Group | `rg-campfire-hosting-central` |
| Location | Central US |
| Function App | `func-campfire-43tqv4` (Consumption Y1) |
| Storage Account | `stcampfire43tqv4` (Standard_LRS, Table Storage) |
| Key Vault | `kv-cf-host-central` (RBAC-enabled) |
| App Insights | `appi-campfire-43tqv4` |
| Log Analytics | `log-campfire-43tqv4` |
| Managed Identity | `0966ffc8-7d4b-4fc4-ba96-5e3529fb1554` |
| Ed25519 Public Key | `6Zvp9pf+GzUGbysyK/DShjuzYuw0F0N1nLbIZUBSBGQ=` |

---

## Endpoints

| Instance | Custom Domain | Default Hostname |
|----------|---------------|------------------|
| East US 2 | `https://mcp.east.getcampfire.dev` | `https://func-campfire-bpjpsl.azurewebsites.net` |
| West US 2 | `https://mcp.west.getcampfire.dev` | `https://func-campfire-nkjj23.azurewebsites.net` |
| Central US | `https://mcp.central.getcampfire.dev` | `https://func-campfire-43tqv4.azurewebsites.net` |

All instances expose: `POST /api/mcp`, `GET /api/sse`, `POST /api/payment`, `GET /api/health`

## DNS

Zone `getcampfire.dev` is hosted in Azure DNS within `rg-campfire-hosting`.

| Record | Type | Value |
|--------|------|-------|
| `@` | A | 185.199.108.153, 109, 110, 111 (GitHub Pages — public site) |
| `mcp` | CNAME | `mcp.east.getcampfire.dev` (alias for East US) |
| `mcp.east` | CNAME | `func-campfire-bpjpsl.azurewebsites.net` |
| `mcp.west` | CNAME | `func-campfire-nkjj23.azurewebsites.net` |
| `mcp.central` | CNAME | `func-campfire-43tqv4.azurewebsites.net` |
| `asuid.mcp.east` | TXT | `82FB076892DF52BE6673A24AA83812423901F0801C49F8B982EB40A9E3D3348C` |
| `asuid.mcp.west` | TXT | `82FB076892DF52BE6673A24AA83812423901F0801C49F8B982EB40A9E3D3348C` |
| `asuid.mcp.central` | TXT | `82FB076892DF52BE6673A24AA83812423901F0801C49F8B982EB40A9E3D3348C` |

## TLS

| Instance | Thumbprint | Issuer | Expires |
|----------|-----------|--------|---------|
| East US 2 | `9948F84AA166850D4EA260AE169C2B439B63A704` | GeoTrust TLS RSA CA G1 | 2026-09-24 |
| East US 2 (mcp.east) | `309C5FE93F13BDDD71CCFAD4738654A9954AB2FB` | GeoTrust TLS RSA CA G1 | 2026-09-27 |
| West US 2 | `A07CC245C59A326EBE6C4A77FA60F78E3AC86C19` | GeoTrust TLS RSA CA G1 | 2026-09-27 |
| Central US | `14F66BAE93182CDFE7CB32D57E05B117BCDA1963` | GeoTrust TLS RSA CA G1 | 2026-09-27 |

All certificates are Azure App Service Managed Certificates (free, auto-renew).

## RBAC Grants

| Instance | Principal | Role | Scope |
|----------|-----------|------|-------|
| East US 2 | `05b0064d-f10d-4e82-8c0d-603b25767bbd` | Key Vault Secrets User | `kv-cf-host-prod` |
| West US 2 | `49bd9bd9-6926-45d0-be28-2022056f0f81` | Key Vault Secrets User | `kv-cf-host-west2` |
| Central US | `0966ffc8-7d4b-4fc4-ba96-5e3529fb1554` | Key Vault Secrets User | `kv-cf-host-central` |

## Function App Configuration

All instances share the same configuration pattern:

| Setting | Value |
|---------|-------|
| `FUNCTIONS_WORKER_RUNTIME` | `custom` |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` |
| `CF_DOMAIN` | `mcp.<region>.getcampfire.dev` |
| `CF_SESSION_TOKEN` | Key Vault ref: `@Microsoft.KeyVault(VaultName=<kv>;SecretName=CF_SESSION_TOKEN)` |
| `AZURE_STORAGE_CONNECTION_STRING` | (auto from Bicep — points to instance storage) |
| `FORGE_BASE_URL` | `https://forge.3dl.dev` |
| `FORGE_SERVICE_KEY` | Key Vault ref: `@Microsoft.KeyVault(VaultName=<kv>;SecretName=FORGE_SERVICE_KEY)` |
| `FORGE_ACCOUNT_ID` | (set per deployment — forge account for metering) |

## Deployment

Staged rollout via GitHub Actions (`.github/workflows/deploy-functions.yml` in campfire-agent repo):

1. Build `cf-functions` + `cf-mcp` from public `campfire-net/campfire` repo
2. Deploy to East US 2 (canary) → health check
3. If healthy, deploy to West US 2 + Central US in parallel → health checks

GitHub secrets/variables per instance:
- `AZURE_FUNCTIONAPP_NAME_EAST` / `AZURE_FUNCTIONAPP_PUBLISH_PROFILE_EAST`
- `AZURE_FUNCTIONAPP_NAME_WEST` / `AZURE_FUNCTIONAPP_PUBLISH_PROFILE_WEST`
- `AZURE_FUNCTIONAPP_NAME_CENTRAL` / `AZURE_FUNCTIONAPP_PUBLISH_PROFILE_CENTRAL`

## Known Issues

1. **Windows Consumption plan** — all instances use Windows (not Linux). Binary must be `.exe`, paths use `C:\`. Would prefer Linux Consumption but the subscription had no Dynamic VM quota in some regions.
2. **West US unavailable** — West US had no Dynamic VM quota; used West US 2 instead. Domain remains `mcp.west.getcampfire.dev`.
3. **No code on new instances** — West US 2 and Central US function apps are deployed but have no code yet. First push to main via the staged workflow will deploy code to all 3.
4. **Azurite CI** — Table Storage integration tests are gated behind `//go:build azurite`. Need Azurite in CI (tracked: `campfire-agent-k66`).
