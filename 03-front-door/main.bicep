// Videos 3 and 4: Azure Front Door and Azure Traffic Manager.
//
// Builds the "origins" both videos need: the same web server in three regions on
// three continents. Each one has its own virtual network, a Standard public IP
// with a DNS name (needed for Traffic Manager Azure endpoints) and the demo
// website showing the country and flag. Front Door itself and Traffic Manager are
// created in the portal while following the videos.
//
//   Southeast Asia  -> Singapore
//   Sweden Central  -> Sweden
//   East US         -> United States
//
// Web traffic is allowed from the whole Internet by default (Traffic Manager
// clients connect straight to the servers). With lockToFrontDoor = true only the
// Azure Front Door service tag is allowed, which is the lock-down the Front Door
// video explains.

targetScope = 'resourceGroup'

param adminUsername string = 'azureuser'

@description('SSH public key (the contents of the .pub file).')
param sshPublicKey string

@description('Your public IP address: the only address allowed to SSH in.')
param allowedSourceIp string

param vmSize string = 'Standard_B1s'

@description('Hide the viewer\'s own public IP on the demo pages (used when recording).')
param hideClient bool = false

@description('Allow web traffic only from Azure Front Door (service tag AzureFrontDoor.Backend).')
param lockToFrontDoor bool = false

@description('Prefix of the public DNS names. A unique suffix and the region code are added.')
param dnsPrefix string = 'lbdemo'

param tags object = {
  purpose: 'lb-series-demo'
  video: '03-front-door'
}

@description('The origins. Change the regions here if you want other countries.')
param origins array = [
  { short: 'sea', location: 'southeastasia', octet: 1, label: 'Singapore', country: 'Singapore', city: 'Singapore', flag: '🇸🇬', color: '#c0392b' }
  { short: 'swc', location: 'swedencentral', octet: 2, label: 'Sweden', country: 'Sweden', city: 'Gävle', flag: '🇸🇪', color: '#b8860b' }
  { short: 'eus', location: 'eastus', octet: 3, label: 'United States', country: 'United States', city: 'Virginia', flag: '🇺🇸', color: '#1f618d' }
]

var suffix = take(uniqueString(resourceGroup().id), 6)

module origin 'origin-region.bicep' = [for o in origins: {
  name: 'origin-${o.short}'
  params: {
    location: o.location
    short: o.short
    octet: o.octet
    site: { label: o.label, country: o.country, city: o.city, flag: o.flag, color: o.color }
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    allowedSourceIp: allowedSourceIp
    vmSize: vmSize
    hideClient: hideClient
    lockToFrontDoor: lockToFrontDoor
    dnsLabel: '${dnsPrefix}-${suffix}-${o.short}'
    tags: tags
  }
}]

output origins array = [for (o, i) in origins: {
  short: o.short
  country: o.country
  location: o.location
  name: origin[i].outputs.name
  publicIp: origin[i].outputs.publicIp
  fqdn: origin[i].outputs.fqdn
}]
