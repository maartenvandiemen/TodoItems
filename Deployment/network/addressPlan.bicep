// Single source of truth for the IP plan. The orchestrator (main.bicep) and hub.bicep import from here,
// so the firewall rule (hub) and the spoke networks can never drift apart.
//
// Every instance (hub + spokes) deploys into its own resource groups and is never peered with
// another instance, so each instance can safely reuse the same address ranges.

@export()
type Spoke = {
  @description('Short name. Used to derive resource names, for example vnet-spoke-1.')
  name: string

  @description('Address space of the spoke virtual network.')
  addressPrefix: string

  @description('Prefix of the workload subnet. Must be inside addressPrefix.')
  workloadSubnetPrefix: string

  @description('Prefix of the subnet for App Service VNet integration. Gets delegated to Microsoft.Web/serverFarms. /26 is the recommended size.')
  appServiceSubnetPrefix: string

  @description('Prefix of the subnet that holds private endpoints.')
  privateEndpointSubnetPrefix: string

  @description('Prefix of the subnet for the Application Gateway. v2 needs a subnet of its own; /24 is the recommended size so the gateway can scale out.')
  appGatewaySubnetPrefix: string
}

@export()
var hub = {
  name: 'hub'
  addressPrefix: '10.0.0.0/16'
  sharedServicesSubnetPrefix: '10.0.1.0/24'
  // Azure Firewall requires a subnet named AzureFirewallSubnet of at least /26.
  firewallSubnetPrefix: '10.0.2.0/26'
  // Private endpoints of the hub (for now: the Azure Monitor private link scope, which needs at least
  // 11 free addresses, /27 is the smallest supported size).
  privateEndpointSubnetPrefix: '10.0.3.0/27'
}

// Private DNS zone for private endpoints of App Service. It lives in the hub and is linked to every
// VNet that has to resolve the private endpoint: the hub itself and each spoke.
@export()
#disable-next-line no-hardcoded-env-urls
var webAppPrivateDnsZoneName = 'privatelink.azurewebsites.net'

// Private DNS zones of the Azure Monitor private link (AMPLS). Same rule as the zone above: they live in
// the hub and are linked to the hub itself and to each spoke.
@export()
var monitorPrivateDnsZoneNames = [
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
  'privatelink.blob.${environment().suffixes.storage}'
]

// Private DNS zones of the data services. Same rule: in the hub, linked to the hub and each spoke.
// The ORDER matters: hub.bicep outputs the zone ids by position (0 = SQL, 1 = Key Vault).
@export()
var dataPrivateDnsZoneNames = [
  'privatelink${environment().suffixes.sqlServerHostname}'
  'privatelink.vaultcore.azure.net'
]

// The web app is deployed into the FIRST spoke (spokes[0]).
@export()
var spokes Spoke[] = [
  {
    name: 'spoke-1'
    addressPrefix: '10.1.0.0/16'
    workloadSubnetPrefix: '10.1.1.0/24'
    appServiceSubnetPrefix: '10.1.2.0/26'
    privateEndpointSubnetPrefix: '10.1.3.0/27'
    appGatewaySubnetPrefix: '10.1.4.0/24'
  }
  // Second spoke is for demo purposes
  {
    name: 'spoke-2'
    addressPrefix: '10.2.0.0/16'
    workloadSubnetPrefix: '10.2.1.0/24'
    appServiceSubnetPrefix: '10.2.2.0/26'
    privateEndpointSubnetPrefix: '10.2.3.0/27'
    appGatewaySubnetPrefix: '10.2.4.0/24'
  }
]
