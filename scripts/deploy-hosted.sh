#!/usr/bin/env bash
# deploy-hosted.sh — Deploy campfire-hosting to mcp.getcampfire.dev
#
# Prerequisites (human gates — must be done before running this script):
#   1. Azure CLI authenticated: az login
#   2. Subscription selected: az account set --subscription <sub-id>
#   3. Key Vault exists with CF_SESSION_TOKEN secret:
#        az keyvault create --name kv-campfire --resource-group rg-campfire-hosting --location eastus
#        az keyvault secret set --vault-name kv-campfire --name CF_SESSION_TOKEN --value "<token>"
#   4. DNS CNAME configured: mcp.getcampfire.dev → <functionApp>.azurewebsites.net
#      (Set SKIP_CUSTOM_DOMAIN=true on first deploy, add CNAME after, re-run with false.)
#   5. AZURE_FUNCTIONAPP_PUBLISH_PROFILE secret set in GitHub repo settings
#      (Get from: az functionapp deployment list-publishing-profiles --name <app> --resource-group rg-campfire-hosting)
#
# Usage:
#   SKIP_CUSTOM_DOMAIN=true ./scripts/deploy-hosted.sh          # First deploy (no DNS yet)
#   SKIP_CUSTOM_DOMAIN=false ./scripts/deploy-hosted.sh         # Re-deploy after DNS is live
#
# Environment variables:
#   RESOURCE_GROUP      — Azure resource group (default: rg-campfire-hosting)
#   LOCATION            — Azure region (default: eastus)
#   KEY_VAULT_NAME      — Key Vault name (default: kv-campfire)
#   SKIP_CUSTOM_DOMAIN  — Skip custom domain binding (default: false)
#   DRY_RUN             — Print commands without running (default: false)

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-campfire-hosting}"
LOCATION="${LOCATION:-eastus}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-campfire}"
SKIP_CUSTOM_DOMAIN="${SKIP_CUSTOM_DOMAIN:-false}"
DRY_RUN="${DRY_RUN:-false}"
DOMAIN="${DOMAIN:-mcp.getcampfire.dev}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { echo "[deploy-hosted] $*"; }
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  DRY RUN: $*"
  else
    "$@"
  fi
}

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
log "Checking Azure CLI authentication..."
if ! az account show &>/dev/null; then
  echo "ERROR: Not authenticated. Run: az login" >&2
  exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
log "Using subscription: ${SUBSCRIPTION_ID}"

# ── Step 2: Create resource group ─────────────────────────────────────────────
log "Creating resource group ${RESOURCE_GROUP} in ${LOCATION}..."
run az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

# ── Step 3: Deploy Bicep infrastructure ───────────────────────────────────────
CREATE_DOMAIN="true"
if [[ "${SKIP_CUSTOM_DOMAIN}" == "true" ]]; then
  CREATE_DOMAIN="false"
  log "Skipping custom domain binding (SKIP_CUSTOM_DOMAIN=true)."
fi

log "Deploying Bicep infrastructure..."
DEPLOY_OUTPUT=$(run az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${REPO_ROOT}/infra/functions/main.bicep" \
  --parameters "${REPO_ROOT}/infra/functions/main.bicepparam" \
  --parameters createCustomDomain="${CREATE_DOMAIN}" \
  --parameters domainName="${DOMAIN}" \
  --parameters cfDomain="${DOMAIN}" \
  --parameters keyVaultName="${KEY_VAULT_NAME}" \
  --parameters location="${LOCATION}" \
  --output json 2>&1)

if [[ "${DRY_RUN}" != "true" ]]; then
  FUNCTION_APP_NAME=$(echo "${DEPLOY_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['functionAppName']['value'])")
  PRINCIPAL_ID=$(echo "${DEPLOY_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['functionAppPrincipalId']['value'])")
  FUNCTION_APP_URL=$(echo "${DEPLOY_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['functionAppUrl']['value'])")
  STORAGE_ACCOUNT=$(echo "${DEPLOY_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['properties']['outputs']['storageAccountName']['value'])")

  log "Function App: ${FUNCTION_APP_NAME}"
  log "Default URL:  ${FUNCTION_APP_URL}"
  log "Storage:      ${STORAGE_ACCOUNT}"
  log "Principal ID: ${PRINCIPAL_ID}"
fi

# ── Step 4: Grant Key Vault access to Function App managed identity ────────────
log "Granting Key Vault Secrets User role to Function App managed identity..."
if [[ "${DRY_RUN}" != "true" ]]; then
  KV_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
  run az role assignment create \
    --assignee "${PRINCIPAL_ID}" \
    --role "Key Vault Secrets User" \
    --scope "${KV_SCOPE}" \
    --output none || log "WARNING: Role assignment may already exist. Continuing."
fi

# ── Step 5: Configure GitHub variable AZURE_FUNCTIONAPP_NAME ──────────────────
if [[ "${DRY_RUN}" != "true" ]] && command -v gh &>/dev/null; then
  log "Setting AZURE_FUNCTIONAPP_NAME GitHub variable..."
  run gh variable set AZURE_FUNCTIONAPP_NAME --body "${FUNCTION_APP_NAME}" || \
    log "WARNING: Could not set GitHub variable. Set manually: AZURE_FUNCTIONAPP_NAME=${FUNCTION_APP_NAME}"
fi

# ── Step 6: DNS instructions ──────────────────────────────────────────────────
if [[ "${DRY_RUN}" != "true" ]] && [[ "${SKIP_CUSTOM_DOMAIN}" == "true" ]]; then
  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "  HUMAN ACTION REQUIRED: Configure DNS"
  echo "══════════════════════════════════════════════════════════"
  echo "  Add a CNAME record:"
  echo "    ${DOMAIN} → ${FUNCTION_APP_NAME}.azurewebsites.net"
  echo ""
  echo "  After DNS propagates (~5-15 min), re-run with:"
  echo "    DOMAIN=${DOMAIN} SKIP_CUSTOM_DOMAIN=false ./scripts/deploy-hosted.sh"
  echo "══════════════════════════════════════════════════════════"
fi

# ── Step 7: GitHub Actions first deployment ───────────────────────────────────
echo ""
log "Infrastructure deployed. CI/CD is configured via GitHub Actions."
echo ""
echo "  NEXT STEPS:"
echo "    1. Ensure AZURE_FUNCTIONAPP_PUBLISH_PROFILE is set in GitHub repo secrets."
echo "       Get publish profile: az functionapp deployment list-publishing-profiles \\"
echo "         --name ${FUNCTION_APP_NAME:-<function-app-name>} \\"
echo "         --resource-group ${RESOURCE_GROUP} --xml"
echo ""
echo "    2. Push to main or trigger the workflow manually:"
echo "       gh workflow run deploy-functions.yml"
echo ""
echo "    3. After deployment, run smoke tests:"
echo "       ./scripts/smoke-test.sh"
echo ""
log "Done."
