// Virtual network flow logs: a record of the IP traffic that flows through a VNet (which source, destination, port,
// and whether an NSG rule allowed or denied it). Written to a storage account by Network Watcher.
//
// IMPORTANT: a flow log is a child of the Network Watcher of the region, and that one lives in the resource group
// NetworkWatcherRG of the SUBSCRIPTION, shared by everything in the region. So the flow logs of an instance are NOT
// in the resource groups of the instance and are not deleted with them: the cleanup of the pipelines deletes them
// by name (fl-<prefix>-...).
//
// Deploy into the resource group of the Network Watcher (NetworkWatcherRG), after all VNets exist.
// The Network Watcher is created by Azure automatically for a region, the first time a VNet is created in it.

param location string

@description('Unique name of the instance. Used in the names of the flow logs so the pipeline can find them.')
param resourceGroupPrefix string

@description('Name of the Network Watcher of the region. Azure names it NetworkWatcher_<region>.')
param networkWatcherName string = 'NetworkWatcher_${location}'

@description('Resource id of the storage account (same region as the VNets) that receives the flow logs.')
param storageId string

param hubVnetId string

@description('The VNets of the spokes: [{ name: string, vnetId: string }].')
param spokeVnets array

var targets = concat([
  {
    name: 'hub'
    vnetId: hubVnetId
  }
], spokeVnets)

resource networkWatcher 'Microsoft.Network/networkWatchers@2026-03-01' existing = {
  name: networkWatcherName
}

// One at a time: several changes on the same Network Watcher in parallel can conflict.
@batchSize(1)
resource flowLogs 'Microsoft.Network/networkWatchers/flowLogs@2026-03-01' = [for target in targets: {
  parent: networkWatcher
  name: 'fl-${resourceGroupPrefix}-${target.name}'
  location: location
  properties: {
    targetResourceId: target.vnetId
    storageId: storageId
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      days: 7
      enabled: true
    }
  }
}]
