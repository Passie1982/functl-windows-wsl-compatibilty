<#
.SYNOPSIS
    Installs functl inside WSL, wires up a Windows-side functl wrapper, and merges a
    Fundament portal kubeconfig into the default kubeconfig so kubectl/OpenLens/Freelens
    can authenticate via functl running in WSL.

.PARAMETER KubeconfigPath
    Path to the kubeconfig file downloaded from the Fundament portal
    (e.g. C:\Users\<you>\Downloads\kubeconfig-<org>-<cluster>.yaml).

.PARAMETER WslDistro
    Name of the WSL distro to install/run functl in. Defaults to "Ubuntu".

.PARAMETER Force
    Reinstall functl in WSL even if it is already present.

.EXAMPLE
    .\Setup-FundamentKubeconfig.ps1 -KubeconfigPath "C:\Users\HorstP\Downloads\kubeconfig-downloaded-from-the-fundament-console.yaml"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KubeconfigPath,

    [string]$WslDistro = "Ubuntu",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# --- 0. Validate prerequisites -------------------------------------------------
Write-Step "Validating prerequisites"

if (-not (Test-Path $KubeconfigPath)) {
    throw "Kubeconfig not found at '$KubeconfigPath'"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl not found on PATH. Install kubectl before running this script."
}

$distros = (wsl --list --quiet) -replace "`0", "" | Where-Object { $_.Trim() -ne "" }
if ($distros -notcontains $WslDistro) {
    throw "WSL distro '$WslDistro' not found. Available distros: $($distros -join ', ')"
}

# --- 1. Install functl inside WSL ----------------------------------------------
Write-Step "Checking functl installation in WSL ($WslDistro)"

$existing = wsl -d $WslDistro -- bash -lc "command -v functl" 2>$null
if ($existing -and -not $Force) {
    Write-Host "functl already installed at: $existing"
}
else {
    Write-Host "Installing functl into ~/.local/bin (no sudo required)..."
    $arch = (wsl -d $WslDistro -- uname -m).Trim()
    switch ($arch) {
        "x86_64" { $functlArch = "linux_amd64" }
        "aarch64" { $functlArch = "linux_arm64" }
        "arm64" { $functlArch = "linux_arm64" }
        default { throw "Unsupported WSL architecture: $arch" }
    }

    $installCmd = @(
        "set -e",
        "mkdir -p ~/.local/bin",
        "curl -fsSL https://github.com/fundament-oss/fundament/releases/download/functl-latest/functl_$functlArch.tar.gz | tar -xzf - -C ~/.local/bin functl",
        "chmod +x ~/.local/bin/functl",
        "~/.local/bin/functl version"
    ) -join " && "

    wsl -d $WslDistro -- bash -lc "$installCmd"
    if ($LASTEXITCODE -ne 0) { throw "functl installation failed in WSL." }
}

# --- 2. Check functl authentication ---------------------------------------------
Write-Step "Checking functl authentication in WSL"

$authStatus = (wsl -d $WslDistro -- bash -lc "functl auth status" 2>&1) -join "`n"
Write-Host $authStatus
if ($authStatus -notmatch "Authenticated:\s*yes") {
    Write-Host ""
    Write-Host "functl is not authenticated yet. Run this once, interactively, then re-run this script:" -ForegroundColor Yellow
    Write-Host "  wsl -d $WslDistro -- functl auth login" -ForegroundColor Yellow
}

# --- 3. Create Windows wrapper so kubectl's exec plugin can find functl ---------
Write-Step "Configuring Windows functl wrapper"

$binDir = Join-Path $env:USERPROFILE "bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

$wrapperPath = Join-Path $binDir "functl.cmd"
@"
@echo off
wsl.exe -d $WslDistro -- functl %*
"@ | Out-File -FilePath $wrapperPath -Encoding ascii

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
    Write-Host "Added $binDir to the user PATH (new processes will pick this up)."
}
if ($env:PATH -notlike "*$binDir*") {
    $env:PATH = "$env:PATH;$binDir"
}
Write-Host "Wrapper created at $wrapperPath"

# --- 4. Merge the downloaded kubeconfig into the default kubeconfig ------------
Write-Step "Merging kubeconfig into `$HOME\.kube\config"

$kubeDir = Join-Path $env:USERPROFILE ".kube"
New-Item -ItemType Directory -Force -Path $kubeDir | Out-Null
$defaultConfig = Join-Path $kubeDir "config"

$mergeList = @()
if (Test-Path $defaultConfig) {
    $backup = Join-Path $kubeDir ("config.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $defaultConfig $backup
    Write-Host "Backed up existing kubeconfig to $backup"
    $mergeList += $defaultConfig
}
$mergeList += $KubeconfigPath

$previousKubeconfigEnv = $env:KUBECONFIG
try {
    $env:KUBECONFIG = ($mergeList -join ";")
    $merged = kubectl config view --flatten
    $mergedTmp = Join-Path $kubeDir "config.merged"
    $merged | Out-File -FilePath $mergedTmp -Encoding utf8
}
finally {
    if ($null -ne $previousKubeconfigEnv) { $env:KUBECONFIG = $previousKubeconfigEnv } else { Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue }
}

Move-Item -Force $mergedTmp $defaultConfig
Write-Host "Merge complete."

# --- 5. Summary ------------------------------------------------------------------
Write-Step "Contexts available"
kubectl config get-contexts --kubeconfig $defaultConfig
