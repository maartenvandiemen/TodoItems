// Everything the application needs around it, in ONE resource group:
// one virtual network with a subnet per tier, a network security group per subnet, the private DNS zones for the
// private endpoints (linked to that one VNet) and the Log Analytics workspace that receives the logs.
// One VNet: no peering, no firewall, no user-defined routes, there is nothing to route between.
//
// Deploy into the resource group of the instance. Called by main.bicep.

param location string

param addressPrefix string = '10.0.0.0/16'

@description('Deploy an Azure Monitor private link scope (ampls.bicep): the telemetry of the application goes through a private endpoint, with five extra private DNS zones. Without it the workspace accepts public ingestion.')
param enableAmpls bool = true

// One subnet per tier, each with its own network security group.
// The Application Gateway v2 needs a subnet of its own; /24 is the recommended size so it can scale out.
var appGatewaySubnetPrefix = '10.0.1.0/24'
// App Service VNet integration (outbound traffic of the app): delegated to the App Service plan, /26 is recommended.
var appServiceSubnetPrefix = '10.0.2.0/26'
// The private endpoints of the web app, SQL and Key Vault.
var privateEndpointSubnetPrefix = '10.0.3.0/27'

// Private DNS zones of the services that get a private endpoint. The name of a zone is fixed by the service.
#disable-next-line no-hardcoded-env-urls
var webAppPrivateDnsZoneName = 'privatelink.azurewebsites.net'
// The ORDER matters: the outputs below use the zones by position (0 = SQL, 1 = Key Vault).
var dataPrivateDnsZoneNames = [
  'privatelink${environment().suffixes.sqlServerHostname}'
  'privatelink.vaultcore.azure.net'
]

// Central Log Analytics workspace: the application, the gateway, the NSGs, SQL and Key Vault send their logs here.
resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: 'log-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    retentionInDays: 30
    // With a private link scope (enableAmpls), data only gets in through its private endpoint.
    // Logs that Azure resources send through a diagnostic setting are not affected by this: they use a
    // private Microsoft channel.
    publicNetworkAccessForIngestion: enableAmpls ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

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
  name: 'nsg-appgateway'
  params: {
    location: location
    name: 'nsg-appgateway'
    workspaceId: workspace.id
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
  name: 'nsg-appservice'
  params: {
    location: location
    name: 'nsg-appservice'
    workspaceId: workspace.id
    securityRules: [
      denyAllInbound
    ]
  }
}

// Private endpoints (web app, SQL, Key Vault). Only the gateway may reach the web app, and only the app
// may reach SQL (1433) and Key Vault (443). These rules only apply because the subnet has
// privateEndpointNetworkPolicies enabled (see below).
module nsgPrivateEndpoints 'nsg.bicep' = {
  name: 'nsg-privateendpoints'
  params: {
    location: location
    name: 'nsg-privateendpoints'
    workspaceId: workspace.id
    securityRules: [
      {
        name: 'allow-gateway-to-webapp'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appGatewaySubnetPrefix
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
          sourceAddressPrefix: appServiceSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '443'
            '1433'
          ]
        }
      }
      denyAllInbound
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-app'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        // Dedicated subnet for the Application Gateway (v2 does not allow other resources in it).
        // No route table on purpose: the gateway needs a direct route to the internet.
        name: 'snet-appgateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: nsgAppGateway.outputs.id
          }
        }
      }
      {
        name: 'snet-appservice'
        properties: {
          addressPrefix: appServiceSubnetPrefix
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
          addressPrefix: privateEndpointSubnetPrefix
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

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: vnet
  name: 'snet-appgateway'
}

resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: vnet
  name: 'snet-appservice'
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' existing = {
  parent: vnet
  name: 'snet-privateendpoints'
}

// Private DNS zones: a private endpoint only works when the name of the service resolves to its private address.
// The zones are linked to the VNet, so everything in it (the web app's integration subnet, the gateway) resolves
// the names to the private endpoints. The zones must exist (and be linked) before the endpoints and the
// Application Gateway are created: the gateway caches DNS lookups of its backend.
resource webAppDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: webAppPrivateDnsZoneName
  location: 'global'
}

resource webAppDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: webAppDnsZone
  name: 'link-${vnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource dataDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in dataPrivateDnsZoneNames: {
  name: zoneName
  location: 'global'
}]

resource dataDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in dataPrivateDnsZoneNames: {
  parent: dataDnsZones[index]
  name: 'link-${vnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

// Azure Monitor private link scope (optional): see ampls.bicep. The web app's integration subnet may already reach
// the private endpoint: the rule 'allow-app-to-sql-and-keyvault' of the private endpoint subnet allows 443.
module ampls 'ampls.bicep' = if (enableAmpls) {
  name: 'ampls'
  params: {
    location: location
    workspaceName: workspace.name
    vnetName: vnet.name
    vnetId: vnet.id
    privateEndpointSubnetId: privateEndpointSubnet.id
  }
}

// Empty without AMPLS.
output monitorPrivateLinkScopeName string = ampls.?outputs.scopeName ?? ''
output logAnalyticsWorkspaceId string = workspace.id
output appGatewaySubnetId string = appGatewaySubnet.id
output appServiceSubnetId string = appServiceSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output webAppPrivateDnsZoneId string = webAppDnsZone.id
// In the order of dataPrivateDnsZoneNames: 0 = SQL, 1 = Key Vault.
output sqlPrivateDnsZoneId string = dataDnsZones[0].id
output keyVaultPrivateDnsZoneId string = dataDnsZones[1].id
