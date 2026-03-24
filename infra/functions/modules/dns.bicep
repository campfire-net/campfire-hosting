// modules/dns.bicep — Custom domain binding + managed TLS certificate
//
// Binds the custom domain (mcp.getcampfire.dev) to the Function App and provisions
// a free managed TLS certificate via Azure App Service.
//
// IMPORTANT — DNS prerequisite:
//   Before deploying this module, create DNS records in your DNS provider:
//
//   1. CNAME record:
//      mcp.getcampfire.dev → <appName>.azurewebsites.net
//
//   2. TXT record for domain ownership verification:
//      asuid.mcp.getcampfire.dev → <customDomainVerificationId from Function App>
//      Get the verification ID:
//        az webapp show --name <appName> --resource-group <rg> \
//          --query properties.customDomainVerificationId -o tsv
//
//   DNS propagation can take up to 48h. Deploy with createCustomDomain=false until DNS is live,
//   then re-run with createCustomDomain=true.
//
// TLS:
//   Azure App Service Managed Certificate is free for custom domains on App Service plans.
//   It auto-renews 60 days before expiry. The certificate covers one hostname (no wildcard).

param appName string
param domainName string
param location string

// Reference the existing Function App (created in functions.bicep)
resource functionApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: appName
}

// Step 1: Bind the custom hostname to the Function App.
// Azure validates that the CNAME and TXT records exist before accepting the binding.
resource customHostnameBinding 'Microsoft.Web/sites/hostNameBindings@2022-09-01' = {
  parent: functionApp
  name: domainName
  properties: {
    hostNameType: 'Verified'
    sslState: 'Disabled'    // TLS attached via managed certificate resource below
    customHostNameDnsRecordType: 'CName'
  }
}

// Step 2: Provision a free managed TLS certificate for the hostname.
// The certificate is automatically renewed by Azure before expiry.
resource managedCertificate 'Microsoft.Web/certificates@2022-09-01' = {
  name: '${appName}-${replace(domainName, '.', '-')}-cert'
  location: location
  properties: {
    serverFarmId: functionApp.properties.serverFarmId
    canonicalName: domainName    // must match the custom hostname binding
  }
  dependsOn: [customHostnameBinding]
}

// Step 3: Enable SNI SSL on the hostname binding using the managed certificate.
resource sslBinding 'Microsoft.Web/sites/hostNameBindings@2022-09-01' = {
  parent: functionApp
  name: domainName
  properties: {
    hostNameType: 'Verified'
    sslState: 'SniEnabled'
    thumbprint: managedCertificate.properties.thumbprint
    customHostNameDnsRecordType: 'CName'
  }
}


// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Bound custom domain name.')
output boundDomain string = domainName

@description('Managed certificate thumbprint.')
output certificateThumbprint string = managedCertificate.properties.thumbprint

@description('Certificate expiry date.')
output certificateExpiryDate string = managedCertificate.properties.expirationDate
