targetScope = 'resourceGroup'

resource target 'Microsoft.Network/networkSecurityGroups@2024-05-01' existing = {
  name: 'name' // Replace with your name or param
}

output Id string = target.id
output Name string = target.name
