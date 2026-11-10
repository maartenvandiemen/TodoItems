// Adds an Azure Monitor resource (here: the Application Insights component of the web app) to the Azure Monitor
// Private Link Scope of the hub. Only resources in the scope can be reached through the private endpoint.
// Deploy into the hub resource group, after the resource exists.

param monitorPrivateLinkScopeName string

@description('Name of the connection, unique within the scope.')
param name string

@description('Resource id of the Azure Monitor resource (workspace or Application Insights component).')
param linkedResourceId string

resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' existing = {
  name: monitorPrivateLinkScopeName
}

resource scopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: monitorPrivateLinkScope
  name: name
  properties: {
    linkedResourceId: linkedResourceId
  }
}
