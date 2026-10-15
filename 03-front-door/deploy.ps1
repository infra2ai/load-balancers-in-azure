<#
.SYNOPSIS
    Videos 3 and 4: Azure Front Door and Azure Traffic Manager. Deploys the same
    web server in three regions on three continents (Singapore, Sweden,
    United States), each with its own virtual network, a public IP with a DNS
    name and the demo website showing its country and flag. Front Door and
    Traffic Manager are created in the portal, in the videos.
.PARAMETER ResourceGroup
    Resource group (default rg-fd-demo).
.PARAMETER Location
    Where the resource group's metadata lives (default southeastasia).
.PARAMETER VmSize
    VM size. Default: Standard_B1s, then the next sizes that exist in every region.
.PARAMETER AllowIp
    The address allowed to SSH in. Default: your public IP, detected.
.PARAMETER LockToFrontDoor
    Accept web traffic only from the AzureFrontDoor.Backend service tag.
.PARAMETER HideClient
    Hide your own public IP on the demo pages (for recordings).
.PARAMETER SkipCheck
    Do not test the web servers at the end.
#>
param(
    [string]$ResourceGroup = 'rg-fd-demo',
    [string]$Location = 'southeastasia',
    [string]$VmSize,
    [string]$AllowIp,
    [switch]$LockToFrontDoor,
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

$deployment = Invoke-LabDeployment -ResourceGroup $ResourceGroup -Location $Location -Template (Join-Path $PSScriptRoot 'main.bicep') -Parameters @{
    sshPublicKey    = $publicKey
    allowedSourceIp = $AllowIp
    lockToFrontDoor = $LockToFrontDoor.IsPresent
    hideClient      = $HideClient.IsPresent
    adminUsername   = $script:LbUser
}

$origins = @(Get-LabOutput $deployment 'origins')
if (-not $SkipCheck -and -not $LockToFrontDoor) {
    Test-LabPublic -Url @($origins | ForEach-Object { "http://$($_.fqdn)/healthz" }) | Out-Null
}

Write-Step 'Ready.'
foreach ($o in $origins) { Write-Note ("{0} ({1})  {2}  {3}" -f $o.country, $o.location, $o.publicIp, $o.fqdn) }
Write-Note "SSH: ssh -i `"$script:LbKey`" $script:LbUser@<public IP>"
if ($LockToFrontDoor) { Write-Note 'Web traffic is limited to the AzureFrontDoor.Backend service tag, so the sites do not answer directly.' }
Write-Note "VM size used: $script:LbSize"
Write-Note "Next: create Front Door (video 3) or Traffic Manager (video 4) in the portal. Remove everything with ./cleanup.ps1 -ResourceGroup $ResourceGroup"
