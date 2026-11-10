param location string

param applicationname string

@description('Resource id of the Log Analytics workspace the telemetry is sent to. The workspace is shared by the whole instance and lives in the hub.')
param workspaceResourceId string

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
    // Telemetry only gets in through the private endpoint of the Azure Monitor private link scope in the hub.
    // The component has to be added to that scope (network/monitorScopedResource.bicep), otherwise the
    // application cannot send telemetry.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: monitorQueryAccessMode == 'Open' ? 'Enabled' : 'Disabled'
    WorkspaceResourceId: workspaceResourceId
  }
}

output id string = appInsights.id
output connectionString string = appInsights.properties.ConnectionString
