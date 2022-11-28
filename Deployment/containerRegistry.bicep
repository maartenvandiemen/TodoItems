resource acr 'Microsoft.ContainerRegistry/registries@2021-12-01-preview' existing = {
  name: 'maartenvandiemen'
  scope: resourceGroup('Docker')
}

output loginServer string = acr.properties.loginServer
