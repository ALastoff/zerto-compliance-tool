param(
  [string]$InstallDir = "C:\\Program Files\\ZertoCompliance"
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$csproj   = Join-Path $repoRoot "Launcher\ZertoComplianceLauncher.csproj"
$publish  = Join-Path $repoRoot "Launcher\bin\Release\publish"

Write-Host "Building launcher..." -ForegroundColor Cyan
$null = New-Item -ItemType Directory -Force -Path $publish
& dotnet publish $csproj -c Release -o $publish
if ($LASTEXITCODE -ne 0) { Write-Error "dotnet publish failed"; exit 1 }

Write-Host "Installing..." -ForegroundColor Cyan
& "$PSScriptRoot\Install-ZertoComplianceLauncher.ps1" -SourceDir $publish -InstallDir $InstallDir
