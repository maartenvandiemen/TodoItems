// Azure Monitor Private Link Scope (AMPLS): makes the Log Analytics workspace and Application Insights reachable
// through a private endpoint in the VNet, so the telemetry of the application does not go over a public endpoint.
// Optional: network.bicep only deploys this with enableAmpls.
//
// One endpoint needs five private DNS zones: Azure Monitor uses several different domain names, and a private DNS
// zone only answers for the one domain it is named after. The zones are linked to the VNet.
// Application Insights is added to the scope by applicationInsights.bicep: everything that is connected to the scope
// lives in the same resource group, so it is deleted together with it. (A resource that is connected to a private
// link scope cannot be deleted on its own.)
// Deploy into the resource group of the instance.

param location string

param workspaceName string

param vnetName string

param vnetId string

@description('Subnet that holds private endpoints.')
param privateEndpointSubnetId string

// The domains that Azure Monitor uses.
var monitorPrivateDnsZoneNames = [
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
  'privatelink.blob.${environment().suffixes.storage}'
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: workspaceName
}

resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = {
  name: 'ampls-app'
  location: 'global'
  properties: {
    accessModeSettings: {
      // Telemetry only goes in through the private endpoint. Queries (the Azure portal) stay open.
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'Open'
    }
  }
}

resource workspaceScopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: monitorPrivateLinkScope
  name: '${workspace.name}-connection'
  properties: {
    linkedResourceId: workspace.id
  }
}

resource monitorDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in monitorPrivateDnsZoneNames: {
  name: zoneName
  location: 'global'
}]

resource monitorDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in monitorPrivateDnsZoneNames: {
  parent: monitorDnsZones[index]
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource monitorPrivateEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = {
  name: 'pe-${monitorPrivateLinkScope.name}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'monitor'
        properties: {
          privateLinkServiceId: monitorPrivateLinkScope.id
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
  // The endpoint registers DNS records for the resources that are in the scope: add the workspace first.
  dependsOn: [
    workspaceScopedResource
  ]
}

// Registers the private IP addresses of the endpoint in the five zones of Azure Monitor.
resource monitorDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-03-01' = {
  parent: monitorPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneName, index) in monitorPrivateDnsZoneNames: {
      name: replace(zoneName, '.', '-')
      properties: {
        privateDnsZoneId: monitorDnsZones[index].id
      }
    }]
  }
}

output scopeName string = monitorPrivateLinkScope.name
