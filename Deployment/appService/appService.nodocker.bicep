param location string

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

param sqlServerData object
param applicationname string

@secure ()
param sqlAdministratorLoginPassword string

param applicationInsightsInstrumentationKey string

var appServiceAppName = '${applicationname}-${stage}'
var appServicePlanName = '${applicationname}-${stage}-plan'
var appServicePlanSkuName = (stage == 'P') ? 'B2' : 'B1'

resource appServicePlan 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSkuName
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
        linuxFxVersion: ''
        appSettings: [
          {
            'name': 'APPINSIGHTS_INSTRUMENTATIONKEY'
            'value': applicationInsightsInstrumentationKey
          }   
        ]
      }
    }

    resource siteConnectionstrings 'config'={
      name: 'connectionstrings'
      properties:{
        TodoDb:{
        value: 'Data Source=tcp:${sqlServerData.fullyQualifiedDomainName},1433;Initial Catalog=${sqlServerData.databaseName};Persist Security Info=False;User Id=${sqlServerData.sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
        type: 'SQLAzure'
      }
    }
  }
}

output principalId string = appServiceApp.identity.principalId
