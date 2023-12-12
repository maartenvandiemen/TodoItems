param location string
param keyVaultName string
param applicationname string

param applicationInsightsConnectionString string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker')
param dockerImageNameAndTag string = ''

var appServiceAppName = 'site-${applicationname}-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'sitePlan-${applicationname}-${uniqueString(resourceGroup().id)}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
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

resource appServiceApp 'Microsoft.Web/sites@2022-09-01' = {
  name: appServiceAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
     acrUseManagedIdentityCreds: false
     linuxFxVersion: empty(dockerImageNameAndTag) ? 'DOTNETCORE|7.0' : 'DOCKER|${dockerImageNameAndTag}'
     healthCheckPath: '/health'
     connectionStrings: [
      { 
        name: 'TodoDb'
        connectionString: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=ConnectionString)'
        type: 'SQLAzure'
      }
     ]
     appSettings: [
      {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
      }
     ]
    }
  }  
  identity: {
    type: 'SystemAssigned'
 }
}

output principalId string = appServiceApp.identity.principalId
output webAppName string = appServiceApp.name
output webAppUrl string = 'https://${appServiceApp.properties.defaultHostName}'
