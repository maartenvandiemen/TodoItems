// Orchestrator: deploys one complete instance of the application in ONE resource group, with one virtual network.
//
//   <prefix>-app   network/network.bicep   VNet (a subnet and an NSG per tier), private DNS zones, Log Analytics
//                  network/ampls.bicep     Azure Monitor private link scope (optional, enableAmpls)
//                  applicationInsights.bicep
//                  webApp.bicep            web app (private endpoint, VNet integration), SQL (private endpoint),
//                                          Key Vault (private endpoint), Application Gateway in front of the web app
//
// Microsoft's recommendations for a web application: the data services and the web app are only reachable through
// private endpoints, an NSG on every subnet, a gateway as the only public entrance, and the logs of all parts in
// one workspace. One VNet means nothing to route or peer: no hub, no firewall.
//
// Deployed at subscription scope because it creates the resource group itself. Nothing is shared between instances.
// The resource group is tagged with the instance, so a pipeline can find (and clean up) it.
targetScope = 'subscription'

@description('Azure region of all resources.')
param location string

param applicationname string

@description('Unique name of this instance, for example todoItems-52155627557. The resource group is named <prefix>-app.')
param resourceGroupPrefix string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker. Empty: no container, the pipeline deploys a zip.')
param dockerImageNameAndTag string = ''

@description('Deploy an Azure Monitor private link scope: the telemetry of the application (Application Insights, Log Analytics) goes through a private endpoint, with five extra private DNS zones. Without it the workspace and Application Insights accept public ingestion.')
param enableAmpls bool = true

resource appResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: '${resourceGroupPrefix}-app'
  location: location
  tags: {
    instance: resourceGroupPrefix
  }
}

module network 'network/network.bicep' = {
  name: 'network'
  scope: appResourceGroup
  params: {
    location: location
    enableAmpls: enableAmpls
  }
}

module appInsights 'applicationInsights.bicep' = {
  name: 'appInsights'
  scope: appResourceGroup
  params: {
    location: location
    applicationname: applicationname
    workspaceResourceId: network.outputs.logAnalyticsWorkspaceId
    enableAmpls: enableAmpls
    monitorPrivateLinkScopeName: network.outputs.monitorPrivateLinkScopeName
  }
}

module webApp 'webApp.bicep' = {
  name: 'webApp'
  scope: appResourceGroup
  params: {
    location: location
    applicationname: applicationname
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    dockerImageNameAndTag: dockerImageNameAndTag
    applicationInsightsConnectionString: appInsights.outputs.connectionString
    logAnalyticsWorkspaceId: network.outputs.logAnalyticsWorkspaceId
    sqlPrivateDnsZoneId: network.outputs.sqlPrivateDnsZoneId
    keyVaultPrivateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId
    integrationSubnetId: network.outputs.appServiceSubnetId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: network.outputs.webAppPrivateDnsZoneId
    appGatewaySubnetId: network.outputs.appGatewaySubnetId
  }
}

output appResourceGroupName string = appResourceGroup.name
output webAppUrl string = webApp.outputs.webAppUrl
output webAppName string = webApp.outputs.webAppName
output gatewayUrl string = webApp.outputs.gatewayUrl
output sqlServerFQDN string = webApp.outputs.sqlServerFQDN
output databaseName string = webApp.outputs.databaseName
