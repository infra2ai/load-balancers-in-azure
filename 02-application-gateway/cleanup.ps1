<#
.SYNOPSIS
    Video 2: removes everything deploy.ps1 created (the whole resource group).
#>
param(
    [string]$ResourceGroup = 'rg-appgw-demo',
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..' 'shared' 'scripts' 'common.ps1')
Assert-LabTools
Remove-LabGroup -ResourceGroup $ResourceGroup -Yes:$Yes
