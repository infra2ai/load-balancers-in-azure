# Helpers shared by the deploy and cleanup scripts of every video.
# Dot-source this file from a script; do not run it. Works in PowerShell 7 and
# in Azure Cloud Shell. Needs the Az module and the Bicep CLI.

$script:LbRepo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:LbKey  = if ($env:LB_KEY) { $env:LB_KEY } else { Join-Path $script:LbRepo '.keys' 'lbdemo_ed25519' }
$script:LbUser = if ($env:LB_USER) { $env:LB_USER } else { 'azureuser' }

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Note([string]$Message) { Write-Host "    $Message" }
function Write-Warn([string]$Message) { Write-Host "!!  $Message" -ForegroundColor Yellow }

function Assert-LabTools {
    if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
        throw 'The Az PowerShell module is not installed. Run: Install-Module Az -Scope CurrentUser'
    }
    $context = Get-AzContext
    if (-not $context) { throw 'You are not signed in. Run: Connect-AzAccount' }
    if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
        throw 'The Bicep CLI was not found. Install it with: az bicep install (then add ~/.azure/bin to PATH), or see https://aka.ms/bicep-install'
    }
    Write-Step "Subscription: $($context.Subscription.Name)"
}

# The public IPv4 address Azure will see you connect from (the only address allowed to SSH in).
function Get-MyPublicIp {
    foreach ($url in 'https://api.ipify.org', 'https://ifconfig.me/ip') {
        try { return (Invoke-RestMethod -Uri $url -TimeoutSec 8).ToString().Trim() } catch { }
    }
    return $null
}

# Uses the key pair in .keys/ (created on first use). No passwords anywhere.
function Initialize-SshKey {
    if (-not (Test-Path $script:LbKey)) {
        if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw 'ssh-keygen not found. Install an OpenSSH client.' }
        New-Item -ItemType Directory -Force -Path (Split-Path $script:LbKey) | Out-Null
        $empty = if ($PSVersionTable.PSEdition -eq 'Desktop') { '""' } else { '' }
        & ssh-keygen -q -t ed25519 -N $empty -C lbdemo -f $script:LbKey
        Write-Note "Created a new SSH key pair: $script:LbKey"
    }
    return (Get-Content "$script:LbKey.pub" -Raw).Trim()
}

# Creates the group if needed and deploys the Bicep template. B1s is the cheapest
# size but is sometimes unavailable in a region or zone, so the next size in
# $env:LB_VM_SIZES is tried when Azure says so. Returns the deployment.
function Invoke-LabDeployment {
    param([string]$ResourceGroup, [string]$Location, [string]$Template, [hashtable]$Parameters)
    New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag @{ purpose = 'lb-series-demo' } -Force | Out-Null
    $sizes = if ($env:LB_VM_SIZES) { $env:LB_VM_SIZES -split '\s+' } else { 'Standard_B1s', 'Standard_B2ats_v2', 'Standard_B1ms', 'Standard_B2s' }
    $name = Split-Path (Split-Path $Template) -Leaf
    foreach ($size in $sizes) {
        Write-Step "Deploying to $ResourceGroup ($Location) with VM size $size. This takes a few minutes."
        $p = $Parameters.Clone(); $p['vmSize'] = $size
        try {
            $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -Name $name -TemplateFile $Template -TemplateParameterObject $p -ErrorAction Stop
            $script:LbSize = $size
            return $deployment
        }
        catch {
            $text = ($_ | Out-String)
            if ($text -match 'SkuNotAvailable|NotAvailableForSubscription|ZonalAllocationFailed|AllocationFailed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest') {
                Write-Warn "$size is not available here right now. Trying the next size."
                continue
            }
            if ($text -match 'customData') {
                throw 'The website on a running VM cannot be changed in place. Run cleanup, then deploy again.'
            }
            throw
        }
    }
    throw "None of these VM sizes could be created in ${Location}: $($sizes -join ', '). Try another region."
}

# One output of a deployment as plain objects. The Az module returns arrays as
# object[] or as a JArray, depending on its version.
function Get-LabOutput {
    param($Deployment, [string]$Name)
    $value = $Deployment.Outputs[$Name].Value
    if ($value -is [string]) { return $value }
    if ($value -is [Newtonsoft.Json.Linq.JToken]) { return $value.ToString() | ConvertFrom-Json }
    return ConvertTo-Json -InputObject $value -Depth 8 -Compress | ConvertFrom-Json
}

# Calls /healthz on every IP from inside the virtual network and waits until all answer 200.
function Test-LabWeb {
    param([string]$ResourceGroup, [string]$ClientVm, [string[]]$Ip)
    Write-Step 'Checking the web servers from inside the network.'
    $script = "for ip in $($Ip -join ' '); do printf '%s ' `$ip; curl -s -m 5 -o /dev/null -w '%{http_code}' http://`$ip/healthz; echo; done"
    for ($try = 1; $try -le 8; $try++) {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -VMName $ClientVm -CommandId RunShellScript -ScriptString $script
        $lines = @($result.Value[0].Message -split "`n" | Where-Object { $_ -match '^[0-9.]+ [0-9]{3}$' })
        if (@($lines | Where-Object { $_ -match ' 200$' }).Count -eq $Ip.Count) {
            $lines | ForEach-Object { Write-Note $_ }
            return $true
        }
        Write-Note "not all answering yet (try $try of 8), waiting 15 seconds"
        Start-Sleep -Seconds 15
    }
    $lines | ForEach-Object { Write-Note $_ }
    Write-Warn 'Some web servers did not answer. The site starts a few seconds after the VM; try again in a minute.'
    return $false
}

function Remove-LabGroup {
    param([string]$ResourceGroup, [switch]$Yes)
    if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
        Write-Note "Nothing to delete: $ResourceGroup does not exist."
        return
    }
    if (-not $Yes) {
        $answer = Read-Host "Delete resource group $ResourceGroup and everything in it? [y/N]"
        if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; return }
    }
    Remove-AzResourceGroup -Name $ResourceGroup -Force -AsJob | Out-Null
    Write-Step "Deleting $ResourceGroup. It keeps running in the background and finishes in a few minutes."
}

# Creates a self-signed certificate for the HTTPS listener part of video 2:
# .keys/NAME.pfx (the password is in .keys/NAME.pfx.password) and .keys/NAME.cer.
# Needs openssl; skipped with a note when it is missing.
function New-DemoCert {
    param([string]$Name)
    $dir = Join-Path $script:LbRepo '.keys'
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Warn 'openssl not found, so no demo certificate was made. It is only needed for the HTTPS listener.'
        return
    }
    if (Test-Path (Join-Path $dir "$Name.pfx")) { return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $password = (& openssl rand -hex 12).Trim()
    & openssl req -x509 -newkey rsa:2048 -nodes -keyout (Join-Path $dir "$Name.key") -out (Join-Path $dir "$Name.crt") -days 90 `
        -subj '/CN=lbdemo.example.com' -addext 'subjectAltName=DNS:lbdemo.example.com,DNS:*.lbdemo.example.com' 2>$null
    & openssl pkcs12 -export -out (Join-Path $dir "$Name.pfx") -inkey (Join-Path $dir "$Name.key") -in (Join-Path $dir "$Name.crt") `
        -passout "pass:$password" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>$null
    & openssl x509 -in (Join-Path $dir "$Name.crt") -outform der -out (Join-Path $dir "$Name.cer")
    Set-Content -Path (Join-Path $dir "$Name.pfx.password") -Value $password -NoNewline
    Write-Note "Demo certificate: $(Join-Path $dir "$Name.pfx") (password in $Name.pfx.password)"
}

# Calls every URL from this computer and waits until all answer 200.
function Test-LabPublic {
    param([string[]]$Url)
    Write-Step 'Checking the web servers from here.'
    for ($try = 1; $try -le 10; $try++) {
        $ok = $true
        foreach ($u in $Url) {
            $code = try { (Invoke-WebRequest -Uri $u -TimeoutSec 6 -SkipHttpErrorCheck -UseBasicParsing).StatusCode } catch { 0 }
            if ($code -ne 200) { $ok = $false }
            Write-Note "$code  $u"
        }
        if ($ok) { return $true }
        Write-Note "not all answering yet (try $try of 10), waiting 15 seconds"
        Start-Sleep -Seconds 15
    }
    Write-Warn 'Some servers did not answer from here. They start a few seconds after the VM; try again in a minute.'
    return $false
}
