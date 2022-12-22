param location string

param applicationname string

param applicationInsightsConnectionString string

param acrLoginServer string
param dockerRepositoryAndVersion string

var appServiceAppName = 'site-${applicationname}-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'sitePlan-${applicationname}-${uniqueString(resourceGroup().id)}'

resource websiteUserManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: 'webAppUserManagedIdentity-${appServiceAppName}'
  location: location
 }

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

output principalId string = websiteUserManagedIdentity.properties.principalId
output webAppName string = appServiceApp.name
