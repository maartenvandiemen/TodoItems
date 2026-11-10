// Orchestrator: deploys one complete instance of the solution.
//
//   <prefix>-hub       hub.bicep      VNet, firewall, private DNS zones, Log Analytics workspace and the
//                                     Azure Monitor private link scope (private endpoint in the hub)
//   <prefix>-<spoke>   spoke.bicep    one resource group per spoke: VNet, route table, peering to the hub
//                      webApp.bicep   in the resource group of the first spoke: web app (private endpoint),
//                                     sql, key vault, application gateway
//
// Deployed at subscription scope because it creates the resource groups itself. The order is defined by the
// outputs that are used as input: hub -> spokes -> web app. Nothing is shared between instances.
// Every resource group is tagged with the instance, so a pipeline can find (and clean up) all of them.
targetScope = 'subscription'

import { spokes } from 'network/addressPlan.bicep'

@description('Azure region of all resources.')
param location string

param applicationname string

@description('Unique name of this instance, for example todoItems-52155627557. The resource groups are named <prefix>-hub and <prefix>-<spoke name>.')
param resourceGroupPrefix string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker. Empty: no container, the pipeline deploys a zip.')
param dockerImageNameAndTag string = ''

@description('Who may query logs and telemetry (Log Analytics workspace, Application Insights). Open: also from public networks, for example the Azure portal (authenticated). PrivateOnly: only from connected private networks, the portal then cannot show the logs from outside the network. Ingestion is always private only.')
@allowed([
  'Open'
  'PrivateOnly'
])
param monitorQueryAccessMode string = 'Open'

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: '${resourceGroupPrefix}-hub'
  location: location
  tags: {
    instance: resourceGroupPrefix
    role: 'hub'
  }
}

resource spokeResourceGroups 'Microsoft.Resources/resourceGroups@2025-04-01' = [for spoke in spokes: {
  name: '${resourceGroupPrefix}-${spoke.name}'
  location: location
  tags: {
    instance: resourceGroupPrefix
    role: 'spoke'
  }
}]

module hub 'network/hub.bicep' = {
  name: 'hub'
  scope: hubResourceGroup
  params: {
    location: location
    monitorQueryAccessMode: monitorQueryAccessMode
  }
}

// Peerings are created one at a time (batchSize 1). Creating several peerings against the same
// virtual network in parallel can fail with 'AnotherOperationInProgress'.
@batchSize(1)
module spokeNetworks 'network/spoke.bicep' = [for (spoke, index) in spokes: {
  name: 'spoke-${spoke.name}'
  scope: spokeResourceGroups[index]
  params: {
    location: location
    spoke: spoke
    otherSpokes: filter(spokes, other => other.name != spoke.name)
    hubVnetId: hub.outputs.hubVnetId
    firewallPrivateIp: hub.outputs.firewallPrivateIp
  }
}]

// The hub side of each peering and the DNS zone link live in the hub resource group.
// Only after all spokes: the hub VNet is involved in every peering.
@batchSize(1)
module hubSides 'network/hubSideOfSpoke.bicep' = [for (spoke, index) in spokes: {
  name: 'hubside-${spoke.name}'
  scope: hubResourceGroup
  params: {
    hubVnetName: hub.outputs.hubVnetName
    spokeName: spoke.name
    spokeVnetId: spokeNetworks[index].outputs.vnetId
  }
}]

// The web app lives in the first spoke.
module webApp 'webApp.bicep' = {
  name: 'webApp'
  scope: spokeResourceGroups[0]
  params: {
    location: location
    applicationname: applicationname
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    dockerImageNameAndTag: dockerImageNameAndTag
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
    monitorQueryAccessMode: monitorQueryAccessMode
    integrationSubnetId: spokeNetworks[0].outputs.appServiceSubnetId
    privateEndpointSubnetId: spokeNetworks[0].outputs.privateEndpointSubnetId
    privateDnsZoneId: hub.outputs.webAppPrivateDnsZoneId
    appGatewaySubnetId: spokeNetworks[0].outputs.appGatewaySubnetId
  }
  // The DNS zone must be linked to the spoke before the web app creates its private endpoint and the
  // gateway resolves the hostname: the gateway caches DNS lookups of its backend.
  dependsOn: [
    hubSides
  ]
}

// Application Insights is added to the Azure Monitor private link scope of the hub, which lives in the
// hub resource group. That can only happen now that the component exists.
module appInsightsPrivateLink 'network/monitorScopedResource.bicep' = {
  name: 'appInsightsPrivateLink'
  scope: hubResourceGroup
  params: {
    monitorPrivateLinkScopeName: hub.outputs.monitorPrivateLinkScopeName
    name: 'appinsights-connection'
    linkedResourceId: webApp.outputs.appInsightsId
  }
}

output appResourceGroupName string = spokeResourceGroups[0].name
output webAppUrl string = webApp.outputs.webAppUrl
output webAppName string = webApp.outputs.webAppName
output gatewayUrl string = webApp.outputs.gatewayUrl
output sqlServerFQDN string = webApp.outputs.sqlServerFQDN
output databaseName string = webApp.outputs.databaseName
