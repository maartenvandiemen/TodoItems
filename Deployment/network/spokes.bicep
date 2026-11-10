// All spokes. Deploy into the spokes resource group, after the hub (hub.bicep) has been deployed.
// Peering needs both sides, so this template also writes the hub -> spoke peerings
// into the hub resource group (cross resource group deployment).
import { hub, spokes } from 'addressPlan.bicep'

param location string = resourceGroup().location

@description('Resource group that contains the hub, created by hub.bicep.')
param hubResourceGroupName string

@description('Output firewallPrivateIp of hub.bicep.')
param firewallPrivateIp string

resource hubVnet 'Microsoft.Network/virtualNetworks@2026-03-01' existing = {
  name: 'vnet-${hub.name}'
  scope: resourceGroup(hubResourceGroupName)
}

// Peerings are created one at a time (batchSize 1). Creating several peerings against the same
// virtual network in parallel can fail with 'AnotherOperationInProgress'.
@batchSize(1)
module spokeNetworks 'spoke.bicep' = [for spoke in spokes: {
  name: 'spoke-${spoke.name}'
  params: {
    location: location
    spoke: spoke
    otherSpokes: filter(spokes, other => other.name != spoke.name)
    hubVnetId: hubVnet.id
    firewallPrivateIp: firewallPrivateIp
  }
}]

@batchSize(1)
module hubSides 'hubSideOfSpoke.bicep' = [for (spoke, index) in spokes: {
  name: 'hubside-${spoke.name}'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    hubVnetName: hubVnet.name
    spokeName: spoke.name
    spokeVnetId: spokeNetworks[index].outputs.vnetId
  }
}]

// The web app lives in the first spoke.
output appServiceSubnetId string = spokeNetworks[0].outputs.appServiceSubnetId
output privateEndpointSubnetId string = spokeNetworks[0].outputs.privateEndpointSubnetId
output appGatewaySubnetId string = spokeNetworks[0].outputs.appGatewaySubnetId
