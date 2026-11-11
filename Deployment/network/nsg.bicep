// A network security group (NSG) for one subnet, with its logs sent to the central Log Analytics workspace.
// An NSG filters the traffic that enters and leaves the subnet. Rules are evaluated by priority, lowest number first.
// The default rules (priority 65000 and up) allow all traffic inside the VNet: a rule 'deny-all-inbound' with a
// lower number than that closes the subnet, so every wanted flow has to be allowed explicitly before it.

param location string

param name string

@description('Custom rules. Each item: { name: string, properties: { priority, direction, access, protocol, ... } }.')
param securityRules array = []

@description('Resource id of the Log Analytics workspace that receives the NSG logs.')
param workspaceId string

resource nsg 'Microsoft.Network/networkSecurityGroups@2026-03-01' = {
  name: name
  location: location
  properties: {
    securityRules: securityRules
  }
}

// The only stable API version of diagnostic settings (2016-09-01) is too old for the linter's age limit, and
// has no logAnalyticsDestinationType. The newest preview is the one that is used everywhere.
#disable-next-line use-recent-api-versions
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: nsg
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'NetworkSecurityGroupEvent'
        enabled: true
      }
      {
        category: 'NetworkSecurityGroupRuleCounter'
        enabled: true
      }
    ]
  }
}

output id string = nsg.id
