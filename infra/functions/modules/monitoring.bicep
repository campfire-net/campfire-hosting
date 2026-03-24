// modules/monitoring.bicep — Log Analytics workspace + Application Insights
//
// Application Insights is the telemetry sink for the Function App.
// Log Analytics is the backing store for App Insights (workspace-based mode, required for new deployments).
//
// Retention: 30 days (Log Analytics default, free tier threshold).
// Upgrade retention in the Log Analytics workspace properties if compliance requires longer.

param logAnalyticsName string
param appInsightsName string
param location string
param tags object

// Log Analytics Workspace — backing store for App Insights
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'    // pay-per-GB, no commitment — cheapest option
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights — workspace-based (classic is deprecated)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Application Insights instrumentation key (legacy — prefer connection string).')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights connection string (preferred over instrumentation key).')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights resource ID.')
output appInsightsId string = appInsights.id

@description('Log Analytics workspace ID.')
output logAnalyticsWorkspaceId string = logAnalytics.id
