# Zerto Compliance Tool - Create Deployment Package
# Bundles all necessary files for distribution with auto-ZIP

param(
    [string]$OutputPath = (Join-Path $env:USERPROFILE "Documents\ComplianceTool_DeploymentPackage"),
    [string]$SourcePath = $PSScriptRoot,
    [switch]$SkipZip
)

Write-Host "Zerto Compliance Tool - Deployment Package Creator" -ForegroundColor Cyan
Write-Host "Version: 2.1.0" -ForegroundColor Cyan
Write-Host ""

 # Validate source
if (-not (Test-Path $SourcePath)) {
    Write-Host "ERROR: Source path not found: $SourcePath" -ForegroundColor Red
    exit 1
}

# Create output directory
if (Test-Path $OutputPath) {
    Write-Host "Removing existing output directory..." -ForegroundColor Yellow
    Remove-Item $OutputPath -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Create user-friendly subfolder structure
$appFolder = "$OutputPath\ComplianceTool"
New-Item -ItemType Directory -Path $appFolder -Force | Out-Null

Write-Host "Creating deployment package at: $OutputPath" -ForegroundColor Green
Write-Host "User-friendly structure: ComplianceTool\" -ForegroundColor Green
Write-Host ""

# Core application files (in main folder for easy access)
$coreFiles = @(
    @{ Name = "ZertoComplianceLauncher.exe"; Path = "$SourcePath\Launcher\bin\Release\net8.0-windows\"; Dest = $appFolder },
    @{ Name = "ZertoComplianceLauncher.dll"; Path = "$SourcePath\Launcher\bin\Release\net8.0-windows\"; Dest = $appFolder },
    @{ Name = "ZertoComplianceLauncher.deps.json"; Path = "$SourcePath\Launcher\bin\Release\net8.0-windows\"; Dest = $appFolder },
    @{ Name = "ZertoComplianceLauncher.runtimeconfig.json"; Path = "$SourcePath\Launcher\bin\Release\net8.0-windows\"; Dest = $appFolder },
    @{ Name = "Run-ComplianceAudit.ps1"; Path = "$SourcePath\"; Dest = $appFolder }
)

# Installation and documentation files
$docFiles = @(
    @{ Name = "Install-ZertoComplianceLauncher.ps1"; Path = "$SourcePath\Installer\"; Dest = $appFolder },
    @{ Name = "Uninstall-ZertoComplianceLauncher.ps1"; Path = "$SourcePath\Installer\"; Dest = $appFolder },
    @{ Name = "Setup-Environment.ps1"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "dotnet-install.ps1"; Path = "$SourcePath\Launcher\"; Dest = $appFolder },
    @{ Name = "icon.ico"; Path = "$SourcePath\Launcher\"; Dest = $appFolder },
    @{ Name = "DEPLOYMENT_GUIDE.html"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "QUICK_START.md"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "PRE-DEPLOYMENT_CHECKLIST.md"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "ZERTO-10-ARCHITECTURE.md"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "IMPORT-CERTIFICATE.md"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "UPGRADE.md"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "DEPLOYMENT_README.txt"; Path = "$SourcePath\"; Dest = $appFolder },
    @{ Name = "README.md"; Path = "$SourcePath\"; Dest = $appFolder }
)

$allFiles = $coreFiles + $docFiles
$success = 0
$skipped = 0

Write-Host "Packaging core application files:" -ForegroundColor Cyan
foreach ($file in $coreFiles) {
    $sourcePath = "$($file.Path)$($file.Name)"
    $destPath = "$($file.Dest)\$($file.Name)"
    
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $destPath -Force
        Write-Host "  [OK] $($file.Name)" -ForegroundColor Green
        $success++
    }
    else {
        Write-Host "  [SKIP] $($file.Name)" -ForegroundColor Yellow
        $skipped++
    }
}

Write-Host ""
Write-Host "Packaging documentation and installation files:" -ForegroundColor Cyan
foreach ($file in $docFiles) {
    $sourcePath = "$($file.Path)$($file.Name)"
    $destPath = "$($file.Dest)\$($file.Name)"
    
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $destPath -Force
        Write-Host "  [OK] $($file.Name)" -ForegroundColor Green
        $success++
    }
    else {
        Write-Host "  [SKIP] $($file.Name)" -ForegroundColor Yellow
        $skipped++
    }
}

Write-Host ""
Write-Host "Package Summary:" -ForegroundColor Cyan
Write-Host "  Files copied: $success" -ForegroundColor Green
Write-Host "  Files skipped: $skipped" -ForegroundColor Yellow

# Create manifest
$manifest = @{
    ToolName = "Zerto Compliance Tool"
    Version = "2.1.0"
    ReleaseDate = "December 25, 2025"
    PackageCreatedDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    OutputPath = $OutputPath
    Structure = "Single folder (ComplianceTool) with all files"
}

$manifest | ConvertTo-Json | Out-File "$appFolder\PACKAGE_MANIFEST.json" -Force
Write-Host "  [OK] PACKAGE_MANIFEST.json" -ForegroundColor Green

# Create a simple START_HERE.txt in root
# Write START_HERE.md (Markdown, ASCII-safe) and START_HERE.txt (plain ASCII)
$startHereMd = @"
## Zerto Compliance Tool - START HERE

Version 2.1.0

Important: run setup first. All PowerShell commands must be run as Administrator.

### Installation Steps

1. Extract the ZIP file
    - Right-click `ComplianceTool_DeploymentPackage.zip` -> Extract All
    - Choose where to extract (e.g., `C:\Temp`)

2. Open the folder and go into `ComplianceTool`
    - You should see: `Setup-Environment.ps1`, `ZertoComplianceLauncher.exe`, etc.

3. Run setup (do this first)

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
    ```

    - Ensures .NET 8.0 is installed and PATH is configured.
    - If you see errors, restart PowerShell and try again.

4. Run installer

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1
    ```

    - Installs to `C:\Program Files\ZertoCompliance`

5. Launch the application
    - Start Menu -> "Zerto Compliance Tool"
    - Or open: `C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe`

### Folder Contents

- `ZertoComplianceLauncher.exe` - Main GUI application
- `Run-ComplianceAudit.ps1` - Core PowerShell script
- `Setup-Environment.ps1` - .NET setup (run first)
- `Install-ZertoComplianceLauncher.ps1` - Installer script
- `DEPLOYMENT_GUIDE.html` - Full installation guide
- `QUICK_START.md` - 5-minute quick start
- `PRE-DEPLOYMENT_CHECKLIST.md` - Environment validation

### System Requirements

- Windows Server 2016+, Windows 10, or Windows 11
- Administrator rights
- .NET 8.0 (auto-installed by `Setup-Environment.ps1`)
- Network access to Zerto ZVMA
  - Port 443 for Zerto 10.x (Linux)
  - Port 9669 for Zerto 9.x (Windows)

### Quick Troubleshooting

- "dotnet is not recognized"
  - Run `Setup-Environment.ps1` first, restart PowerShell, try again.
- "PowerShell execution policy error"
  - Use `-ExecutionPolicy Bypass` as shown above.
- "Access denied" or "Not an administrator"
  - Run PowerShell as Administrator.

For more help: open `DEPLOYMENT_GUIDE.html` or email `aaron.lastoff@hpe.com`.
"@

$startHereText = @"
Zerto Compliance Tool - START HERE (v2.1.0)

IMPORTANT: Run setup first. All PowerShell commands must be run as Administrator.

INSTALLATION STEPS
------------------
1) Extract the ZIP: ComplianceTool_DeploymentPackage.zip -> Extract All -> choose a folder (e.g., C:\Temp)
2) Open the extracted folder and go into ComplianceTool
3) Run setup (do this first):
    powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
4) Run installer:
    powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1
5) Launch:
    Start Menu -> "Zerto Compliance Tool" OR C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe

CONTENTS
--------
- ZertoComplianceLauncher.exe (GUI)
- Run-ComplianceAudit.ps1 (core script)
- Setup-Environment.ps1 (dotnet setup)
- Install-ZertoComplianceLauncher.ps1 (installer)
- DEPLOYMENT_GUIDE.html, QUICK_START.md, PRE-DEPLOYMENT_CHECKLIST.md

REQUIREMENTS
------------
- Windows Server 2016+ / Windows 10 / Windows 11
- Administrator rights
- .NET 8.0 (auto-installed by Setup-Environment.ps1)
- Zerto ZVMA network access (443 for 10.x, 9669 for 9.x)

TROUBLESHOOTING
---------------
"dotnet is not recognized" -> run Setup-Environment.ps1, restart PowerShell
Execution policy issues -> use -ExecutionPolicy Bypass
Access denied -> run PowerShell as Administrator

Help: open DEPLOYMENT_GUIDE.html or email aaron.lastoff@hpe.com
"@

Set-Content -Path (Join-Path $OutputPath "START_HERE.md") -Value $startHereMd -Encoding UTF8
Set-Content -Path (Join-Path $OutputPath "START_HERE.txt") -Value $startHereText -Encoding ASCII
Write-Host "  [OK] START_HERE.md" -ForegroundColor Green
Write-Host "  [OK] START_HERE.txt" -ForegroundColor Green

Write-Host ""
Write-Host "Deployment package ready!" -ForegroundColor Green
Write-Host "Location: $OutputPath" -ForegroundColor Cyan

# Create ZIP file
if (-not $SkipZip) {
    Write-Host ""
    Write-Host "Creating ZIP archive..." -ForegroundColor Cyan
    
    $zipPath = "$OutputPath.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    try {
        Compress-Archive -Path "$OutputPath\*" -DestinationPath $zipPath -Force
        $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        Write-Host "  [OK] ZIP created successfully" -ForegroundColor Green
        Write-Host "  Location: $zipPath" -ForegroundColor Cyan
        Write-Host "  Size: $zipSize MB" -ForegroundColor Cyan
    }
    catch {
        Write-Host "  [ERROR] Failed to create ZIP: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Transfer ZIP file to target environment" -ForegroundColor White
Write-Host "  2. Extract ZIP file" -ForegroundColor White
Write-Host "  3. Read START_HERE.txt for instructions" -ForegroundColor White
Write-Host "  4. Open DEPLOYMENT_GUIDE.html for detailed setup" -ForegroundColor White
Write-Host ""
