targetScope = 'resourceGroup'

resource target 'Microsoft.KeyVault/vaults/keys@2024-12-01-preview' existing = {
  name: 'name' // Replace with your name or param
}

output name string = target.name
output uri string = target.properties.keyUri
