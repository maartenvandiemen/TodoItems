param location string
param applicationname string

var blazorAppServiceAppName = 'site-blazor-${applicationname}-${uniqueString(resourceGroup().id)}'
var blazorAppServicePlanName = 'sitePlan-blazor-${applicationname}-${uniqueString(resourceGroup().id)}'

resource blazorAppServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: blazorAppServicePlanName
  location: location
  sku: {
    name: 'P1V3'
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource blazorAppServiceApp 'Microsoft.Web/sites@2024-11-01' = {
  name: blazorAppServiceAppName
  location: location
  properties: {
    serverFarmId: blazorAppServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output webAppName string = blazorAppServiceApp.name
output webAppUrl string = 'https://${blazorAppServiceApp.properties.defaultHostName}'
