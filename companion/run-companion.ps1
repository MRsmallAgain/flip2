# TCL Flip2 Manager — dependency check, npm install if needed, start Companion.
# Usage: .\run-companion.ps1 [-Smoke] [extra electron args…]
param(
    [switch]$Smoke,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ElectronArgs
)

$ErrorActionPreference = 'Stop'

$CompanionDir = $PSScriptRoot
$Flip2Root = (Resolve-Path (Join-Path $CompanionDir '..')).Path
$WizardDir = Join-Path $Flip2Root 'wizard'

function Die($msg) {
    Write-Error "flip2-manager: $msg"
    exit 1
}

function Warn($msg) {
    Write-Warning "flip2-manager: $msg"
}

Write-Host '=== TCL Flip2 Manager (Companion) ==='
Write-Host "Repo: $Flip2Root"

if (-not (Test-Path (Join-Path $WizardDir 'pages'))) {
    Die "wizard\ not found at $WizardDir — run from a full flip2 checkout."
}
if (-not (Test-Path (Join-Path $CompanionDir 'package.json'))) {
    Die 'companion\package.json missing.'
}

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Die 'Node.js is not installed. Install Node 18+ (https://nodejs.org/) then re-run this script.'
}
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Die 'npm is not on PATH (usually ships with Node.js).'
}

try {
    $nodeVer = node -p "process.versions.node.split('.')[0]"
    if ([int]$nodeVer -lt 18) {
        Warn "Node $nodeVer detected; Node 18+ is recommended for Electron 33."
    }
} catch {
    Warn 'Could not read Node version.'
}

$ElectronBin = Join-Path $CompanionDir 'node_modules\.bin\electron.cmd'
$ElectronUnix = Join-Path $CompanionDir 'node_modules\.bin\electron'
if (-not (Test-Path $ElectronBin) -and -not (Test-Path $ElectronUnix)) {
    if ($env:FLIP2_SKIP_NPM_INSTALL -eq '1') {
        Die "Electron not installed and FLIP2_SKIP_NPM_INSTALL=1 — run: cd $CompanionDir; npm install"
    }
    Write-Host 'Installing Companion dependencies (first run may take a few minutes)…'
    Push-Location $CompanionDir
    try {
        npm install --no-fund --no-audit
    } finally {
        Pop-Location
    }
    if (-not (Test-Path $ElectronBin) -and -not (Test-Path $ElectronUnix)) {
        Die 'npm install finished but electron is missing.'
    }
}

$bundledAdb = Join-Path $CompanionDir 'platform-tools-win\adb.exe'
if (-not $env:FLIP2_ADB -and (Test-Path $bundledAdb)) {
    $env:FLIP2_ADB = $bundledAdb
}

$adbPath = $env:FLIP2_ADB
if (-not $adbPath) {
    $adbCmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if (-not $adbCmd) {
        $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
    }
    if ($adbCmd) { $adbPath = $adbCmd.Source }
}
if (-not $adbPath) {
    Warn 'adb not found. Run: npm run fetch:platform-tools:win  (or install Platform Tools — see docs\SETUP-WIZARD-WINDOWS.md)'
} else {
    try {
        $adbVer = & $adbPath version 2>$null | Select-Object -First 1
        if ($adbVer) { Write-Host "adb: $adbVer" }
    } catch {
        Warn 'Could not run adb version.'
    }
}

Warn 'On Windows, install Google USB Driver if adb devices stays empty — see docs\SETUP-WIZARD-WINDOWS.md'

$argsList = @()
if ($Smoke) { $argsList += '--smoke' }
if ($ElectronArgs) { $argsList += $ElectronArgs }

$electron = $ElectronBin
if (-not (Test-Path $electron)) { $electron = $ElectronUnix }

Write-Host 'Starting TCL Flip2 Manager…'
Set-Location $CompanionDir
& $electron . @argsList
exit $LASTEXITCODE
