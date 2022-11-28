param location string
param appServicePrincipalId string

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

@maxLength(16)
param applicationname string

var keyVaultName = '${applicationname}-vault-${stage}'

resource key_vault 'Microsoft.KeyVault/vaults@2019-09-01' = {
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

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2018-09-01-preview' = {
  scope: key_vault
  name: guid(keyVaultName, resourceGroup().id, appServicePrincipalId, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
    principalId: appServicePrincipalId
  }
}
