#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Claude Code CLI with all required dependencies on Windows.
.DESCRIPTION
    Detects available package managers (winget/chocolatey), installs Node.js LTS,
    Git, and Claude Code CLI globally via npm. Skips components already installed.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "    [--] $Message (already installed)" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [!!] $Message" -ForegroundColor Red
}

function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

function Get-CommandVersion {
    param([string]$Command, [string]$VersionArg = "--version")
    try {
        $out = & $Command $VersionArg 2>&1
        return ($out | Select-Object -First 1).ToString().Trim()
    } catch {
        return $null
    }
}

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# ──────────────────────────────────────────────
# 1. Detect package manager
# ──────────────────────────────────────────────
Write-Step "Detecting package manager"

$useWinget = Test-CommandExists "winget"
$useChoco  = Test-CommandExists "choco"

if ($useWinget) {
    Write-Ok "winget available"
} elseif ($useChoco) {
    Write-Ok "Chocolatey available"
} else {
    Write-Host "    [!!] Neither winget nor Chocolatey found." -ForegroundColor Red
    Write-Host "         Installing Chocolatey..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refresh-Path
        $useChoco = Test-CommandExists "choco"
        if ($useChoco) { Write-Ok "Chocolatey installed" }
        else { throw "Chocolatey installation failed" }
    } catch {
        Write-Fail "Could not install a package manager: $_"
        Write-Host "         Please install winget (App Installer) or Chocolatey manually and re-run." -ForegroundColor Red
        exit 1
    }
}

# ──────────────────────────────────────────────
# 2. Node.js (LTS) + npm
# ──────────────────────────────────────────────
Write-Step "Checking Node.js"

$nodeVersion = Get-CommandVersion "node"
if ($nodeVersion) {
    Write-Skip "Node.js $nodeVersion"
} else {
    Write-Host "    Installing Node.js LTS..." -ForegroundColor Yellow
    try {
        if ($useWinget) {
            winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
        } else {
            choco install nodejs-lts -y
        }
        Refresh-Path
        $nodeVersion = Get-CommandVersion "node"
        if ($nodeVersion) { Write-Ok "Node.js $nodeVersion installed" }
        else { throw "node command not found after install" }
    } catch {
        Write-Fail "Node.js installation failed: $_"
        exit 1
    }
}

$npmVersion = Get-CommandVersion "npm"
if ($npmVersion) {
    Write-Ok "npm $npmVersion"
} else {
    Write-Fail "npm not found — it should ship with Node.js. Check your installation."
    exit 1
}

# ──────────────────────────────────────────────
# 3. Git
# ──────────────────────────────────────────────
Write-Step "Checking Git"

$gitVersion = Get-CommandVersion "git"
if ($gitVersion) {
    Write-Skip "Git $gitVersion"
} else {
    Write-Host "    Installing Git..." -ForegroundColor Yellow
    try {
        if ($useWinget) {
            winget install --id Git.Git --accept-source-agreements --accept-package-agreements --silent
        } else {
            choco install git -y
        }
        Refresh-Path
        $gitVersion = Get-CommandVersion "git"
        if ($gitVersion) { Write-Ok "Git $gitVersion installed" }
        else { throw "git command not found after install" }
    } catch {
        Write-Fail "Git installation failed: $_"
        exit 1
    }
}

# ──────────────────────────────────────────────
# 4. Claude Code CLI
# ──────────────────────────────────────────────
Write-Step "Checking Claude Code CLI"

$claudeVersion = Get-CommandVersion "claude"
if ($claudeVersion) {
    Write-Skip "claude $claudeVersion"
} else {
    Write-Host "    Installing Claude Code CLI globally via npm..." -ForegroundColor Yellow
    try {
        npm install -g @anthropic-ai/claude-code
        Refresh-Path
        $claudeVersion = Get-CommandVersion "claude"
        if ($claudeVersion) { Write-Ok "Claude Code CLI installed" }
        else { throw "claude command not found after install" }
    } catch {
        Write-Fail "Claude Code CLI installation failed: $_"
        exit 1
    }
}

# ──────────────────────────────────────────────
# 5. PATH validation
# ──────────────────────────────────────────────
Write-Step "Validating PATH entries"

$npmGlobalBin = (npm config get prefix) + "\bin" 2>$null
if (-not ($env:PATH -split ";" | Where-Object { $_ -eq $npmGlobalBin })) {
    $currentUser = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not ($currentUser -split ";" | Where-Object { $_ -eq $npmGlobalBin })) {
        [System.Environment]::SetEnvironmentVariable("PATH", "$currentUser;$npmGlobalBin", "User")
        Write-Ok "Added $npmGlobalBin to user PATH"
    }
    Refresh-Path
} else {
    Write-Ok "npm global bin already in PATH"
}

# ──────────────────────────────────────────────
# 6. Validation summary
# ──────────────────────────────────────────────
Write-Step "Validation"

$ok = $true
foreach ($item in @(
    @{ Cmd = "node";   Arg = "--version"; Label = "Node.js" },
    @{ Cmd = "npm";    Arg = "--version"; Label = "npm"     },
    @{ Cmd = "git";    Arg = "--version"; Label = "Git"     },
    @{ Cmd = "claude"; Arg = "--version"; Label = "Claude"  }
)) {
    $v = Get-CommandVersion $item.Cmd $item.Arg
    if ($v) { Write-Ok "$($item.Label): $v" }
    else    { Write-Fail "$($item.Label) not found"; $ok = $false }
}

if (-not $ok) {
    Write-Host "`nSome components are missing. Please resolve the errors above." -ForegroundColor Red
    exit 1
}

Write-Step "Smoke test — claude --version"
& claude --version

Write-Host "`nClaude Code CLI is ready." -ForegroundColor Green
Write-Host "Run 'claude' to start, or 'claude --help' for options.`n"
