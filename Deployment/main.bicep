// Orchestrator: deploys one complete instance of the application in ONE resource group, with one virtual network.
//
//   network/network.bicep   VNet (a subnet and an NSG per tier), private DNS zones, Log Analytics
//   network/ampls.bicep     Azure Monitor private link scope
//   applicationInsights.bicep
//   sql.bicep               SQL server and database (private endpoint)
//   appService.bicep        web app (private endpoint, VNet integration)
//   keyVault.bicep          Key Vault (private endpoint) with the connection string of the database
//   appGateway.bicep        Application Gateway in front of the web app
//
// Microsoft's recommendations for a web application: the data services and the web app are only reachable through
// private endpoints, an NSG on every subnet, a gateway as the only public entrance, and the logs of all parts in
// one workspace. One VNet means nothing to route or peer: no hub, no firewall.
//
// Deployed into a resource group that the pipeline creates (az group create). Nothing is shared between instances.
//
// dockerImageNameAndTag empty: the web app runs the .NET runtime stack and the pipeline deploys a zip.
// dockerImageNameAndTag set:   the web app runs that container image.

@description('Azure region of all resources.')
param location string = resourceGroup().location

@description('Used in the names of the resources. It is also the name of the database.')
param applicationname string = 'todoitems'

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker. Empty: no container, the pipeline deploys a zip.')
param dockerImageNameAndTag string = ''

var keyVaultName = 'vault-${uniqueString(resourceGroup().id)}'

module network 'network/network.bicep' = {
  name: 'network'
  params: {
    location: location
  }
}

module appInsights 'applicationInsights.bicep' = {
  name: 'appInsights'
  params: {
    location: location
    applicationname: applicationname
    workspaceResourceId: network.outputs.logAnalyticsWorkspaceId
    monitorPrivateLinkScopeName: network.outputs.monitorPrivateLinkScopeName
  }
}

module sql 'sql.bicep' = {
  name: 'sql'
  params: {
    location: location
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    applicationname: applicationname
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.sqlPrivateDnsZoneId
    workspaceId: network.outputs.logAnalyticsWorkspaceId
  }
}

module appService 'appService.bicep' = {
  name: 'appService'
  params: {
    keyVaultName: keyVaultName
    location: location
    applicationname: applicationname
    applicationInsightsConnectionString: appInsights.outputs.connectionString
    dockerImageNameAndTag: dockerImageNameAndTag
    integrationSubnetId: network.outputs.appServiceSubnetId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.webAppPrivateDnsZoneId
    workspaceId: network.outputs.logAnalyticsWorkspaceId
  }
}

// Uses the hostname output of the appService module. A module output is only available after the whole
// module has been deployed, including the private endpoint and its DNS registration. Exactly what the
// gateway needs: it caches the DNS lookup of its backend.
module appGateway 'appGateway.bicep' = {
  name: 'appGateway'
  params: {
    location: location
    applicationname: applicationname
    subnetId: network.outputs.appGatewaySubnetId
    backendHostName: appService.outputs.webAppHostName
    workspaceId: network.outputs.logAnalyticsWorkspaceId
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault'
  params: {
    keyVaultName: keyVaultName
    location: location
    appServicePrincipalId: appService.outputs.principalId
    sqlServerFQDN: sql.outputs.sqlServerFQDN
    databaseName: sql.outputs.databaseName
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId
    workspaceId: network.outputs.logAnalyticsWorkspaceId
  }
}

output webAppUrl string = appService.outputs.webAppUrl
output webAppName string = appService.outputs.webAppName
output gatewayUrl string = appGateway.outputs.gatewayUrl
output sqlServerName string = sql.outputs.sqlServerName
output sqlServerFQDN string = sql.outputs.sqlServerFQDN
output databaseName string = sql.outputs.databaseName
