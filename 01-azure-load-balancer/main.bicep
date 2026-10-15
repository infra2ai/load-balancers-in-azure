// Video 1: Azure Load Balancer.
//
// Builds everything the video needs EXCEPT the load balancer itself, which you
// create in the portal while following the video:
//   - a virtual network with a web subnet and a client subnet
//   - three Linux web servers (web-01, web-02, web-03), one per availability zone,
//     each running the demo website, with no public IP
//   - a client VM with a public IP: the machine you SSH into, and the place to
//     call an internal load balancer from
//   - network security groups: HTTP from the Internet to the web servers, SSH only
//     from your own public IP
//
// The web subnet is a PRIVATE subnet (no default outbound access), which is how
// new Azure virtual networks behave today. The web servers therefore have no way
// out to the Internet until you give them one (an outbound rule, in the video).

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
  video: '01-azure-load-balancer'
}

var clientSubnetPrefix = '10.0.1.0/24'
var webSubnetPrefix = '10.0.2.0/24'

// Azure keeps the first four addresses of a subnet, so .4 is the first one free.
var webServers = [
  { name: 'web-01', ip: '10.0.2.4', zone: '1', color: '#c0392b' }
  { name: 'web-02', ip: '10.0.2.5', zone: '2', color: '#1e8449' }
  { name: 'web-03', ip: '10.0.2.6', zone: '3', color: '#1f618d' }
]

resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-from-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
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

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-lb-demo'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'snet-client'
        properties: { addressPrefix: clientSubnetPrefix, networkSecurityGroup: { id: nsgClient.id } }
      }
      {
        name: 'snet-web'
        properties: {
          addressPrefix: webSubnetPrefix
          networkSecurityGroup: { id: nsgWeb.id }
          defaultOutboundAccess: false
        }
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
    site: { label: s.name, color: s.color, hideClient: hideClient }
    tags: tags
  }
}]

module client '../shared/bicep/web-vm.bicep' = {
  name: 'vm-client'
  params: {
    name: 'client-vm'
    location: location
    subnetId: vnet.properties.subnets[0].id
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    privateIp: '10.0.1.4'
    publicIp: true
    installSite: false
    tags: tags
  }
}

output webServers array = [for (s, i) in webServers: {
  name: web[i].outputs.name
  privateIp: web[i].outputs.privateIp
  zone: useZones ? s.zone : ''
}]
output clientName string = client.outputs.name
output clientPublicIp string = client.outputs.publicIp
