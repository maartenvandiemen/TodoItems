param location string

param sqlAdministratorLoginUser string

@secure ()
param sqlAdministratorLoginPassword string

param applicationname string

@description('Optional. Subnet for the private endpoint of the SQL server. Empty: no private endpoint, the server stays publicly reachable.')
param privateEndpointSubnetId string = ''

@description('Resource id of the private DNS zone for SQL (privatelink.database.windows.net). Required when privateEndpointSubnetId is set.')
param privateDnsZoneId string = ''

@description('Resource id of the Log Analytics workspace that receives the diagnostic logs of the database.')
param workspaceId string

var usePrivateEndpoint = !empty(privateEndpointSubnetId)

var sqlserverName = 'sqlserver-${toLower(applicationname)}-${uniqueString(resourceGroup().id)}'

resource sqlServer 'Microsoft.Sql/servers@2025-01-01' = {
   name: sqlserverName
   location: location
  properties: {
    administratorLogin: sqlAdministratorLoginUser
    administratorLoginPassword: sqlAdministratorLoginPassword
    // With a private endpoint the server has no public endpoint at all: it can only be reached through the endpoint.
    // (A pipeline that has to reach it from outside, for the database migration, switches this on temporarily.)
    publicNetworkAccess: usePrivateEndpoint ? 'Disabled' : 'Enabled'
  }
}

resource database 'Microsoft.Sql/servers/databases@2025-01-01' = {
  name: applicationname
  parent: sqlServer
  location: location
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824 //1GB
    autoPauseDelay: 60
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
    isLedgerOn: false
  }
}

// Lets every Azure service (from any customer) connect. Only without a private endpoint: with one, nothing but the
// private endpoint is needed.
resource sqlserverName_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2025-01-01' = if (!usePrivateEndpoint) {
  name: 'AllowAllWindowsAzureIPs'
  parent: sqlServer
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = if (usePrivateEndpoint) {
  name: 'pe-${sqlserverName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sql'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// Registers the private IP of the endpoint in the private DNS zone, so that the server name resolves to it.
resource sqlDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-03-01' = if (usePrivateEndpoint) {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

#disable-next-line use-recent-api-versions
resource databaseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: database
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'Errors'
        enabled: true
      }
      {
        category: 'Timeouts'
        enabled: true
      }
      {
        category: 'Blocks'
        enabled: true
      }
      {
        category: 'Deadlocks'
        enabled: true
      }
    ]
  }
}

output sqlServerDatabase object = {
  fullyQualifiedDomainName : sqlServer.properties.fullyQualifiedDomainName
  databaseName: applicationname
}
