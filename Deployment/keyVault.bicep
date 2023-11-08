param location string
param keyVaultName string
param appServicePrincipalId string

param sqlServerData object

param sqlAdministratorLoginUser string

@secure ()
param sqlAdministratorLoginPassword string

resource key_vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'ConnectionString'
  parent: key_vault
  properties: {
    value: 'Data Source=tcp:${sqlServerData.fullyQualifiedDomainName},1433;Initial Catalog=${sqlServerData.databaseName};Persist Security Info=False;User Id=${sqlAdministratorLoginUser};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;'
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: key_vault
  name: guid(keyVaultName, resourceGroup().id, appServicePrincipalId, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: appServicePrincipalId
  }
}
