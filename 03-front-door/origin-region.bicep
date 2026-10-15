// One origin web server in one region: its own virtual network, a network
// security group, a Standard public IP with a DNS name, and a Linux VM running the
// demo website with the country and flag of the region on the page.
// Deployed once per region by main.bicep.

param location string

@description('Short region code used in resource names, for example sea.')
param short string

@description('Second octet of the 10.x.0.0/16 address space of this region (every region gets its own).')
param octet int

@description('What the demo page shows: label, country, city, flag, color.')
param site object

param adminUsername string
param sshPublicKey string

@description('Your public IP address: the only address allowed to SSH in.')
param allowedSourceIp string

param vmSize string
param hideClient bool

@description('Web traffic is allowed only from Azure Front Door (service tag AzureFrontDoor.Backend) instead of from the whole Internet.')
param lockToFrontDoor bool

@description('DNS name label for the public IP: <label>.<region>.cloudapp.azure.com')
param dnsLabel string

param tags object

var vnetPrefix = '10.${octet}.0.0/16'
var subnetPrefix = '10.${octet}.0.0/24'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${short}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: lockToFrontDoor ? 'Allow-HTTP-from-AzureFrontDoor' : 'Allow-HTTP-from-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: lockToFrontDoor ? 'AzureFrontDoor.Backend' : 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
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

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${short}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [vnetPrefix] }
    subnets: [
      {
        name: 'snet-web'
        properties: { addressPrefix: subnetPrefix, networkSecurityGroup: { id: nsg.id } }
      }
    ]
  }
}

module vm '../shared/bicep/web-vm.bicep' = {
  name: 'vm-${short}'
  params: {
    name: 'web-${short}'
    location: location
    subnetId: vnet.properties.subnets[0].id
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    privateIp: '10.${octet}.0.4'
    publicIp: true
    publicIpDnsLabel: dnsLabel
    site: union(site, { hideClient: hideClient })
    tags: tags
  }
}

output name string = vm.outputs.name
output location string = location
output publicIp string = vm.outputs.publicIp
output fqdn string = vm.outputs.fqdn
