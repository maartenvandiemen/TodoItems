// Hub: shared network + Azure Firewall that routes traffic between the spokes.
// Deploy into the hub resource group. The spokes are deployed afterwards (spoke.bicep, one resource group per spoke).
import { hub, spokes, webAppPrivateDnsZoneName, monitorPrivateDnsZoneNames } from 'addressPlan.bicep'

param location string = resourceGroup().location

@description('Who may query the Log Analytics workspace: Open also allows queries from public networks (the Azure portal, authenticated), PrivateOnly only from the connected private networks. Ingestion is always private only.')
@allowed([
  'Open'
  'PrivateOnly'
])
param monitorQueryAccessMode string = 'Open'

var spokePrefixes = map(spokes, spoke => spoke.addressPrefix)

resource hubVnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-${hub.name}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hub.addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-shared-services'
        properties: {
          addressPrefix: hub.sharedServicesSubnetPrefix
          defaultOutboundAccess: false
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hub.firewallSubnetPrefix
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefix: hub.privateEndpointSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: hubVnet
  name: 'snet-privateendpoints'
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: hubVnet
  name: 'AzureFirewallSubnet'
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2026-03-01' = {
  name: 'pip-fw-${hub.name}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2026-03-01' = {
  name: 'fwp-${hub.name}'
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
  }
}

resource spokeToSpokeRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2026-03-01' = {
  parent: firewallPolicy
  name: 'rcg-spoke-to-spoke'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'spoke-to-spoke'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'allow-spoke-traffic'
            ipProtocols: [
              'Any'
            ]
            sourceAddresses: spokePrefixes
            destinationAddresses: spokePrefixes
            destinationPorts: [
              '*'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2026-03-01' = {
  name: 'fw-${hub.name}'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-config'
        properties: {
          publicIPAddress: {
            id: firewallPublicIp.id
          }
          subnet: {
            id: firewallSubnet.id
          }
        }
      }
    ]
  }
  // Create the rules before the policy is attached to the firewall.
  // Changing a policy while it is attached can fail with 'update in progress' errors.
  dependsOn: [
    spokeToSpokeRules
  ]
}

// Private DNS zone for private endpoints of App Service, shared by the whole instance.
// Each VNet that has to resolve the private endpoint needs a link to it: this one links the hub,
// the spokes get their link in hubSideOfSpoke.bicep. The zone must exist (and be linked) before the
// Application Gateway is created: the gateway caches DNS lookups of its backend.
resource webAppDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: webAppPrivateDnsZoneName
  location: 'global'
}

resource webAppDnsZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: webAppDnsZone
  name: 'link-${hubVnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

// Central Log Analytics workspace of the instance. Everything that writes logs or telemetry (the application,
// later also the firewall, gateway and network flow logs) sends it here, so it can be queried and
// correlated in one place. It lives in the hub because the hub outlives the spokes within an instance:
// the spokes are deleted first.
resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: 'log-${hub.name}'
  location: location
  properties: {
    retentionInDays: 30
    // Data only gets in through the private endpoint of the private link scope below.
    // Logs that Azure resources send through a diagnostic setting are not affected by this: they use a
    // private Microsoft channel.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: monitorQueryAccessMode == 'Open' ? 'Enabled' : 'Disabled'
  }
}

// Azure Monitor Private Link Scope (AMPLS): makes the workspace (and Application Insights) reachable through a
// private endpoint. A hub-and-spoke network uses ONE scope with ONE private endpoint in the hub, not one per
// spoke: a second endpoint for the same zones would override the DNS records of the first.
// Application Insights is added to the scope by applicationInsights.bicep, which is deployed into this
// resource group too: everything that is connected to the scope is deleted together with the resource group.
resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = {
  name: 'ampls-${hub.name}'
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: monitorQueryAccessMode
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

resource monitorDnsZoneHubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in monitorPrivateDnsZoneNames: {
  parent: monitorDnsZones[index]
  name: 'link-${hubVnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}]

resource monitorPrivateEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = {
  name: 'pe-${monitorPrivateLinkScope.name}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
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

output monitorPrivateLinkScopeName string = monitorPrivateLinkScope.name
output hubVnetName string = hubVnet.name
output logAnalyticsWorkspaceId string = workspace.id
output hubVnetId string = hubVnet.id
output webAppPrivateDnsZoneId string = webAppDnsZone.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
