param location string = resourceGroup().location

param applicationname string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

param dateTime string = utcNow()

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

module appService 'appService/appService.nodocker.bicep' = {
  name: 'appService-${dateTime}'
  params: {
    location: location
    applicationname: applicationname
    applicationInsightsConnectionString: appInsights.outputs.connectionString
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault-${dateTime}'
  params: {
    location: location
    appServicePrincipalId: appService.outputs.principalId
    sqlServerData: sql.outputs.sqlServerDatabase
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
  }
}

output webAppName string = appService.outputs.webAppName
output sqlServerFQDN string = sql.outputs.sqlServerDatabase.fullyQualifiedDomainName
output databaseName string = sql.outputs.sqlServerDatabase.databaseName
