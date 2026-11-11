// The web application and everything it needs: sql, key vault, the web app itself and (optionally) an
// Application Gateway in front of it. Application Insights is deployed by main.bicep.
// Deploy into the resource group of the instance. Called by main.bicep.
//
// dockerImageNameAndTag empty: the web app runs the .NET runtime stack and the pipeline deploys a zip.
// dockerImageNameAndTag set:   the web app runs that container image.

param location string

param applicationname string

param sqlAdministratorLoginUser string

@secure()
param sqlAdministratorLoginPassword string

@description('Full docker image name, including tag. Example: ghcr.io/mvdiemen/todoitems:docker. Empty: no container, the pipeline deploys a zip.')
param dockerImageNameAndTag string = ''

@description('Connection string of the Application Insights component of this instance.')
param applicationInsightsConnectionString string

@description('Resource id of the Log Analytics workspace of this instance. The diagnostic logs of the resources are sent there.')
param logAnalyticsWorkspaceId string

@description('Optional. Private DNS zone for SQL (privatelink.database.windows.net). Required with privateEndpointSubnetId.')
param sqlPrivateDnsZoneId string = ''

@description('Optional. Private DNS zone for Key Vault (privatelink.vaultcore.azure.net). Required with privateEndpointSubnetId.')
param keyVaultPrivateDnsZoneId string = ''

@description('Optional. Subnet for VNet integration of the web app (outbound).')
param integrationSubnetId string = ''

@description('Optional. Subnet for the private endpoint of the web app (inbound). Makes the web app private.')
param privateEndpointSubnetId string = ''

@description('Optional. Private DNS zone privatelink.azurewebsites.net. Required with privateEndpointSubnetId.')
param privateDnsZoneId string = ''

@description('Optional. Dedicated subnet for an Application Gateway in front of the web app. Empty: no gateway.')
param appGatewaySubnetId string = ''

var keyVaultName = 'vault-${uniqueString(resourceGroup().id)}'

module sql 'sql.bicep' = {
  name: 'sql'
  params: {
    location: location
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    applicationname: applicationname
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: sqlPrivateDnsZoneId
    workspaceId: logAnalyticsWorkspaceId
  }
}

module appService 'appService.bicep' = {
  name: 'appService'
  params: {
    keyVaultName: keyVaultName
    location: location
    applicationname: applicationname
    applicationInsightsConnectionString: applicationInsightsConnectionString
    dockerImageNameAndTag: dockerImageNameAndTag
    integrationSubnetId: integrationSubnetId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: privateDnsZoneId
    workspaceId: logAnalyticsWorkspaceId
  }
}

// Uses the hostname output of the appService module. A module output is only available after the whole
// module has been deployed, including the private endpoint and its DNS registration. Exactly what the
// gateway needs: it caches the DNS lookup of its backend.
module appGateway 'appGateway.bicep' = if (!empty(appGatewaySubnetId)) {
  name: 'appGateway'
  params: {
    location: location
    applicationname: applicationname
    subnetId: appGatewaySubnetId
    backendHostName: appService.outputs.webAppHostName
    workspaceId: logAnalyticsWorkspaceId
  }
}

module keyVault 'keyVault.bicep' = {
  name: 'keyVault'
  params: {
    keyVaultName: keyVaultName
    location: location
    appServicePrincipalId: appService.outputs.principalId
    sqlServerData: sql.outputs.sqlServerDatabase
    sqlAdministratorLoginUser: sqlAdministratorLoginUser
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: keyVaultPrivateDnsZoneId
    workspaceId: logAnalyticsWorkspaceId
  }
}

output webAppUrl string = appService.outputs.webAppUrl
output webAppName string = appService.outputs.webAppName
output gatewayUrl string = appGateway.?outputs.gatewayUrl ?? ''
output sqlServerFQDN string = sql.outputs.sqlServerDatabase.fullyQualifiedDomainName
output databaseName string = sql.outputs.sqlServerDatabase.databaseName
