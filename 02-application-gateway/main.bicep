// Video 2: Azure Application Gateway.
//
// Builds everything the video needs EXCEPT the application gateway itself, which
// you create in the portal while following the video:
//   - a virtual network with an empty gateway subnet (snet-appgw), a web subnet
//     and a client subnet
//   - six Linux web servers in three pools of two: red-01/02, green-01/02,
//     blue-01/02, each running the demo website, with no public IP. A server
//     answers on its own path (/red/..., /green/..., /blue/...) and on /, and says
//     so on the page, which makes path-based routing visible
//   - a client VM with a public IP to SSH into
//   - network security groups: the web servers accept HTTP only from the gateway
//     subnet, SSH only from the client VM and from your own public IP
//
// The web subnet is a private subnet (no default outbound access).

targetScope = 'resourceGroup'

param location string = resourceGroup().location

param adminUsername string = 'azureuser'

@description('SSH public key (the contents of the .pub file).')
param sshPublicKey string

@description('Your public IP address: the only address allowed to SSH in. Use * to allow every address (not recommended).')
param allowedSourceIp string

param vmSize string = 'Standard_B1s'

@description('Spread the web servers over availability zones 1, 2 and 3. Turn off for a region without zones.')
param useZones bool = true

@description('Hide the viewer\'s own public IP on the demo pages (used when recording).')
param hideClient bool = false

param tags object = {
  purpose: 'lb-series-demo'
  video: '02-application-gateway'
}

var gatewaySubnetPrefix = '10.0.0.0/24'
var webSubnetPrefix = '10.0.1.0/24'
var clientSubnetPrefix = '10.0.2.0/24'

// Two shades per colour so the two servers of a pool can be told apart on screen.
var webServers = [
  { name: 'red-01', group: 'red', ip: '10.0.1.4', zone: '1', color: '#b03a2e' }
  { name: 'red-02', group: 'red', ip: '10.0.1.5', zone: '2', color: '#e74c3c' }
  { name: 'green-01', group: 'green', ip: '10.0.1.6', zone: '3', color: '#1e8449' }
  { name: 'green-02', group: 'green', ip: '10.0.1.7', zone: '1', color: '#2ecc71' }
  { name: 'blue-01', group: 'blue', ip: '10.0.1.8', zone: '2', color: '#1f618d' }
  { name: 'blue-02', group: 'blue', ip: '10.0.1.9', zone: '3', color: '#3498db' }
]

resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-from-gateway-subnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: gatewaySubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['80', '443']
        }
      }
      {
        name: 'Allow-SSH-from-client-subnet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: clientSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-SSH-from-my-IP'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource nsgClient 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-client'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-from-my-IP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// The gateway subnet has no NSG on purpose: the video shows the rules a gateway subnet needs.
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-appgw-demo'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'snet-appgw'
        properties: { addressPrefix: gatewaySubnetPrefix }
      }
      {
        name: 'snet-web'
        properties: {
          addressPrefix: webSubnetPrefix
          networkSecurityGroup: { id: nsgWeb.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-client'
        properties: { addressPrefix: clientSubnetPrefix, networkSecurityGroup: { id: nsgClient.id } }
      }
    ]
  }
}

module web '../shared/bicep/web-vm.bicep' = [for s in webServers: {
  name: 'vm-${s.name}'
  params: {
    name: s.name
    location: location
    subnetId: vnet.properties.subnets[1].id
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    zone: useZones ? s.zone : ''
    privateIp: s.ip
    site: { label: s.name, group: s.group, color: s.color, hideClient: hideClient }
    tags: tags
  }
}]

module client '../shared/bicep/web-vm.bicep' = {
  name: 'vm-client'
  params: {
    name: 'client-vm'
    location: location
    subnetId: vnet.properties.subnets[2].id
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    privateIp: '10.0.2.4'
    publicIp: true
    installSite: false
    tags: tags
  }
}

output webServers array = [for (s, i) in webServers: {
  name: web[i].outputs.name
  group: s.group
  privateIp: web[i].outputs.privateIp
  zone: useZones ? s.zone : ''
}]
output clientName string = client.outputs.name
output clientPublicIp string = client.outputs.publicIp
