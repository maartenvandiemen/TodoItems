param location string

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

@secure ()
param sqlAdministratorLoginPassword string

param applicationname string

var sqlAdministratorLogin = 'AdminUser${stage}'
var sqlserverName = '${toLower(applicationname)}-sqlserver-${toLower(stage)}'

resource sqlServer 'Microsoft.Sql/servers@2021-11-01-preview' = {
   name: sqlserverName
   location: location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
  }
}

resource database 'Microsoft.Sql/servers/databases@2021-11-01-preview' = {
  name: '${sqlServer.name}/${applicationname}'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 524288000 //500MB
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
    isLedgerOn: false
  }
}

resource sqlserverName_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2014-04-01' = {
  name: '${sqlServer.name}/AllowAllWindowsAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

output sqlServerDatabase object = {
  fullyQualifiedDomainName : sqlServer.properties.fullyQualifiedDomainName
  databaseName: applicationname
  sqlAdministratorLogin: sqlAdministratorLogin
}
