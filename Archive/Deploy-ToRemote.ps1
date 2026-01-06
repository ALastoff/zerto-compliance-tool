# Zerto Compliance Tool - Direct Deployment Script
# Run this on the REMOTE machine to install all files directly from source

param(
    [string]$SourceShare = "\\\\<YOUR-SHARE>\\CompliancePkg",
    [string]$InstallPath = "C:\\Program Files\\ZertoCompliance",
    [string]$PackageFolderName = "ComplianceTool_DeploymentPackage",
    [string]$PackageSubfolder = "ComplianceTool"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ZERTO COMPLIANCE TOOL - DIRECT DEPLOY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Please run as Administrator" -ForegroundColor Red
    exit 1
}

# Create install directory
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
Write-Host "Install path: $InstallPath" -ForegroundColor Green

# Copy launcher files directly
Write-Host ""
Write-Host "Copying launcher files..." -ForegroundColor Cyan

$files = @(
    "ZertoComplianceLauncher.exe",
    "ZertoComplianceLauncher.dll",
    "ZertoComplianceLauncher.deps.json",
    "ZertoComplianceLauncher.runtimeconfig.json"
)

# Copy core launcher files
foreach ($file in $files) {
    $sourcePath = "$SourceShare\$PackageFolderName\$PackageSubfolder\$file"
    $destPath = "$InstallPath\$file"
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $destPath -Force
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] $file not found at $sourcePath" -ForegroundColor Red
    }
}

# Copy compliance audit script (new name preferred, legacy fallback)
$newScript = "$SourceShare\$PackageFolderName\$PackageSubfolder\Run-ComplianceAudit.ps1"
$legacyScript = "$SourceShare\$PackageFolderName\$PackageSubfolder\ZertoComplianceNew.ps1"
if (Test-Path $newScript) {
    Copy-Item $newScript -Destination (Join-Path $InstallPath "Run-ComplianceAudit.ps1") -Force
    Write-Host "  [OK] Run-ComplianceAudit.ps1" -ForegroundColor Green
} elseif (Test-Path $legacyScript) {
    Copy-Item $legacyScript -Destination (Join-Path $InstallPath "Run-ComplianceAudit.ps1") -Force
    Write-Host "  [OK] ZertoComplianceNew.ps1 -> Run-ComplianceAudit.ps1 (legacy)" -ForegroundColor Yellow
} else {
    Write-Host "  [ERROR] Compliance audit script not found in source package" -ForegroundColor Red
}

Write-Host ""
Write-Host "Files in install directory:" -ForegroundColor Cyan
Get-ChildItem $InstallPath | Where-Object { $_.Name -like "ZertoCompliance*" } | Select-Object Name, Length | Format-Table -AutoSize

Write-Host ""
Write-Host "Creating shortcuts..." -ForegroundColor Cyan

# Desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$desktopPath = "$env:PUBLIC\Desktop\Zerto Compliance Tool.lnk"
$shortcut = $WshShell.CreateShortcut($desktopPath)
$shortcut.TargetPath = "$InstallPath\ZertoComplianceLauncher.exe"
$shortcut.WorkingDirectory = $InstallPath
$shortcut.IconLocation = "$InstallPath\ZertoComplianceLauncher.exe"
$shortcut.Save()
Write-Host "  [OK] Desktop shortcut created" -ForegroundColor Green

# Start Menu shortcut
$startMenuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zerto"
New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
$menuPath = "$startMenuDir\Zerto Compliance Tool.lnk"
$menuShortcut = $WshShell.CreateShortcut($menuPath)
$menuShortcut.TargetPath = "$InstallPath\ZertoComplianceLauncher.exe"
$menuShortcut.WorkingDirectory = $InstallPath
$menuShortcut.IconLocation = "$InstallPath\ZertoComplianceLauncher.exe"
$menuShortcut.Save()
Write-Host "  [OK] Start Menu shortcut created" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "[OK] DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Launch the application:" -ForegroundColor Cyan
Write-Host "  & '$InstallPath\ZertoComplianceLauncher.exe'" -ForegroundColor Yellow
Write-Host ""
