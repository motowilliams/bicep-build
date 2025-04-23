targetScope = 'resourceGroup'

resource source 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: 'name' // Replace with your name or param
}

resource target 'Microsoft.KeyVault/vaults/keys@2024-11-01' existing = {
  parent: source
  name: 'name' // Replace with your name or param
}

output name string = target.name
output uri string = target.properties.keyUri
