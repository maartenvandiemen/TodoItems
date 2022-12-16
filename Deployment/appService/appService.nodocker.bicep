param location string

param applicationname string

param applicationInsightsConnectionString string

var appServiceAppName = 'site-${applicationname}-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'sitePlan-${applicationname}-${uniqueString(resourceGroup().id)}'

resource appServicePlan 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
  }
  properties:{
    reserved: true
  }
  kind: 'linux'
}

resource appServiceApp 'Microsoft.Web/sites@2021-02-01' = {
  name: appServiceAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
 }
    resource siteConfig 'config' ={
      name: 'web'
      properties: {
        linuxFxVersion: 'DOTNETCORE|7.0'
        appSettings: [
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: applicationInsightsConnectionString
          }   
        ]
      }
    }

    resource siteConnectionstrings 'config'={
      name: 'connectionstrings'
      properties:{
        TodoDb:{
        value: '@Microsoft.KeyVault(VaultName=myvault;SecretName=ConnectionString)'
        type: 'SQLAzure'
      }
    }
  }
}

output principalId string = appServiceApp.identity.principalId
output webAppName string = appServiceApp.name
