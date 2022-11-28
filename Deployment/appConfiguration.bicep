param location string
param appServicePrincipalId string

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

var appConfigurationStoreName = 'appConfiguration-${stage}'

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2021-03-01-preview' = {
  name: appConfigurationStoreName
  identity: {
    type: 'SystemAssigned'
  }
  location: location
  sku: {
    name: 'free'
  }

  resource kv3 'keyValues' = {
    name: 'SomeOtherKeyValuePair$development' 
    properties: {
      value: '<value_for_development>'
    }
  }
}

var roleDefinitionAppConfigurationDataReader= subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '516239f1-63e1-4d78-a4de-a74fb236a071')

resource appConfigurationAppServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2021-04-01-preview' = {
  name: guid(appConfigurationStoreName, resourceGroup().id, roleDefinitionAppConfigurationDataReader)
  scope: appConfiguration
  properties: {
    roleDefinitionId: roleDefinitionAppConfigurationDataReader
    principalId: appServicePrincipalId
  }
}

output principalId string = appConfiguration.identity.principalId
