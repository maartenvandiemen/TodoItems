// Hub: shared network + Azure Firewall that routes traffic between the spokes.
// Deploy into the hub resource group. The spokes are deployed afterwards by spokes.bicep.
import { hub, spokes, webAppPrivateDnsZoneName } from 'addressPlan.bicep'

param location string = resourceGroup().location

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
    ]
  }
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

output hubVnetName string = hubVnet.name
output webAppPrivateDnsZoneId string = webAppDnsZone.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
