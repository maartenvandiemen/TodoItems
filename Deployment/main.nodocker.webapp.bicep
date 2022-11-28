param location string = resourceGroup().location

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

param applicationname string

@secure()
param sqlAdministratorLoginPassword string

var utc string = utcNow()

module sql 'sql.bicep' = {
  name: 'sql-${uniqueString(utc)}'
  params: {
    location: location
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    stage: stage
    applicationname: applicationname
  }
}

module appInsights 'applicationInsights.bicep' ={
  name: 'appInsights-${uniqueString(utc)}'
  params: {
    location: location
    applicationname: applicationname
    stage: stage
  }
}

module appService 'appService/appService.nodocker.bicep' = {
  name: 'appService-${uniqueString(utc)}'
  params: {
    location: location
    stage: stage
    applicationname: applicationname
    sqlServerData: sql.outputs.sqlServerDatabase
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    applicationInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault-${uniqueString(utc)}'
  params: {
    location: location
    stage: stage
    appServicePrincipalId: appService.outputs.principalId
    applicationname: applicationname
  }
}
