// One spoke: virtual network, its subnets with a network security group each, and a route table that sends all
// traffic destined for the other spokes to the hub firewall. Also creates the spoke -> hub peering.
// The hub -> spoke peering and the DNS zone links are created by hubSideOfSpoke.bicep (they live in the hub resource group).
import { Spoke } from 'addressPlan.bicep'

param location string

param spoke Spoke

@description('All other spokes. Traffic to these ranges is sent to the firewall.')
param otherSpokes Spoke[]

param hubVnetId string

@description('Private IP address of the hub firewall. Next hop for traffic between spokes.')
param firewallPrivateIp string

@description('Resource id of the central Log Analytics workspace (in the hub). The NSG logs are sent there.')
param workspaceId string

@description('Workload subnets of the spokes that host the build agent. They may reach the private endpoints of this spoke (HTTPS and SQL).')
param buildAgentSubnetPrefixes string[] = []

// This spoke hosts the build agent: its workload subnet reaches the internet through the firewall.
var sendInternetThroughFirewall = spoke.?hostsBuildAgent ?? false

// Closes the subnet for everything that is not allowed by a rule with a lower number.
// Without it the default rule AllowVnetInBound (priority 65000) lets every resource in the VNet in.
var denyAllInbound = {
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

// Application Gateway subnet. Application Gateway v2 REQUIRES these inbound rules: the GatewayManager ports for
// its own management, and the load balancer probes. The deny rule has a lower number than the default rule
// that allows the load balancer (65001), so the load balancer has to be allowed explicitly.
module nsgAppGateway 'nsg.bicep' = {
  name: 'nsg-${spoke.name}-appgateway'
  params: {
    location: location
    name: 'nsg-${spoke.name}-appgateway'
    workspaceId: workspaceId
    securityRules: [
      {
        name: 'allow-web-from-internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'allow-gateway-manager'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
      {
        name: 'allow-load-balancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      denyAllInbound
    ]
  }
}

// App Service VNet integration subnet: only used for OUTBOUND traffic of the app, nothing has to come in.
module nsgAppService 'nsg.bicep' = {
  name: 'nsg-${spoke.name}-appservice'
  params: {
    location: location
    name: 'nsg-${spoke.name}-appservice'
    workspaceId: workspaceId
    securityRules: [
      denyAllInbound
    ]
  }
}

// Private endpoints (web app, SQL, Key Vault). Only the gateway may reach the web app, and only the app
// may reach SQL (1433) and Key Vault (443). These rules only apply because the subnet has
// privateEndpointNetworkPolicies enabled (see below).
module nsgPrivateEndpoints 'nsg.bicep' = {
  name: 'nsg-${spoke.name}-privateendpoints'
  params: {
    location: location
    name: 'nsg-${spoke.name}-privateendpoints'
    workspaceId: workspaceId
    securityRules: concat([
      {
        name: 'allow-gateway-to-webapp'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: spoke.appGatewaySubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-app-to-sql-and-keyvault'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: spoke.appServiceSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '443'
            '1433'
          ]
        }
      }
    ], empty(buildAgentSubnetPrefixes) ? [] : [
      {
        // The build agent deploys the application and the database: web app (also its SCM site), SQL and Key Vault.
        // Its traffic arrives through the firewall with the address of the agent (the firewall does not translate
        // the address of traffic between private networks).
        name: 'allow-build-agent'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: buildAgentSubnetPrefixes
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '443'
            '1433'
          ]
        }
      }
    ], [
      denyAllInbound
    ])
  }
}

// Workload subnet (lab VMs, clients). No custom rules yet: the default rules apply, and the NSG logs.
module nsgWorkload 'nsg.bicep' = {
  name: 'nsg-${spoke.name}-workload'
  params: {
    location: location
    name: 'nsg-${spoke.name}-workload'
    workspaceId: workspaceId
  }
}

var routesToOtherSpokes = [for other in otherSpokes: {
  name: 'to-${other.name}'
  properties: {
    addressPrefix: other.addressPrefix
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: firewallPrivateIp
  }
}]

// The more specific routes win: traffic to the hub and within this VNet (system routes) does not follow the
// default route, only what is left (the internet) does.
var routeToInternet = [
  {
    name: 'to-internet'
    properties: {
      addressPrefix: '0.0.0.0/0'
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: firewallPrivateIp
    }
  }
]

// Used by the workload subnet and by the private endpoint subnet. The second one needs it for the REPLIES: traffic
// that arrives from another spoke through the firewall must go back through the firewall. This works because
// privateEndpointNetworkPolicies is enabled on that subnet.
resource routeTable 'Microsoft.Network/routeTables@2026-03-01' = {
  name: 'rt-${spoke.name}'
  location: location
  properties: {
    routes: concat(routesToOtherSpokes, sendInternetThroughFirewall ? routeToInternet : [])
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
          networkSecurityGroup: {
            id: nsgWorkload.outputs.id
          }
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
          networkSecurityGroup: {
            id: nsgAppService.outputs.id
          }
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefix: spoke.privateEndpointSubnetPrefix
          defaultOutboundAccess: false
          // Without this the NSG rules are not applied to private endpoints in this subnet.
          privateEndpointNetworkPolicies: 'Enabled'
          routeTable: {
            id: routeTable.id
          }
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.outputs.id
          }
        }
      }
      {
        // Dedicated subnet for the Application Gateway (v2 does not allow other resources in it).
        // No route table on purpose: the gateway needs a direct route to the internet.
        name: 'snet-appgateway'
        properties: {
          addressPrefix: spoke.appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: nsgAppGateway.outputs.id
          }
        }
      }
    ]
  }
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: spokeVnet
  name: 'snet-workload'
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
output workloadSubnetId string = workloadSubnet.id
output appServiceSubnetId string = appServiceSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output appGatewaySubnetId string = appGatewaySubnet.id
