param location string
param keyVaultName string
param appServicePrincipalId string

param sqlServerFQDN string

param databaseName string

param sqlAdministratorLoginUser string

@secure ()
param sqlAdministratorLoginPassword string

@description('Subnet for the private endpoint of the key vault.')
param privateEndpointSubnetId string

@description('Resource id of the private DNS zone for Key Vault (privatelink.vaultcore.azure.net).')
param privateDnsZoneId string

@description('Resource id of the Log Analytics workspace that receives the audit logs of the vault.')
param workspaceId string

resource key_vault 'Microsoft.KeyVault/vaults@2026-05-15' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    // The vault is only reachable through the private endpoint.
    // Creating the secret below is a management operation (through Azure Resource Manager) and is not blocked.
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2026-05-15' = {
  name: 'ConnectionString'
  parent: key_vault
  properties: {
    value: 'Data Source=tcp:${sqlServerFQDN},1433;Initial Catalog=${databaseName};Persist Security Info=False;User Id=${sqlAdministratorLoginUser};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;'
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

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: key_vault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// Registers the private IP of the endpoint in the private DNS zone, so that the vault name resolves to it.
resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-03-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// Audit log: who read which secret, and which requests were refused.
#disable-next-line use-recent-api-versions
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: key_vault
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}
