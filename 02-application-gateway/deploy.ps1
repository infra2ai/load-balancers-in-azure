<#
.SYNOPSIS
    Video 2: Azure Application Gateway. Deploys the lab: a virtual network with an
    empty gateway subnet, two NSGs, six web servers in red, green and blue pools of
    two, and a client VM. It also makes a self-signed certificate for the HTTPS
    listener part. The application gateway itself is created in the portal, in
    the video.
.PARAMETER Location
    Region (default southeastasia).
.PARAMETER ResourceGroup
    Resource group (default rg-appgw-demo).
.PARAMETER VmSize
    VM size. Default: Standard_B1s, then the next sizes that exist in the region.
.PARAMETER AllowIp
    The address allowed to SSH in. Default: your public IP, detected.
.PARAMETER NoZones
    For a region without availability zones.
.PARAMETER HideClient
    Hide your own public IP on the demo pages (for recordings).
.PARAMETER SkipCheck
    Do not test the web servers at the end.
#>
param(
    [string]$Location = 'southeastasia',
    [string]$ResourceGroup = 'rg-appgw-demo',
    [string]$VmSize,
    [string]$AllowIp,
    [switch]$NoZones,
    [switch]$HideClient,
    [switch]$SkipCheck
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..' 'shared' 'scripts' 'common.ps1')

if ($VmSize) { $env:LB_VM_SIZES = $VmSize }
Assert-LabTools
if (-not $AllowIp) { $AllowIp = Get-MyPublicIp }
if (-not $AllowIp) { throw 'Could not detect your public IP. Pass it with -AllowIp.' }
Write-Note "SSH will be allowed only from $AllowIp"
$publicKey = Initialize-SshKey
New-DemoCert -Name 'appgw-demo'

$deployment = Invoke-LabDeployment -ResourceGroup $ResourceGroup -Location $Location -Template (Join-Path $PSScriptRoot 'main.bicep') -Parameters @{
    location        = $Location
    sshPublicKey    = $publicKey
    allowedSourceIp = $AllowIp
    useZones        = (-not $NoZones.IsPresent)
    hideClient      = $HideClient.IsPresent
    adminUsername   = $script:LbUser
}

$webServers = @(Get-LabOutput $deployment 'webServers')
$clientIp = Get-LabOutput $deployment 'clientPublicIp'
if (-not $SkipCheck) {
    Test-LabWeb -ResourceGroup $ResourceGroup -ClientVm (Get-LabOutput $deployment 'clientName') -Ip @($webServers.privateIp) | Out-Null
}

Write-Step 'Ready.'
foreach ($w in $webServers) { Write-Note ("{0} pool  {1}  {2}  zone {3}" -f $w.group, $w.name, $w.privateIp, $(if ($w.zone) { $w.zone } else { 'none' })) }
Write-Note "client-vm  $clientIp"
Write-Note "SSH: ssh -i `"$script:LbKey`" $script:LbUser@$clientIp"
Write-Note "VM size used: $script:LbSize"
Write-Note "Next: create the application gateway in the portal, as in the video. Remove everything with ./cleanup.ps1 -ResourceGroup $ResourceGroup"
