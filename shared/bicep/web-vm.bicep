// One Linux VM for the "Load Balancers in Azure" demos: NIC, optional Standard
// public IP, optional availability zone, and (optionally) the demo website
// baked in with cloud-init. Used by every video's template.

@description('VM name. Also the Linux host name and the name shown on the demo page.')
param name string

param location string

@description('Subnet the network interface joins.')
param subnetId string

param adminUsername string

@description('SSH public key (the contents of the .pub file). Password sign-in is turned off.')
param sshPublicKey string

param vmSize string = 'Standard_B1s'

@description('Availability zone "1", "2" or "3". Leave empty for a VM without a zone.')
param zone string = ''

@description('Static private IP for the NIC. Leave empty to let Azure pick one.')
param privateIp string = ''

@description('Give the VM its own Standard public IP address.')
param publicIp bool = false

@description('DNS name label for the public IP (needed for Traffic Manager Azure endpoints). Empty for none.')
param publicIpDnsLabel string = ''

@description('Install the demo website. False for a plain client VM.')
param installSite bool = true

@description('Settings of the demo website: label, group, color, country, city, flag, hideClient.')
param site object = {}

param tags object = {}

var envLines = [
  'LBDEMO_NAME="${name}"'
  'LBDEMO_LABEL="${site.?label ?? name}"'
  'LBDEMO_GROUP="${site.?group ?? ''}"'
  'LBDEMO_COLOR="${site.?color ?? '#34495e'}"'
  'LBDEMO_COUNTRY="${site.?country ?? ''}"'
  'LBDEMO_CITY="${site.?city ?? ''}"'
  'LBDEMO_FLAG="${site.?flag ?? ''}"'
  'LBDEMO_HIDE_CLIENT="${(site.?hideClient ?? false) ? '1' : '0'}"'
]
var cloudInit = replace(replace(loadTextContent('../cloud-init.yaml'), '__APP_B64__', base64(loadTextContent('../webapp/app.py'))), '__ENV_B64__', base64('${join(envLines, '\n')}\n'))

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (publicIp) {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  zones: empty(zone) ? null : ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: empty(publicIpDnsLabel) ? null : { domainNameLabel: publicIpDnsLabel }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: empty(privateIp) ? 'Dynamic' : 'Static'
          privateIPAddress: empty(privateIp) ? null : privateIp
          publicIPAddress: publicIp ? { id: pip.id } : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  zones: empty(zone) ? null : [zone]
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      customData: installSite ? base64(cloudInit) : null
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: sshPublicKey }] }
      }
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: 'latest' }
      osDisk: { createOption: 'FromImage', managedDisk: { storageAccountType: 'StandardSSD_LRS' }, deleteOption: 'Delete' }
    }
    networkProfile: { networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

output name string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output publicIp string = publicIp ? pip!.properties.ipAddress : ''
output fqdn string = publicIp ? (pip!.properties.?dnsSettings.?fqdn ?? '') : ''
