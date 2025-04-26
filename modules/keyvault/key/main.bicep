targetScope = 'resourceGroup'

resource vault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: 'name' // Replace with your name or param

  resource key 'keys@2024-11-01' existing = {
    name: 'name' // Replace with your name or param
  }
}

output name string = vault.name
output uri string = vault::key.properties.keyUri
