// main.bicep — Entry point for campfire-hosting Azure Functions stack
//
// Deploys the complete hosting infrastructure for cf-mcp at mcp.getcampfire.dev:
//   - Azure Storage Account (Table Storage for campfire data + Functions runtime)
//   - Log Analytics workspace + Application Insights
//   - Azure Functions App (Consumption plan, custom handler runtime)
//   - Custom domain binding with managed TLS certificate
//
// Deployment:
//   az group create --name rg-campfire-hosting --location eastus
//   az deployment group create \
//     --resource-group rg-campfire-hosting \
//     --template-file infra/functions/main.bicep \
//     --parameters location=eastus domainName=mcp.getcampfire.dev keyVaultName=kv-campfire
//
// Prerequisites:
//   1. Key Vault must exist with CF_SESSION_TOKEN secret
//   2. DNS CNAME mcp.getcampfire.dev → <functionAppName>.azurewebsites.net must be created before
//      running the dns module (or set createCustomDomain=false for initial deploy)
//   3. Function App managed identity must have get/list on Key Vault secrets (see outputs)

targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Custom domain to bind to the Function App (e.g. mcp.getcampfire.dev).')
param domainName string = 'mcp.getcampfire.dev'

@description('Name of the Key Vault holding CF_SESSION_TOKEN secret.')
param keyVaultName string

@description('CF_DOMAIN env var value passed to the Function App.')
param cfDomain string = 'mcp.getcampfire.dev'

@description('Whether to create the custom domain binding. Set false on first deploy until DNS CNAME is in place.')
param createCustomDomain bool = true

// ─── Naming ──────────────────────────────────────────────────────────────────
// All resource names follow Azure convention: <type>-<project>-<env>
// Using a unique suffix derived from the resource group id to avoid global name conflicts.
var uniqueSuffix = take(uniqueString(resourceGroup().id), 6)
var appName = 'func-campfire-${uniqueSuffix}'
var storageAccountName = 'stcampfire${uniqueSuffix}'   // storage names: lowercase, no hyphens, max 24 chars
var hostingPlanName = 'plan-campfire-${uniqueSuffix}'
var appInsightsName = 'appi-campfire-${uniqueSuffix}'
var logAnalyticsName = 'log-campfire-${uniqueSuffix}'

var tags = {
  project: 'campfire-hosting'
  environment: 'production'
  domain: domainName
}

// ─── Modules ─────────────────────────────────────────────────────────────────

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    location: location
    tags: tags
  }
}

module functions 'modules/functions.bicep' = {
  name: 'functions'
  params: {
    appName: appName
    hostingPlanName: hostingPlanName
    location: location
    tags: tags
    storageConnectionString: storage.outputs.connectionString
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    keyVaultName: keyVaultName
    cfDomain: cfDomain
  }
}

module dns 'modules/dns.bicep' = if (createCustomDomain) {
  name: 'dns'
  params: {
    appName: appName
    domainName: domainName
    location: location
  }
  dependsOn: [functions]
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('URL of the deployed Function App.')
output functionAppUrl string = 'https://${appName}.azurewebsites.net'

@description('Custom domain URL (once DNS and cert are provisioned).')
output customDomainUrl string = 'https://${domainName}'

@description('Storage account name (needed for Table Storage connection).')
output storageAccountName string = storageAccountName

@description('Application Insights instrumentation key.')
output appInsightsInstrumentationKey string = monitoring.outputs.appInsightsInstrumentationKey

@description('Application Insights connection string.')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

@description('Function App managed identity principal ID — grant this Key Vault Secrets User on the Key Vault.')
output functionAppPrincipalId string = functions.outputs.principalId

@description('Function App name.')
output functionAppName string = appName
