// One spoke: virtual network, a workload subnet and a route table that sends all traffic
// destined for the other spokes to the hub firewall. Also creates the spoke -> hub peering.
// The hub -> spoke peering and the DNS zone link are created by hubSideOfSpoke.bicep (they live in the hub resource group).
import { Spoke } from 'addressPlan.bicep'

param location string

param spoke Spoke

@description('All other spokes. Traffic to these ranges is sent to the firewall.')
param otherSpokes Spoke[]

param hubVnetId string

@description('Private IP address of the hub firewall. Next hop for traffic between spokes.')
param firewallPrivateIp string

resource routeTable 'Microsoft.Network/routeTables@2026-03-01' = {
  name: 'rt-${spoke.name}'
  location: location
  properties: {
    routes: [for other in otherSpokes: {
      name: 'to-${other.name}'
      properties: {
        addressPrefix: other.addressPrefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    }]
  }
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-${spoke.name}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke.addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: spoke.workloadSubnetPrefix
          routeTable: {
            id: routeTable.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-appservice'
        properties: {
          addressPrefix: spoke.appServiceSubnetPrefix
          // A subnet used for App Service VNet integration must be delegated to the App Service plan.
          delegations: [
            {
              name: 'web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefix: spoke.privateEndpointSubnetPrefix
          defaultOutboundAccess: false
        }
      }
      {
        // Dedicated subnet for the Application Gateway (v2 does not allow other resources in it).
        // No route table on purpose: the gateway needs a direct route to the internet.
        name: 'snet-appgateway'
        properties: {
          addressPrefix: spoke.appGatewaySubnetPrefix
        }
      }
    ]
  }
}

resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: spokeVnet
  name: 'snet-appservice'
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: spokeVnet
  name: 'snet-privateendpoints'
}

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: spokeVnet
  name: 'snet-appgateway'
}

resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
  parent: spokeVnet
  name: '${spoke.name}-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    // Accept traffic that was forwarded by the hub firewall (originates from another spoke).
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output vnetId string = spokeVnet.id
output appServiceSubnetId string = appServiceSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output appGatewaySubnetId string = appGatewaySubnet.id
