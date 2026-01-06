param(
  [string]$PfxPath,
  [string]$PfxPassword,
  [string]$ExePath = "C:\\Program Files\\ZertoCompliance\\ZertoComplianceLauncher.exe",
  [string]$Ps1Path = "C:\\Program Files\\ZertoCompliance\\Run-ComplianceAudit.ps1",
  [string]$TimestampUrl = "http://timestamp.digicert.com",
  [string]$CertThumbprint,
  [switch]$MachineStore
)

# Helper: Write status
function Write-Status($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# Validate inputs
if (-not (Test-Path $ExePath)) { Write-Error "EXE not found: $ExePath"; exit 1 }
if (-not (Test-Path $Ps1Path)) { Write-Error "PowerShell script not found: $Ps1Path"; exit 1 }

# Load certificate for PS1 signing
$cert = $null
if ($PfxPath -and (Test-Path $PfxPath)) {
  Write-Status "Importing PFX certificate: $PfxPath" 'Cyan'
  $sec = if ($PfxPassword) { (ConvertTo-SecureString $PfxPassword -AsPlainText -Force) } else { Read-Host -AsSecureString "Enter PFX password" }
  $storePath = if ($MachineStore) { 'Cert:\LocalMachine\My' } else { 'Cert:\CurrentUser\My' }
  Import-PfxCertificate -FilePath $PfxPath -Password $sec -CertStoreLocation $storePath | Out-Null
  $cert = Get-ChildItem $storePath | Sort-Object NotAfter -Descending | Select-Object -First 1
} elseif ($CertThumbprint) {
  Write-Status "Using certificate from store: Thumbprint=$CertThumbprint" 'Cyan'
  $storePath = if ($MachineStore) { 'Cert:\LocalMachine\My' } else { 'Cert:\CurrentUser\My' }
  $cert = Get-ChildItem $storePath | Where-Object { $_.Thumbprint -eq $CertThumbprint }
}

if (-not $cert) { Write-Error "No certificate available for PS1 signing. Provide -PfxPath or -CertThumbprint."; exit 1 }

# Sign PowerShell script (Authenticode)
Write-Status "Signing PowerShell script: $Ps1Path" 'Yellow'
$sig = Set-AuthenticodeSignature -FilePath $Ps1Path -Certificate $cert -TimestampServer $TimestampUrl -HashAlgorithm SHA256
if ($sig.Status -ne 'Valid') {
  Write-Error "PS1 signing failed: $($sig.StatusMessage)"; exit 1
}
Write-Status "PS1 signed successfully: $($sig.SignerCertificate.Subject)" 'Green'

# Sign EXE using signtool (requires Windows SDK)
Write-Status "Signing EXE: $ExePath" 'Yellow'
$signTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if (-not $signTool) {
  Write-Warning "signtool.exe not found. Install Windows SDK (App Installer, Visual Studio build tools)."
  Write-Warning "Skipping EXE signing. PS1 was signed."
} else {
  if ($PfxPath) {
    & $signTool.Source -q sign /f "$PfxPath" /p "$PfxPassword" /fd SHA256 /tr $TimestampUrl /td SHA256 "$ExePath" | Out-Null
  } elseif ($CertThumbprint) {
    & $signTool.Source -q sign /sha1 $CertThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 "$ExePath" | Out-Null
  }
  Write-Status "EXE signed successfully." 'Green'
}

# Verify signatures
Write-Status "Verifying signatures..." 'Cyan'
(Get-AuthenticodeSignature -FilePath $Ps1Path) | Format-List Status, StatusMessage, SignerCertificate | Out-Host
Write-Status "Done." 'Green'
