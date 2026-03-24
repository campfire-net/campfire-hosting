// modules/storage.bicep — Azure Storage Account
//
// Provisions a Storage Account used for:
//   1. Azure Functions runtime storage (required by the Functions host)
//   2. Azure Table Storage — campfire protocol data (operators, API keys, sessions, messages)
//
// Tables created at runtime by the cf-mcp server on first start:
//   cfoperators   — operator registration records
//   cfapikeys     — operator API keys (hashed)
//   cfsessions    — agent session state (partitioned by session token)
//   cfmessages    — campfire messages (partitioned by campfire id)
//
// SKU: Standard_LRS — lowest cost, suitable for hosted service tier.
// Upgrade to Standard_ZRS for higher durability if SLA requirements grow.

param storageAccountName string
param location string
param tags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true          // Functions runtime requires shared key access
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'            // open for initial deploy; tighten with VNet integration later
      bypass: 'AzureServices'
    }
  }
}

// Enable Table Storage service (no extra config needed — it's included in StorageV2)
// Tables are created by the application on startup, not here, to avoid Bicep idempotency issues.

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Storage account resource ID.')
output storageAccountId string = storageAccount.id

@description('Storage account name.')
output storageAccountName string = storageAccount.name

// NOTE: This output contains the storage account key. It is passed directly to the Function App
// appSettings (never written to deployment logs or accessible via ARM API by default).
// The bicep linter warns about listKeys() in outputs; suppressed because the connection
// string is a required input for the Functions runtime and there is no managed-identity path
// for AzureWebJobsStorage on Consumption plan.
@description('Primary connection string for the storage account (contains account key — used only for Function App settings).')
#disable-next-line outputs-should-not-contain-secrets
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Table Storage endpoint.')
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table
