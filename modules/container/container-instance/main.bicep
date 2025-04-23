targetScope = 'resourceGroup'

// param foo string

resource target 'Microsoft.ContainerInstance/containerGroups@2023-05-01' existing = {
  name: 'name'
}

output id string = target.id
output name string = target.name
