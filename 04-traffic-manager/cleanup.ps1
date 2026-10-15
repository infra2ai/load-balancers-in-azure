<#
.SYNOPSIS
    Video 4: removes everything deploy.ps1 created (the whole resource group rg-tm-demo).
#>
param(
    [string]$ResourceGroup = 'rg-tm-demo',
    [switch]$Yes
)
& (Join-Path $PSScriptRoot '..' '03-front-door' 'cleanup.ps1') -ResourceGroup $ResourceGroup -Yes:$Yes
