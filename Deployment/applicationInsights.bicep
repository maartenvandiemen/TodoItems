// Application Insights of the web app, with its telemetry going to the central Log Analytics workspace.
// Deploy into the HUB resource group, next to the workspace and the Azure Monitor private link scope:
// everything that is connected to the scope then lives in one resource group, and is deleted together with it.
// (A resource that is connected to a private link scope cannot be deleted on its own.)

param location string

param applicationname string

@description('Resource id of the Log Analytics workspace the telemetry is sent to. The workspace is shared by the whole instance and lives in the hub.')
param workspaceResourceId string

@description('Name of the Azure Monitor private link scope in this resource group.')
param monitorPrivateLinkScopeName string

@description('Who may query the telemetry: Open also allows queries from public networks (the Azure portal, authenticated), PrivateOnly only from the connected private networks. Ingestion is always private only.')
@allowed([
  'Open'
  'PrivateOnly'
])
param monitorQueryAccessMode string = 'Open'

var applicationInsightsName = 'insights-${applicationname}-${uniqueString(resourceGroup().id)}'

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Telemetry only gets in through the private endpoint of the private link scope: connected below.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: monitorQueryAccessMode == 'Open' ? 'Enabled' : 'Disabled'
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
