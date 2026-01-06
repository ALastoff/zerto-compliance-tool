# Zerto Compliance Tool - PowerShell Profile Fix
# This script adds .NET to PATH and enables dotnet commands in PowerShell

$dotnetPath = "C:\Program Files\dotnet"

# Check if dotnet is already in PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*dotnet*") {
    Write-Host "Adding .NET to system PATH..." -ForegroundColor Yellow
    $newPath = "$dotnetPath;$currentPath"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    Write-Host "✅ .NET path added to system PATH" -ForegroundColor Green
} else {
    Write-Host "✅ .NET already in system PATH" -ForegroundColor Green
}

# Also refresh current session
$env:PATH = "$dotnetPath;$env:PATH"
Write-Host "✅ Current PowerShell session PATH refreshed" -ForegroundColor Green

Write-Host ""
Write-Host "Testing dotnet command:" -ForegroundColor Cyan
& "$dotnetPath\dotnet.exe" --version

Write-Host ""
Write-Host "✅ You can now use 'dotnet' command normally!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: You may need to restart PowerShell or any open terminals" -ForegroundColor Yellow
Write-Host "for the system PATH changes to take full effect." -ForegroundColor Yellow
