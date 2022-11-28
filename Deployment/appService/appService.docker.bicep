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

param acrLoginServer string
param dockerRepositoryAndVersion string

var appServiceAppName = '${applicationname}-${stage}'
var appServicePlanName = '${applicationname}-${stage}-plan'
var appServicePlanSkuName = (stage == 'P') ? 'B2' : 'B1'

resource websiteUserManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: 'webAppUserManagedIdentity-${stage}'
  location: location
 }

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
    //The keyVaultReferenceIdentity defines which identity must be used to fetch Key Vault references
    keyVaultReferenceIdentity: websiteUserManagedIdentity.id
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${websiteUserManagedIdentity.id}' : {}
    }
  }
    resource siteConfig 'config' ={
      name: 'web'
      properties: {
        acrUseManagedIdentityCreds: true
        acrUserManagedIdentityID: websiteUserManagedIdentity.properties.clientId
        linuxFxVersion: 'DOCKER|${toLower(acrLoginServer)}/${toLower(dockerRepositoryAndVersion)}'
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

output principalId string = websiteUserManagedIdentity.properties.principalId
