// Application Insights of the web app, with its telemetry going to the central Log Analytics workspace.
// Deploy into the resource group of the instance, next to the workspace and the Azure Monitor private link scope:
// everything that is connected to the scope lives in one resource group, and is deleted together with it.
// (A resource that is connected to a private link scope cannot be deleted on its own.)

param location string

param applicationname string

@description('Resource id of the Log Analytics workspace the telemetry is sent to.')
param workspaceResourceId string

@description('Name of the Azure Monitor private link scope in this resource group. Application Insights is connected to it, so telemetry only gets in through its private endpoint.')
param monitorPrivateLinkScopeName string

var applicationInsightsName = 'insights-${applicationname}-${uniqueString(resourceGroup().id)}'

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // With a private link scope, telemetry only gets in through its private endpoint: connected below.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Enabled'
    WorkspaceResourceId: workspaceResourceId
  }
}

resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' existing = {
  name: monitorPrivateLinkScopeName
}

resource scopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: monitorPrivateLinkScope
  name: '${appInsights.name}-connection'
  properties: {
    linkedResourceId: appInsights.id
  }
}

output connectionString string = appInsights.properties.ConnectionString
