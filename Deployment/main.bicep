// Orchestrator: deploys one complete instance of the solution.
//
//   hub resource group     hub.bicep      VNet, firewall, private DNS zone
//   spokes resource group  spokes.bicep   spoke VNets, peerings, route tables
//                          webApp.bicep   web app (private endpoint), sql, key vault, application gateway
//
// Deployed at subscription scope because it creates the resource groups itself. The order is defined by the
// outputs that are used as input: hub -> spokes -> web app. Nothing is shared between instances.
targetScope = 'subscription'

@description('Azure region of all resources.')
param location string

param applicationname string

@description('Resource group of the hub. Created by this template.')
param hubResourceGroupName string

@description('Resource group of the spokes and the web app. Created by this template.')
param spokesResourceGroupName string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker. Empty: no container, the pipeline deploys a zip.')
param dockerImageNameAndTag string = ''

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: hubResourceGroupName
  location: location
}

resource spokesResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: spokesResourceGroupName
  location: location
}

module hub 'network/hub.bicep' = {
  name: 'hub'
  scope: hubResourceGroup
  params: {
    location: location
  }
}

module spokes 'network/spokes.bicep' = {
  name: 'spokes'
  scope: spokesResourceGroup
  params: {
    location: location
    hubResourceGroupName: hubResourceGroup.name
    firewallPrivateIp: hub.outputs.firewallPrivateIp
  }
}

module webApp 'webApp.bicep' = {
  name: 'webApp'
  scope: spokesResourceGroup
  params: {
    location: location
    applicationname: applicationname
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    dockerImageNameAndTag: dockerImageNameAndTag
    integrationSubnetId: spokes.outputs.appServiceSubnetId
    privateEndpointSubnetId: spokes.outputs.privateEndpointSubnetId
    privateDnsZoneId: hub.outputs.webAppPrivateDnsZoneId
    appGatewaySubnetId: spokes.outputs.appGatewaySubnetId
  }
}

output webAppUrl string = webApp.outputs.webAppUrl
output webAppName string = webApp.outputs.webAppName
output gatewayUrl string = webApp.outputs.gatewayUrl
output sqlServerFQDN string = webApp.outputs.sqlServerFQDN
output databaseName string = webApp.outputs.databaseName
