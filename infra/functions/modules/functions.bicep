// modules/functions.bicep — Azure Functions App (Consumption plan, custom handler)
//
// cf-mcp runs as an Azure Functions custom handler: a Go binary that listens on a local
// HTTP port. The Functions host proxies HTTP trigger invocations to the Go process.
//
// Runtime: custom (FUNCTIONS_WORKER_RUNTIME=custom)
// Plan: Consumption (Y1) — scale-to-zero, pay-per-invocation. No baseline cost.
//
// Key Vault integration:
//   CF_SESSION_TOKEN is read from Key Vault via a Key Vault reference:
//     @Microsoft.KeyVault(VaultName=<kv>;SecretName=CF_SESSION_TOKEN)
//   The Function App's system-assigned managed identity must have
//   "Key Vault Secrets User" role on the Key Vault.
//   Grant after deploy:
//     az role assignment create \
//       --assignee <functionAppPrincipalId (from output)> \
//       --role "Key Vault Secrets User" \
//       --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv>
//
// Custom handler configuration:
//   The Go binary is deployed as a zip package. The Functions host sets
//   FUNCTIONS_CUSTOMHANDLER_PORT and the binary must listen on that port.
//   Set enableForwardingHttpRequest=true so HTTP triggers pass raw requests through.

param appName string
param hostingPlanName string
param location string
param tags object
param storageConnectionString string
param appInsightsConnectionString string
param appInsightsInstrumentationKey string
param keyVaultName string
param cfDomain string
param forgeBaseUrl string = 'https://forge.3dl.dev'
param forgeAccountId string = ''

// Consumption plan (Y1) — serverless, scale-to-zero
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true    // true = Linux Consumption
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'    // enables Key Vault reference resolution
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      // Custom handler: Go binary listens on FUNCTIONS_CUSTOMHANDLER_PORT
      // The handler must be a native binary in the Functions deployment package.
      // Example host.json:
      //   { "customHandler": { "description": { "defaultExecutablePath": "cf-mcp",
      //       "workingDirectory": "", "arguments": [] },
      //       "enableForwardingHttpRequest": true } }
      appSettings: [
        // ── Functions runtime ──────────────────────────────────────────────
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(appName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'custom'
        }
        {
          // Run from package preserves execute permissions on Linux Consumption.
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }

        // ── Application Insights ───────────────────────────────────────────
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }

        // ── cf-mcp configuration ───────────────────────────────────────────
        {
          name: 'AZURE_STORAGE_CONNECTION_STRING'
          value: storageConnectionString
        }
        {
          // CF_SESSION_TOKEN read from Key Vault via managed identity reference.
          // Format: @Microsoft.KeyVault(VaultName=<name>;SecretName=CF_SESSION_TOKEN)
          // The Function App principal ID (see output) must have Key Vault Secrets User role.
          name: 'CF_SESSION_TOKEN'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=CF_SESSION_TOKEN)'
        }
        {
          // CF_DOMAIN must include the /api path prefix because Azure Functions
          // mounts HTTP triggers under /api/*. Peer-to-peer message delivery
          // uses this URL to reach other instances.
          name: 'CF_DOMAIN'
          value: '${cfDomain}/api'
        }

        // ── Forge metering ─────────────────────────────────────────────────
        {
          name: 'FORGE_BASE_URL'
          value: forgeBaseUrl
        }
        {
          // FORGE_SERVICE_KEY read from Key Vault via managed identity reference.
          name: 'FORGE_SERVICE_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=FORGE_SERVICE_KEY)'
        }
        {
          name: 'FORGE_ACCOUNT_ID'
          value: forgeAccountId
        }

        // ── Custom handler forwarding ──────────────────────────────────────
        // The Go binary reads this port from the env and starts its HTTP listener there.
        // Functions host sets FUNCTIONS_CUSTOMHANDLER_PORT automatically at runtime.
        // No explicit setting needed here — the runtime injects it.
      ]

      // Minimum TLS 1.2
      minTlsVersion: '1.2'

      // HTTP/2 enabled for SSE efficiency
      http20Enabled: true

      // 64-bit worker process
      use32BitWorkerProcess: false

      // Always on: NOT available on Consumption plan — scale-to-zero is the default.
      // For warm-start guarantees, upgrade to Premium EP1 plan.
    }
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Function App default hostname.')
output defaultHostname string = functionApp.properties.defaultHostName

@description('Function App resource ID.')
output functionAppId string = functionApp.id

@description('System-assigned managed identity principal ID — grant Key Vault Secrets User on the Key Vault.')
output principalId string = functionApp.identity.principalId
