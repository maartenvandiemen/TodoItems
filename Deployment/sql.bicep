param location string

param sqlAdministratorLoginUser string

@secure ()
param sqlAdministratorLoginPassword string

param applicationname string

var sqlserverName = 'sqlserver-${toLower(applicationname)}-${uniqueString(resourceGroup().id)}'

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
   name: sqlserverName
   location: location
  properties: {
    administratorLogin: sqlAdministratorLoginUser
    administratorLoginPassword: sqlAdministratorLoginPassword
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
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

resource sqlserverName_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  name: 'AllowAllWindowsAzureIPs'
  parent: sqlServer
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

output sqlServerDatabase object = {
  fullyQualifiedDomainName : sqlServer.properties.fullyQualifiedDomainName
  databaseName: applicationname
}
