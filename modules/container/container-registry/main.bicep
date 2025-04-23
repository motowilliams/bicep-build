targetScope = 'resourceGroup'

@minLength(5)
@maxLength(50)
param name string = 'acr${uniqueString(subscription().id, resourceGroup().name)}'

param location string = resourceGroup().location

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

resource acrResource 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: name
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
  }
}

output loginServer string = acrResource.properties.loginServer
