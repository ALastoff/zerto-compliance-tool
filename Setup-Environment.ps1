# Zerto Compliance Tool - Complete Setup Helper
# This script ensures .NET is properly installed and PATH is configured
# Run this FIRST before running the installer!

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ZERTO COMPLIANCE TOOL - PRE-INSTALLATION SETUP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "WARNING: This script needs to run as Administrator to modify system PATH" -ForegroundColor Yellow
  Write-Host "   Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
  Write-Host ""
  exit 1
}

Write-Host "Step 1: Checking .NET Installation..." -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan

$dotnetPath = "C:\Program Files\dotnet"
$dotnetExe = "$dotnetPath\dotnet.exe"

if (Test-Path $dotnetExe) {
  $runtimes = & $dotnetExe --list-runtimes
  if ($runtimes -match "Microsoft.WindowsDesktop.App") {
    Write-Host "[OK] Windows Desktop runtime found" -ForegroundColor Green
  } else {
    Write-Host "[WARNING] Windows Desktop runtime not detected; will attempt installation" -ForegroundColor Yellow
  }
  Write-Host "   Location: $dotnetPath" -ForegroundColor Green
} else {
  Write-Host "[ERROR] .NET Runtime NOT found at $dotnetPath" -ForegroundColor Red
  Write-Host ""
  Write-Host "Installing .NET 8.0 Desktop Runtime..." -ForegroundColor Yellow
  Write-Host "This will take a few minutes..." -ForegroundColor Yellow
  
  # Check if dotnet-install.ps1 exists in current directory
  $installerScript = Join-Path (Split-Path -Parent $PSCommandPath) "dotnet-install.ps1"
  
  if (Test-Path $installerScript) {
    Write-Host "Found installer: $installerScript" -ForegroundColor Green
    
    Write-Host "Installing .NET 8.0 Runtime (host) ..." -ForegroundColor Yellow
    & $installerScript -Runtime "dotnet" -Channel "8.0" -InstallDir $dotnetPath -NoPath

    Write-Host "Installing .NET 8.0 Windows Desktop Runtime ..." -ForegroundColor Yellow
    & $installerScript -Runtime "windowsdesktop" -Channel "8.0" -InstallDir $dotnetPath -NoPath

    if (Test-Path $dotnetExe) {
      $runtimes = & $dotnetExe --list-runtimes
      if ($runtimes -match "Microsoft.WindowsDesktop.App") {
        Write-Host "[OK] .NET Windows Desktop runtime installed" -ForegroundColor Green
      } else {
        Write-Host "[ERROR] Windows Desktop runtime not found after install" -ForegroundColor Red
        Write-Host "   Please re-run this script or install manually: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
        exit 1
      }
    } else {
      Write-Host "[ERROR] Installation failed. Please download .NET 8.0 Desktop Runtime manually:" -ForegroundColor Red
      Write-Host "   https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
      exit 1
    }
  } else {
    Write-Host "[ERROR] Installer script not found: $installerScript" -ForegroundColor Red
    Write-Host "   Please download dotnet-install.ps1 or .NET 8.0 Desktop Runtime manually" -ForegroundColor Yellow
    Write-Host "   https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
    exit 1
  }
}

Write-Host ""
Write-Host "Step 2: Configuring System PATH..." -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

if ($currentPath -like "*dotnet*") {
  Write-Host "[OK] .NET is already in system PATH" -ForegroundColor Green
} else {
  Write-Host "Adding .NET to system PATH..." -ForegroundColor Yellow
  $newPath = "$dotnetPath;$currentPath"
  [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
  Write-Host "[OK] .NET added to system PATH" -ForegroundColor Green
}

# Refresh current session PATH
$env:PATH = "$dotnetPath;$env:PATH"
Write-Host "[OK] Current session PATH refreshed" -ForegroundColor Green

Write-Host ""
Write-Host "Step 3: Verifying dotnet Command..." -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan

try {
  $runtimes = & $dotnetPath\dotnet.exe --list-runtimes
  if ($runtimes -match "Microsoft.WindowsDesktop.App") {
    Write-Host "[OK] dotnet command works and Windows Desktop runtime is present" -ForegroundColor Green
  } else {
    Write-Host "[ERROR] dotnet is present but Windows Desktop runtime is missing" -ForegroundColor Red
    Write-Host "   Re-run this script or install WindowsDesktop runtime manually" -ForegroundColor Yellow
  }
} catch {
  Write-Host "[ERROR] dotnet command failed: $_" -ForegroundColor Red
  Write-Host "   Try restarting PowerShell after this script completes" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "[OK] SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan
Write-Host "1. Run the installer:" -ForegroundColor White
Write-Host "   powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Or if issues persist, restart PowerShell and try again" -ForegroundColor White
Write-Host ""

Write-Host "IMPORTANT NOTES:" -ForegroundColor Yellow
Write-Host "-------------------------------------------" -ForegroundColor Yellow
Write-Host "* System PATH changes require a PowerShell restart to take effect" -ForegroundColor White
Write-Host "* Close all PowerShell windows and open a new one if dotnet still doesn't work" -ForegroundColor White
Write-Host "* The installer script will also work with the .NET now configured" -ForegroundColor White
Write-Host ""
