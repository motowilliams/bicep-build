targetScope = 'resourceGroup'

resource target 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: 'name'
}

output Id string = target.id
output Name string = target.name
