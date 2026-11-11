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
//
// HOW THE PARTS FIT TOGETHER (an Application Gateway is built from small named parts that refer to each other):
//
//   frontend IP  +  frontend port  +  protocol          ->  LISTENER      "where and how clients connect"
//   listener  ->  ROUTING RULE  ->  backend pool         "which application receives the request"
//                                   + backend settings   "how to talk to it (port, protocol, host header, health probe)"
//
// There is one of each here (one IP, one port, one listener, one rule, one pool), because it serves one API.
// The structure is still required: the gateway is designed for many sites, where listeners share IPs and ports.

param location string

param applicationname string

@description('Subnet of the gateway. Must be a subnet that only contains the gateway.')
param subnetId string

@description('Default hostname of the web app, for example site-todoitems-abc123.azurewebsites.net.')
param backendHostName string

@description('Path of the health endpoint of the web app.')
param healthProbePath string = '/health'

@description('Resource id of the Log Analytics workspace that receives the access log of the gateway.')
param workspaceId string

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
    }
    // The subnet the gateway itself lives in (its instances get their private addresses from it).
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
    // FRONTEND IP: the address clients connect to. A gateway can have a public one, a private one, or both.
    // Here: the public IP above.
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
    // FRONTEND PORT: a port number the gateway listens on. It is declared on its own so that several listeners
    // can share it. HTTPS later: add a port 443 here, and a listener with a certificate.
    frontendPorts: [
      {
        name: frontendPortName
        properties: {
          port: 80
        }
      }
    ]
    // BACKEND POOL: where requests are sent to. Here: the hostname of the web app, which resolves to its
    // private endpoint through the private DNS zone.
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
    // HEALTH PROBE: how the gateway checks that the web app is up. It only sends requests to a healthy backend.
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
    // BACKEND SETTINGS: how the gateway talks to the backend: HTTPS on port 443, with the web app's own hostname
    // as Host header, and the health probe above.
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
    // LISTENER: "accept HTTP requests that arrive on this frontend IP and this frontend port".
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
    // ROUTING RULE: ties it together. Requests that arrive on the listener go to the backend pool, using the
    // backend settings. (With several sites, there would be one listener and one rule per site.)
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

// Access log: every request that went through the gateway, with the response code and the backend it went to.
#disable-next-line use-recent-api-versions
resource gatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: gateway
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
    ]
  }
}

output gatewayUrl string = 'http://${publicIp.properties.dnsSettings.fqdn}'
