param location string = resourceGroup().location

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

param applicationname string

param dockerRepositoryAndVersion string

@secure()
param sqlAdministratorLoginPassword string

param currentTime string = utcNow()

module acr 'containerRegistry.bicep' = {
  name:'acr'
}

module sql 'sql.bicep' = {
  name: 'sql-${uniqueString(currentTime)}'
  params: {
    location: location
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    stage: stage
    applicationname: applicationname
  }
}

module appInsights 'applicationInsights.bicep' ={
  name: 'appInsights-${uniqueString(currentTime)}'
  params: {
    location: location
    applicationname: applicationname
    stage: stage
  }
}

module appService 'appService/appService.docker.bicep' = {
  name: 'appService-${uniqueString(currentTime)}'
  params: {
    location: location
    stage: stage
    applicationname: applicationname
    sqlServerData: sql.outputs.sqlServerDatabase
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    applicationInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    acrLoginServer: acr.outputs.loginServer
    dockerRepositoryAndVersion: dockerRepositoryAndVersion
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault-${uniqueString(currentTime)}'
  params: {
    location: location
    stage: stage
    appServicePrincipalId: appService.outputs.principalId
    applicationname: applicationname
  }
}
