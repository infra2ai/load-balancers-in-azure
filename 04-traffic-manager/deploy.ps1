<#
.SYNOPSIS
    Video 4: Azure Traffic Manager. Deploys the same three-region lab as video 3
    (see ../03-front-door/deploy.ps1 and its parameters), in its own resource
    group (default rg-tm-demo).
#>
param(
    [string]$ResourceGroup = 'rg-tm-demo',
    [string]$Location = 'southeastasia',
    [string]$VmSize,
    [string]$AllowIp,
    [switch]$HideClient,
    [switch]$SkipCheck
)
$forward = @{}
foreach ($key in $PSBoundParameters.Keys) { $forward[$key] = $PSBoundParameters[$key] }
$forward['ResourceGroup'] = $ResourceGroup
& (Join-Path $PSScriptRoot '..' '03-front-door' 'deploy.ps1') @forward
