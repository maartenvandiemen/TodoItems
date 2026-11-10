param location string
param keyVaultName string
param applicationname string

param applicationInsightsConnectionString string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker')
param dockerImageNameAndTag string = ''

@description('Subnet delegated to Microsoft.Web/serverFarms for regional VNet integration (outbound traffic). Empty: no VNet integration.')
param integrationSubnetId string = ''

@description('Subnet for the private endpoint (inbound traffic). Empty: no private endpoint, the web app stays publicly reachable.')
param privateEndpointSubnetId string = ''

@description('Resource id of the privatelink.azurewebsites.net private DNS zone. Required when privateEndpointSubnetId is set.')
param privateDnsZoneId string = ''

var usePrivateEndpoint = !empty(privateEndpointSubnetId)

var appServiceAppName = 'site-${applicationname}-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'sitePlan-${applicationname}-${uniqueString(resourceGroup().id)}'

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'P1V3'
  }
  properties:{
    reserved: true
  }
  kind: 'linux'
}

var defaultAppsettings = [
      {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
      }]

var appsettingsValues = concat(defaultAppsettings, empty(dockerImageNameAndTag) ? [] : [
          {
              name: 'WEBSITES_PORT'
              value: 8080
          }])  

// Public network access has to be set explicitly. 'Disabled' blocks the main site AND the SCM (Kudu) site for
// everything but the private endpoint, and the access restrictions below cannot override that.
//  - zip deploy (no docker image): the pipeline pushes the code through the public SCM site, so public network
//    access stays 'Enabled'. The access restrictions below keep the main site private, and the SCM site closed
//    except for the temporary rule the pipeline adds for its own IP address during the deployment.
//  - docker image: App Service pulls the image itself (outbound), nothing has to reach the app from the
//    internet, so public network access can be 'Disabled' when there is a private endpoint.
var webAppPublicNetworkAccess = usePrivateEndpoint && !empty(dockerImageNameAndTag) ? 'Disabled' : 'Enabled'

// With a private endpoint the main site only accepts traffic that comes through the private endpoint
// (access restrictions do not apply to private endpoint traffic). The SCM site has its own rule set: also
// denied by default. A pipeline that deploys a zip adds a rule for its own IP address and removes it afterwards.
var privateEndpointSiteConfig = usePrivateEndpoint ? {
  ipSecurityRestrictionsDefaultAction: 'Deny'
  scmIpSecurityRestrictionsDefaultAction: 'Deny'
  scmIpSecurityRestrictionsUseMain: false
} : {}

resource appServiceApp 'Microsoft.Web/sites@2025-03-01' = {
  name: appServiceAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: webAppPublicNetworkAccess
    virtualNetworkSubnetId: empty(integrationSubnetId) ? null : integrationSubnetId
    siteConfig: union({
     acrUseManagedIdentityCreds: false
     linuxFxVersion: empty(dockerImageNameAndTag) ? 'DOTNET|11' : 'DOCKER|${dockerImageNameAndTag}'
     healthCheckPath: '/health'
     connectionStrings: [
      {
        name: 'TodoDb'
        connectionString: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=ConnectionString)'
        type: 'SQLAzure'
      }
     ]
     appSettings: appsettingsValues
    }, privateEndpointSiteConfig)
  }
  identity: {
    type: 'SystemAssigned'
 }
}

resource webAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = if (usePrivateEndpoint) {
  name: 'pe-${appServiceAppName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'webapp'
        properties: {
          privateLinkServiceId: appServiceApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

// Registers the private IP of the endpoint in the private DNS zone, so that
// <app>.azurewebsites.net resolves to the private endpoint for everything that uses the zone.
resource webAppDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-03-01' = if (usePrivateEndpoint) {
  parent: webAppPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azurewebsites'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output principalId string = appServiceApp.identity.principalId
output webAppName string = appServiceApp.name
output webAppHostName string = appServiceApp.properties.defaultHostName
output webAppUrl string = 'https://${appServiceApp.properties.defaultHostName}'
