// main.bicepparam — Deployment parameters for campfire-hosting Functions stack
//
// Usage:
//   az deployment group create \
//     --resource-group rg-campfire-hosting \
//     --template-file infra/functions/main.bicep \
//     --parameters infra/functions/main.bicepparam
//
// Alternatively, override individual params on the CLI:
//   az deployment group create ... --parameters keyVaultName=kv-campfire location=eastus2

using './main.bicep'

param location = 'eastus'
param domainName = 'mcp.getcampfire.dev'
param keyVaultName = 'kv-campfire'
param cfDomain = 'mcp.getcampfire.dev'

// Set to false on first deploy until DNS CNAME is live.
// Re-run with true after DNS propagates.
param createCustomDomain = false
