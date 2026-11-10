// Application Gateway (layer 7 load balancer): the public entry point of the web app.
//
//   Internet -> public IP -> Application Gateway (own subnet in the spoke) -> backend (App Service)
//
// It is deployed together with the web app (webApp.bicep), so it can use the hostname of the web
// app directly. It is created after the private endpoint of the web app, because the module that creates
// that endpoint has to finish before its outputs (the hostname) are available. That matters: the gateway
// caches the DNS lookup of its backend, so it must not resolve the hostname before the private endpoint
// has registered itself in the private DNS zone.
//
// The backend is reached over HTTPS by hostname. That works for both cases:
//  - public App Service: the hostname resolves to a public IP.
//  - App Service with a private endpoint: the hostname resolves to the private endpoint, as long as the
//    privatelink.azurewebsites.net private DNS zone is linked to the VNet of the gateway.

param location string

param applicationname string

@description('Subnet of the gateway. Must be a subnet that only contains the gateway.')
param subnetId string

@description('Default hostname of the web app, for example site-todoitems-abc123.azurewebsites.net.')
param backendHostName string

@description('Path of the health endpoint of the web app.')
param healthProbePath string = '/health'

var gatewayName = 'agw-${applicationname}'
var publicIpName = 'pip-agw-${applicationname}'

// Names of the sub objects. Application Gateway references its own parts by resource id.
var gatewayIpConfigName = 'gateway-ip'
var frontendIpConfigName = 'frontend-public'
var frontendPortName = 'port-80'
var backendPoolName = 'pool-webapp'
var backendSettingsName = 'settings-webapp-https'
var listenerName = 'listener-http'
var probeName = 'probe-webapp'
var routingRuleName = 'rule-http-to-webapp'

resource publicIp 'Microsoft.Network/publicIPAddresses@2026-03-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      // Gives the gateway a url: <label>.<region>.cloudapp.azure.com
      domainNameLabel: 'agw-${toLower(applicationname)}-${uniqueString(resourceGroup().id)}'
    }
  }
}

resource gateway 'Microsoft.Network/applicationGateways@2026-03-01' = {
  name: gatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: gatewayIpConfigName
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpConfigName
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: frontendPortName
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              fqdn: backendHostName
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Https'
          path: healthProbePath
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          // Send the web app's own hostname as Host header, otherwise App Service does not know which site is meant.
          pickHostNameFromBackendHttpSettings: true
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: backendSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          // Same reason as in the probe: App Service routes on the Host header.
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', gatewayName, probeName)
          }
        }
      }
    ]
    httpListeners: [
      {
        name: listenerName
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', gatewayName, frontendIpConfigName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', gatewayName, frontendPortName)
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: routingRuleName
        properties: {
          ruleType: 'Basic'
          // Required for the v2 SKU.
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', gatewayName, listenerName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gatewayName, backendPoolName)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', gatewayName, backendSettingsName)
          }
        }
      }
    ]
  }
}

output gatewayUrl string = 'http://${publicIp.properties.dnsSettings.fqdn}'
