param(
  [string]$InstallDir = "C:\\Program Files\\ZertoCompliance"
)

# Requires admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "Please run this uninstaller as Administrator." -ForegroundColor Yellow
  exit 1
}

# Remove shortcuts
$desktopShortcut = "$env:PUBLIC\Desktop\Zerto Compliance Tool.lnk"
$startMenuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zerto"
$startShortcut = Join-Path $startMenuDir "Zerto Compliance Tool.lnk"

foreach ($p in @($desktopShortcut, $startShortcut)) {
  if (Test-Path $p) { Remove-Item $p -Force }
}

# Remove install dir
if (Test-Path $InstallDir) {
  Remove-Item $InstallDir -Recurse -Force
}

# Remove scheduled task (if exists)
try {
  schtasks.exe /Delete /TN "ZertoComplianceScan" /F | Out-Null
} catch {}

Write-Host "Uninstalled Zerto Compliance Launcher." -ForegroundColor Green
