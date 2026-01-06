# Zerto Compliance Launcher Bootstrapper (PowerShell)
# Checks for .NET 8 Desktop Runtime and launches the tool

param(
    [string]$LauncherPath = (Join-Path $PSScriptRoot "ZertoComplianceLauncher.exe")
)

function Test-DotNetRuntime {
    param([string]$MinVersion = "8.0")
    
    try {
        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        if (-not $dotnet) {
            Write-Warning "dotnet command not found in PATH"
            return $false
        }
        
        $runtimes = & dotnet --list-runtimes 2>&1 | Out-String
        if ($runtimes -match "Microsoft\.WindowsDesktop\.App $MinVersion") {
            Write-Host ".NET Desktop Runtime $MinVersion detected." -ForegroundColor Green
            return $true
        }
        
        Write-Warning ".NET Desktop Runtime $MinVersion not found"
        return $false
    }
    catch {
        Write-Warning "Failed to check .NET runtime: $($_.Exception.Message)"
        return $false
    }
}

function Show-InstallPrompt {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " .NET 8 Desktop Runtime NOT FOUND" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The Zerto Compliance Launcher requires .NET 8 Desktop Runtime."
    Write-Host ""
    Write-Host "Download from: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Cyan
    Write-Host "Look for: '.NET Desktop Runtime 8.0.x' (Windows x64)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "After installation, run this bootstrapper again."
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Open download page now? (Y/N)"
    if ($choice -eq 'Y' -or $choice -eq 'y') {
        Start-Process "https://dotnet.microsoft.com/download/dotnet/8.0"
    }
    
    exit 1
}

# Main logic
Write-Host "Zerto Compliance Tool Bootstrapper" -ForegroundColor Green

if (-not (Test-Path $LauncherPath)) {
    Write-Error "Launcher not found: $LauncherPath"
    Write-Host "Please run the installer first." -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "Checking for .NET Desktop Runtime..." -ForegroundColor Cyan

if (-not (Test-DotNetRuntime -MinVersion "8.0")) {
    Show-InstallPrompt
}

Write-Host "Launching Zerto Compliance Tool..." -ForegroundColor Green
Start-Process $LauncherPath
exit 0
