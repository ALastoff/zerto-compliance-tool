param(
  [string]$SourceDir,
  [string]$InstallDir = "C:\\Program Files\\ZertoCompliance",
  [string]$PfxPath,
  [string]$PfxPassword,
  [string]$CertThumbprint,
  [switch]$MachineStore
)

# Requires admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "Please run this installer as Administrator." -ForegroundColor Yellow
  exit 1
}

# Resolve source dir - NOW WORKS FROM DEPLOYMENT PACKAGE!
if (-not $SourceDir) {
  # First, try current directory (when running from extracted package)
  $SourceDir = (Split-Path -Parent $PSCommandPath)

  # Check common development publish locations
  $candidateDirs = @(
    $SourceDir,
    (Join-Path (Split-Path -Parent $PSCommandPath) "..\Launcher\bin\Release\publish"),
    (Join-Path (Split-Path -Parent $PSCommandPath) "..\Launcher\bin\Release\net8.0-windows\publish"),
    (Join-Path (Split-Path -Parent $PSCommandPath) "..\Launcher\bin\Release\net8.0-windows"),
    (Join-Path (Split-Path -Parent $PSCommandPath) "..\Launcher\bin\Release\net6.0-windows")
  )

  $found = $false
  foreach ($dir in $candidateDirs) {
    if (Test-Path (Join-Path $dir "ZertoComplianceLauncher.exe")) {
      $SourceDir = $dir
      $found = $true
      break
    }
  }

  # If not found, attempt to build from source if dotnet SDK is available
  if (-not $found) {
    $repoRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $csproj = Join-Path $repoRoot "Launcher\ZertoComplianceLauncher.csproj"
    $publishDir = Join-Path $repoRoot "Launcher\bin\Release\publish"
    if (Test-Path $csproj) {
      try {
        $dotnetVersion = (& dotnet --version) 2>$null
      } catch {
        $dotnetVersion = $null
      }
      if ($dotnetVersion) {
        Write-Host "Launcher EXE not found. Building from source using dotnet $dotnetVersion..." -ForegroundColor Yellow
        $null = New-Item -ItemType Directory -Force -Path $publishDir
        & dotnet publish $csproj -c Release -o $publishDir
        if ($LASTEXITCODE -ne 0) {
          Write-Error "dotnet publish failed. Please install .NET SDK or build manually, then re-run the installer."; exit 1
        }
        if (Test-Path (Join-Path $publishDir "ZertoComplianceLauncher.exe")) {
          $SourceDir = $publishDir
          $found = $true
        }
      }
    }
  }
}

Write-Host "Source: $SourceDir" -ForegroundColor Cyan
Write-Host "Install: $InstallDir" -ForegroundColor Cyan

$exe = Join-Path $SourceDir "ZertoComplianceLauncher.exe"
$dll = Join-Path $SourceDir "ZertoComplianceLauncher.dll"
$deps = Join-Path $SourceDir "ZertoComplianceLauncher.deps.json"
$runtimecfg = Join-Path $SourceDir "ZertoComplianceLauncher.runtimeconfig.json"
$ps1 = Join-Path $SourceDir "Run-ComplianceAudit.ps1"

# If PS1 not in source dir, try parent directories
if (-not (Test-Path $ps1)) {
  $ps1 = Join-Path (Split-Path -Parent $PSCommandPath) "Run-ComplianceAudit.ps1"
}
if (-not (Test-Path $ps1)) {
  $ps1 = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "Run-ComplianceAudit.ps1"
}

# Fallback to legacy script name if new not found
if (-not (Test-Path $ps1)) {
  $ps1 = Join-Path $SourceDir "ZertoComplianceNew.ps1"
  if (-not (Test-Path $ps1)) { $ps1 = Join-Path (Split-Path -Parent $PSCommandPath) "ZertoComplianceNew.ps1" }
  if (-not (Test-Path $ps1)) { $ps1 = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "ZertoComplianceNew.ps1" }
}

if (-not (Test-Path $exe)) {
  Write-Error "Launcher EXE not found at $exe"
  Write-Host ""; Write-Host "To install from SOURCE, build the launcher then re-run this installer:" -ForegroundColor Yellow
  Write-Host "  dotnet publish \"..\\Launcher\\ZertoComplianceLauncher.csproj\" -c Release -o \"..\\Launcher\\bin\\Release\\publish\"" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File .\\Install-ZertoComplianceLauncher.ps1 -SourceDir ..\\Launcher\\bin\\Release\\publish" -ForegroundColor Yellow
  Write-Host ""; Write-Host "Alternatively, download the Deployment Package release which includes the EXE." -ForegroundColor Yellow
  exit 1
}
if (-not (Test-Path $dll)) { Write-Error "Launcher DLL not found at $dll"; exit 1 }
if (-not (Test-Path $deps)) { Write-Error "Launcher deps.json not found at $deps"; exit 1 }
if (-not (Test-Path $runtimecfg)) { Write-Error "Launcher runtimeconfig.json not found at $runtimecfg"; exit 1 }
if (-not (Test-Path $ps1)) { Write-Error "PowerShell script not found at $ps1"; exit 1 }

Write-Host "Found EXE: $exe" -ForegroundColor Green
Write-Host "Found DLL: $dll" -ForegroundColor Green
Write-Host "Found deps.json: $deps" -ForegroundColor Green
Write-Host "Found runtimeconfig.json: $runtimecfg" -ForegroundColor Green
Write-Host "Found PS1: $ps1" -ForegroundColor Green

# Create install dir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Copy files
Copy-Item $exe -Destination $InstallDir -Force
Copy-Item $dll -Destination $InstallDir -Force
Copy-Item $deps -Destination $InstallDir -Force
Copy-Item $runtimecfg -Destination $InstallDir -Force
Copy-Item $ps1 -Destination $InstallDir -Force

# Optional: copy README
$readmeLocations = @(
  (Join-Path $SourceDir "README.md"),
  (Join-Path (Split-Path -Parent $PSCommandPath) "README.md"),
  (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "README.md")
)
foreach ($readme in $readmeLocations) {
  if (Test-Path $readme) { 
    Copy-Item $readme -Destination $InstallDir -Force
    break
  }
}

# Optional: copy bootstrapper
$bootstrapperBat = Join-Path $SourceDir "ZertoComplianceLauncher.bat"
if (-not (Test-Path $bootstrapperBat)) {
  $bootstrapperBat = Join-Path (Split-Path -Parent $PSCommandPath) "ZertoComplianceLauncher.bat"
}
if (Test-Path $bootstrapperBat) { Copy-Item $bootstrapperBat -Destination $InstallDir -Force }

$bootstrapperPs1 = Join-Path $SourceDir "ZertoComplianceLauncher-Bootstrapper.ps1"
if (-not (Test-Path $bootstrapperPs1)) {
  $bootstrapperPs1 = Join-Path (Split-Path -Parent $PSCommandPath) "ZertoComplianceLauncher-Bootstrapper.ps1"
}
if (Test-Path $bootstrapperPs1) { Copy-Item $bootstrapperPs1 -Destination $InstallDir -Force }

# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$shortcutPath = "$env:PUBLIC\Desktop\Zerto Compliance Tool.lnk"
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $InstallDir "ZertoComplianceLauncher.exe"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.IconLocation = Join-Path $InstallDir "ZertoComplianceLauncher.exe"
$shortcut.Save()

# Create Start Menu shortcut
$startMenuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zerto"
New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
$startShortcutPath = Join-Path $startMenuDir "Zerto Compliance Tool.lnk"
$startShortcut = $WshShell.CreateShortcut($startShortcutPath)
$startShortcut.TargetPath = Join-Path $InstallDir "ZertoComplianceLauncher.exe"
$startShortcut.WorkingDirectory = $InstallDir
$startShortcut.IconLocation = Join-Path $InstallDir "ZertoComplianceLauncher.exe"
$startShortcut.Save()

Write-Host ""
Write-Host "✅ Installed successfully to $InstallDir" -ForegroundColor Green
Write-Host "✅ Shortcut created on Public Desktop" -ForegroundColor Green
Write-Host "✅ Shortcut created in Start Menu" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Launch 'Zerto Compliance Tool' from Start Menu or Desktop" -ForegroundColor Cyan

# Optional signing step
if ($PfxPath -or $CertThumbprint) {
  Write-Host "Signing binaries with provided certificate..." -ForegroundColor Yellow
  $signScript = Join-Path (Split-Path -Parent $PSCommandPath) "Sign-ZertoCompliance.ps1"
  if (Test-Path $signScript) {
    & $signScript -PfxPath $PfxPath -PfxPassword $PfxPassword -CertThumbprint $CertThumbprint -MachineStore:$MachineStore -ExePath (Join-Path $InstallDir "ZertoComplianceLauncher.exe") -Ps1Path (Join-Path $InstallDir "ZertoComplianceNew.ps1")
  } else {
    Write-Warning "Signing script not found: $signScript"
  }
}
