// Everything that has to be created in the hub resource group when a spoke is added:
//  - the hub side of the peering. Peering is two one-directional resources: this one lives in the hub VNet,
//    the other one in the spoke VNet.
//  - a link between the private DNS zone of the hub and the spoke VNet, so that resources in the spoke
//    (such as the Application Gateway) resolve private endpoints to their private IP.
// Deploy into the hub resource group.
import { webAppPrivateDnsZoneName } from 'addressPlan.bicep'

param hubVnetName string

param spokeName string

param spokeVnetId string

resource hubVnet 'Microsoft.Network/virtualNetworks@2026-03-01' existing = {
  name: hubVnetName
}

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
  parent: hubVnet
  name: 'hub-to-${spokeName}'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    // The firewall in the hub forwards traffic between spokes.
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource webAppDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: webAppPrivateDnsZoneName
}

resource webAppDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: webAppDnsZone
  name: 'link-${spokeName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnetId
    }
  }
}
