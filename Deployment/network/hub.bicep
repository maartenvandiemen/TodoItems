// Hub: shared network + Azure Firewall that routes traffic between the spokes.
// Deploy into the hub resource group. The spokes are deployed afterwards (spoke.bicep, one resource group per spoke).
import { hub, spokes, webAppPrivateDnsZoneName, monitorPrivateDnsZoneNames, dataPrivateDnsZoneNames } from 'addressPlan.bicep'

param location string = resourceGroup().location

var spokePrefixes = map(spokes, spoke => spoke.addressPrefix)

// Network security groups of the hub subnets. The firewall subnet gets none: Azure Firewall manages its own subnet.
module nsgSharedServices 'nsg.bicep' = {
  name: 'nsg-${hub.name}-shared-services'
  params: {
    location: location
    name: 'nsg-${hub.name}-shared-services'
    workspaceId: workspace.id
  }
}

module nsgPrivateEndpoints 'nsg.bicep' = {
  name: 'nsg-${hub.name}-privateendpoints'
  params: {
    location: location
    name: 'nsg-${hub.name}-privateendpoints'
    workspaceId: workspace.id
    securityRules: [
      {
        // The Azure Monitor private link scope: the spokes (and the hub) send their telemetry to it over HTTPS.
        name: 'allow-https-from-vnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

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
          networkSecurityGroup: {
            id: nsgSharedServices.outputs.id
          }
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
          // Without this the NSG rules are not applied to private endpoints in this subnet.
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.outputs.id
          }
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
    threatIntelMode: 'Off'
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

// Firewall logs to the central workspace. The AZFW* categories are the structured logs: they need
// 'Dedicated' (resource specific tables).
#disable-next-line use-recent-api-versions
resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: firewall
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'AZFWNetworkRule'
        enabled: true
      }
      {
        category: 'AZFWApplicationRule'
        enabled: true
      }
      {
        category: 'AZFWNatRule'
        enabled: true
      }
      {
        category: 'AZFWThreatIntel'
        enabled: true
      }
    ]
  }
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

// The same for the data services (SQL, Key Vault).
resource dataDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in dataPrivateDnsZoneNames: {
  name: zoneName
  location: 'global'
}]

resource dataDnsZoneHubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in dataPrivateDnsZoneNames: {
  parent: dataDnsZones[index]
  name: 'link-${hubVnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}]

// Central Log Analytics workspace of the instance. Everything that writes logs or telemetry (the application,
// the firewall, the gateway, the NSGs, SQL and Key Vault) sends it here, so it can be queried and
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
    publicNetworkAccessForQuery: 'Enabled'
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

// Storage account for the virtual network flow logs (network/flowLogs.bicep). Flow logs are written here by
// Network Watcher: a standard storage account in the same region as the VNets.
resource flowLogStorage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: 'stflow${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

output monitorPrivateLinkScopeName string = monitorPrivateLinkScope.name
output hubVnetName string = hubVnet.name
output logAnalyticsWorkspaceId string = workspace.id
output flowLogStorageId string = flowLogStorage.id
output hubVnetId string = hubVnet.id
output webAppPrivateDnsZoneId string = webAppDnsZone.id
// In the order of dataPrivateDnsZoneNames (addressPlan.bicep).
output sqlPrivateDnsZoneId string = dataDnsZones[0].id
output keyVaultPrivateDnsZoneId string = dataDnsZones[1].id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
