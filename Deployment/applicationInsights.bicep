param location string

@allowed([
  'O'
  'T'
  'A'
  'P'
])
param stage string

param applicationname string

var applicationInsightsName = '${applicationname}-Insights-${stage}'

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}
output instrumentationKey string = appInsights.properties.InstrumentationKey
