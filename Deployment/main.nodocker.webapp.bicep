param location string = resourceGroup().location

param applicationname string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

param dateTime string = utcNow()

var keyVaultName = 'vault-${uniqueString(resourceGroup().id)}'

module sql 'sql.bicep' = {
  name: 'sql-${dateTime}'
  params: {
    location: location
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    applicationname: applicationname
  }
}

module appInsights 'applicationInsights.bicep' ={
  name: 'appInsights-${dateTime}'
  params: {
    location: location
    applicationname: applicationname
  }
}

module appService 'appService.bicep' = {
  name: 'appService-${dateTime}'
  params: {
    keyVaultName: keyVaultName
    location: location
    applicationname: applicationname
    applicationInsightsConnectionString: appInsights.outputs.connectionString
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault-${dateTime}'
  params: {
    keyVaultName: keyVaultName
    location: location
    appServicePrincipalId: appService.outputs.principalId
    sqlServerData: sql.outputs.sqlServerDatabase
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
  }
}

output webAppUrl string = appService.outputs.webAppUrl
output webAppName string = appService.outputs.webAppName
output sqlServerFQDN string = sql.outputs.sqlServerDatabase.fullyQualifiedDomainName
output databaseName string = sql.outputs.sqlServerDatabase.databaseName
