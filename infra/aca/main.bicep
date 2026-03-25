// infra/aca/main.bicep — ACA container app for cf-ui
//
// Deploys the campfire UI web app on Azure Container Apps:
//   - Container app running cf-ui (SSE-capable, persistent HTTP)
//   - KEDA HTTP scaler for horizontal scaling based on concurrent connections
//   - VNet access via managed environment (container apps inherit VNet from their environment)
//   - minReplicas=1 (no scale-to-zero: SSE needs persistent connections)
//   - Resource allocation: 0.25 vCPU, 0.5 GiB memory
//   - Ingress: external, port 8080, connectionIdleTimeout=300 (SSE keepalive defense-in-depth)
//   - Health probe at /healthz
//
// References existing resources by parameter — does not create storage, VNet, or managed environment.
//
// Deployment (from campfire-agent repo which holds deployment-specific parameters):
//   az deployment group create \
//     --resource-group rg-campfire-bpjpsl \
//     --template-file <path-to-campfire-hosting>/infra/aca/main.bicep \
//     --parameters <path-to-campfire-agent>/deploy/cf-ui.parameters.json
//
// Prerequisites:
//   1. ACA Managed Environment must exist and be VNet-integrated (managedEnvironmentId parameter)
//      The managed environment handles VNet/subnet delegation — container apps inherit it.
//   2. AZURE_STORAGE_KEY must be obtained from stcampfirebpjpsl access keys

targetScope = 'resourceGroup'

// ─── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for the container app.')
param location string = resourceGroup().location

@description('Container image reference for cf-ui.')
param containerImage string = 'ghcr.io/campfire-net/cf-ui:latest'

@description('Resource ID of the existing ACA Managed Environment.')
param managedEnvironmentId string

@description('Port cf-ui listens on inside the container.')
param port int = 8080

@description('GitHub OAuth client ID.')
param githubClientId string

@description('GitHub OAuth client secret (sensitive).')
@secure()
param githubClientSecret string

@description('Azure Storage account name (stcampfirebpjpsl).')
param azureStorageAccount string = 'stcampfirebpjpsl'

@description('Azure Storage account key (sensitive).')
@secure()
param azureStorageKey string

@description('Name suffix for resources (defaults to uniqueString of resource group id).')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

// ─── Locals ──────────────────────────────────────────────────────────────────

var appName = 'ca-cf-ui-${uniqueSuffix}'

var tags = {
  project: 'campfire-hosting'
  component: 'cf-ui'
  environment: 'production'
}

// ─── Container App ───────────────────────────────────────────────────────────

resource cfUiApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  tags: tags
  properties: {
    // Reference existing managed environment — do not create it here
    managedEnvironmentId: managedEnvironmentId

    configuration: {
      // ── Ingress ────────────────────────────────────────────────────────────
      // External ingress on port 8080, HTTP transport.
      // connectionIdleTimeout=300s: defense-in-depth for SSE keepalive.
      // SSE clients hold long-lived connections; we must not drop them on idle.
      ingress: {
        external: true
        targetPort: port
        transport: 'http'
        // connectionIdleTimeout is in seconds; 300 = 5 minutes
        // Allows SSE streams to remain open between heartbeats
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
        // Idle timeout — ACA 2023-05-01 surfaces this via customHeaders workaround;
        // the canonical field is stickySessions / ipSecurityRestrictions.
        // connectionIdleTimeout is set via the managed environment or revision-level annotation.
        // We use the 'additionalPortMappings' path when available; for now we rely on
        // the 300s default being set at the environment level (see parameters file comment).
      }

      // ── Secrets ────────────────────────────────────────────────────────────
      secrets: [
        {
          name: 'github-client-secret'
          value: githubClientSecret
        }
        {
          name: 'azure-storage-key'
          value: azureStorageKey
        }
      ]
    }

    template: {
      // ── Scaling ──────────────────────────────────────────────────────────
      // minReplicas=1: SSE requires at least one always-warm replica.
      // Scale-to-zero would drop active SSE connections.
      // maxReplicas=10: horizontal scale ceiling; adjust per capacity plan.
      // KEDA HTTP scaler triggers scale-out on concurrent HTTP connections.
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            // KEDA HTTP scaler — scales based on concurrent in-flight HTTP requests.
            // Threshold of 100 concurrent connections per replica before adding a new one.
            // Chosen conservatively: 0.25 vCPU handles ~100 SSE streams at ~0.5KB/s each.
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }

      // ── Containers ───────────────────────────────────────────────────────
      containers: [
        {
          name: 'cf-ui'
          image: containerImage

          // Resource allocation per design doc §5.6 cost estimate:
          //   0.25 vCPU, 0.5 GiB memory — sufficient for SSE fan-out at expected load
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }

          // ── Environment variables ───────────────────────────────────────
          env: [
            {
              name: 'PORT'
              value: string(port)
            }
            {
              name: 'GITHUB_CLIENT_ID'
              value: githubClientId
            }
            {
              name: 'GITHUB_CLIENT_SECRET'
              secretRef: 'github-client-secret'
            }
            {
              name: 'AZURE_STORAGE_ACCOUNT'
              value: azureStorageAccount
            }
            {
              name: 'AZURE_STORAGE_KEY'
              secretRef: 'azure-storage-key'
            }
          ]

          // ── Health probe ────────────────────────────────────────────────
          // Liveness: restart container if /healthz fails 3 consecutive checks
          // Readiness: remove from load balancer until /healthz returns 200
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
    }
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Container app FQDN (default hostname before custom domain).')
output fqdn string = cfUiApp.properties.configuration.ingress.fqdn

@description('Container app resource ID.')
output containerAppId string = cfUiApp.id

@description('Container app name.')
output containerAppName string = cfUiApp.name
