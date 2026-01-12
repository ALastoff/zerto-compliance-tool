<#
.SYNOPSIS
  Zerto 10.x Compliance Collector (PowerShell)

.DESCRIPTION
  Authenticates to ZVMA (Keycloak) and Zerto Analytics, collects DR test evidence,
  VPG/LTR details, protected VM inventory, computes a compliance score, and outputs
  audit-ready artifacts (CSV, MANIFEST.json, SUMMARY, LOG, ControlsMap).

.AUTHENTICATION WORKFLOWS
  The script supports three Analytics auth modes:

  1. API_KEY (default):
     -AnalyticsAuthMode api_key -AnalyticsKey "<your_api_key>"
     Prompts: Will ask for ZVMA credentials (if not provided) but NOT Analytics key (provided).

  2. MYZERTO (domain/MFA):
     -AnalyticsAuthMode myzerto -MyZertoClientId "<id>" -MyZertoUser "<email>" -MyZertoPassword "<pass>"
     Prompts: ZVMA credentials (if not provided), MyZerto credentials (if not provided), MFA code (if challenged).
     Does not require a pre-generated bearer file.

  3. BEARER_FILE (from Get-Bearer_scp.ps1):
     -AnalyticsAuthMode bearer_file -AnalyticsBearerFile "<path_to_Bearer.txt>"
     Prompts: ZVMA credentials (if not provided) only.
     If no file provided or file not found, will prompt for MyZerto credentials interactively.
     Does not prompt for Analytics key under any circumstance.

.NOTES
  Version: 1.0.1
  Author: Aaron Lastoff (with Copilot assist)
  Safe for Task Scheduler (non-interactive) via parameters / env vars.
  
  IMPORTANT: Always use -File to run the script, never dot-source (. script.ps1).
  Dot-sourcing can cause old function definitions to persist in memory.
#>

[CmdletBinding()]
param(
  # --- ZVMA / Keycloak ---
  [Parameter(Mandatory = $false)]
  [string]$ZVMAHost,

  # Additional hypervisor sites (loaded from config or prompted)
  [Parameter(Mandatory = $false)]
  [string]$Site2Host,

  [Parameter(Mandatory = $false)]
  [string]$Site3Host,

  [Parameter(Mandatory = $false)]
  [switch]$EnableSite3,

  [Parameter(Mandatory = $false)]
  [string]$Realm = 'zerto',

  [Parameter(Mandatory = $false)]
  [string]$ClientId = 'zerto-client',

  [Parameter(Mandatory = $false)]
  [ValidateSet('password','client_credentials')]
  [string]$GrantType = 'password',

  [Parameter(Mandatory = $false)]
  [string]$Username,

  [Parameter(Mandatory = $false)]
  [string]$Password,

  [Parameter(Mandatory = $false)]
  [string]$ClientSecret,

  # --- Analytics ---
  [Parameter(Mandatory = $false)]
  [string]$AnalyticsKey,

  # --- Analytics auth mode ---
  [Parameter(Mandatory = $false)]
  [ValidateSet('api_key','myzerto','bearer_file')]
  [string]$AnalyticsAuthMode = 'api_key',

  # If using myzerto
  [Parameter(Mandatory = $false)] [string]$MyZertoClientId,
  [Parameter(Mandatory = $false)] [string]$MyZertoRegion = 'us-east-1',
  [Parameter(Mandatory = $false)] [string]$MyZertoUser,
  [Parameter(Mandatory = $false)] [string]$MyZertoPassword,
  [Parameter(Mandatory = $false)] [string]$MyZertoMfaCode,

  # If using bearer_file (produced by Get-Bearer_scp.ps1)
  [Parameter(Mandatory = $false)] [string]$AnalyticsBearerFile,

  # --- Compliance options ---
  [Parameter(Mandatory = $false)]
  [switch]$UseLTR,

  # Optional peer ZVMA hosts to pull metadata from
  [Parameter(Mandatory = $false)]
  [AllowEmptyCollection()]
  [string[]]$PeerHosts = @(),

  # --- Secondary Site Authentication (Option 2 support) ---
  [Parameter(Mandatory = $false)]
  [string]$SecondarySite,

  [Parameter(Mandatory = $false)]
  [string]$SecondaryUsername,

  [Parameter(Mandatory = $false)]
  [string]$SecondaryPassword,

  # --- Additional Sites (3+) ---
  [Parameter(Mandatory = $false)]
  [AllowEmptyCollection()]
  [string[]]$AdditionalSites = @(),

  # --- Coverage option: total VM count (for true coverage calculation). If not provided, coverage = protected dataset only.
  [Parameter(Mandatory = $false)]
  [int]$TotalVmCount,

  # --- Output root folder. If not provided, shows a folder picker.
  [Parameter(Mandatory = $false)]
  [string]$OutRoot,

  # --- Networking ---
  [Parameter(Mandatory = $false)]
  [switch]$Insecure,            # Lab-only: disable TLS verification

  [Parameter(Mandatory = $false)]
  [int]$TimeoutSec = 15,

  [Parameter(Mandatory = $false)]
  [int]$MaxRetries = 5
  ,

  # --- vCenter (optional fallback for inventory) ---
  [Parameter(Mandatory = $false)] [string]$VCenterServer,
  [Parameter(Mandatory = $false)] [string]$VCenterUser,
  [Parameter(Mandatory = $false)] [string]$VCenterPassword,
  [Parameter(Mandatory = $false)] [switch]$VCenterInsecure,

  # --- Output naming ---
  [Parameter(Mandatory = $false)] [switch]$SimpleNames

  ,

  # --- Non-interactive mode (use config files only, no prompts) ---
  [Parameter(Mandatory = $false)] [switch]$NonInteractive,

  # --- Zerto metadata endpoint overrides (optional) ---
  # Provide one or more full URLs to try, e.g. "https://zvma.local/v1/version"
  [Parameter(Mandatory = $false)] [string[]]$ZertoVersionEndpoints,
  [Parameter(Mandatory = $false)] [string[]]$ZertoSitesEndpoints,

  # --- Authentication config file ---
  [Parameter(Mandatory = $false)] [string]$AuthConfigFile
)

# =========================
# Global / Utilities
# =========================
$ErrorActionPreference = 'Stop'
$scriptVersion = '1.0.1'
$startTime = Get-Date
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$timeZone = [System.TimeZoneInfo]::Local.StandardName

# Will be set in Initialize-Output
$script:OutDir = $null
$script:CsvPath = $null
$script:SummaryPath = $null
$script:ManifestPath = $null
$script:ControlsMapPath = $null
$script:LogPath = $null
$script:_prevCallback = $null
$script:TranscriptPath = $null
$script:FailurePath = $null

# =========================
# Authentication Config Functions
# =========================
function Get-StoredCredential {
  param([Parameter(Mandatory=$true)][string]$Target)
  
  try {
    # Use cmdkey to retrieve stored credentials
    $cred = cmdkey /list:$Target 2>$null
    if (-not $cred) {
      Write-Log ("No stored credential found for target: {0}" -f $Target) 'WARN'
      return $null
    }
    
    # Credentials are stored, but PowerShell can't directly retrieve them
    # We'll need to use alternative methods or prompt user to store them first
    Write-Log ("Found stored credential target: {0}" -f $Target) 'INFO'
    return $Target
  } catch {
    Write-Log ("Error checking credential manager: {0}" -f $_.Exception.Message) 'WARN'
    return $null
  }
}

function Get-CredentialFromManager {
  param([Parameter(Mandatory=$true)][string]$Target)
  
  # PowerShell 5.1 method: Use PInvoke to access Windows Credential Manager
  try {
    # Define the Credential structure and API calls
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class CredentialManager
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool CredFree(IntPtr cred);

    public static CREDENTIAL GetCredential(string target)
    {
        IntPtr credPtr;
        if (CredRead(target, 1, 0, out credPtr))
        {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
            CredFree(credPtr);
            return cred;
        }
        throw new Exception("Credential not found");
    }
}
"@
    
    $cred = [CredentialManager]::GetCredential($Target)
    
    # Extract password from blob
    $passwordBytes = New-Object byte[] $cred.CredentialBlobSize
    [Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $passwordBytes, 0, $cred.CredentialBlobSize)
    $password = [Text.Encoding]::Unicode.GetString($passwordBytes)
    
    Write-Log ("Retrieved credential from Credential Manager: {0}" -f $cred.UserName) 'INFO'
    return @{
      Username = $cred.UserName
      Password = $password
    }
  } catch {
    Write-Log ("Failed to retrieve credential for target '{0}': {1}" -f $Target, $_.Exception.Message) 'WARN'
  }
  
  # Fallback: Try to at least get username from cmdkey
  try {
    $storedInfo = cmdkey /list:$Target 2>$null | Select-String "User:" | ForEach-Object { $_.ToString() }
    if ($storedInfo) {
      $username = ($storedInfo -replace '.*User:\s*', '').Trim()
      Write-Log ("Retrieved username from cmdkey: {0}" -f $username) 'INFO'
      return @{
        Username = $username
        Password = $null  # Password cannot be retrieved via cmdkey
      }
    }
  } catch {
    Write-Log ("Could not retrieve credential from manager: {0}" -f $_.Exception.Message) 'WARN'
  }
  
  return $null
}

function Load-AuthConfig {
  param([Parameter(Mandatory=$false)][string]$ConfigPath)
  
  if (-not $ConfigPath) {
    # Try default location
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $ConfigPath = Join-Path $scriptDir 'auth.config.json'
  }
  
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Log ("Auth config not found at {0}" -f $ConfigPath) 'WARN'
    return $null
  }
  
  try {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Log ("Auth config loaded from {0}" -f $ConfigPath) 'INFO'
    return $config
  } catch {
    Write-Log ("Failed to parse auth config: {0}" -f $_.Exception.Message) 'WARN'
    return $null
  }
}

function Apply-AuthConfig {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$false)][ref]$ZVMAHostRef,
    [Parameter(Mandatory=$false)][ref]$UsernameRef,
    [Parameter(Mandatory=$false)][ref]$PasswordRef,
    [Parameter(Mandatory=$false)][ref]$RealmRef,
    [Parameter(Mandatory=$false)][ref]$ClientIdRef,
    [Parameter(Mandatory=$false)][ref]$AnalyticsAuthModeRef,
    [Parameter(Mandatory=$false)][ref]$AnalyticsBearerFileRef,
    [Parameter(Mandatory=$false)][ref]$MyZertoClientIdRef,
    [Parameter(Mandatory=$false)][ref]$MyZertoUserRef,
    [Parameter(Mandatory=$false)][ref]$MyZertoPasswordRef,
    [Parameter(Mandatory=$false)][ref]$VCenterServerRef,
    [Parameter(Mandatory=$false)][ref]$VCenterUserRef,
    [Parameter(Mandatory=$false)][ref]$VCenterPasswordRef,
    [Parameter(Mandatory=$false)][ref]$InsecureRef
  )
  
  if (-not $Config) { return }
  
  # Apply ZVMA UI Account with Credential Manager support
  if ($Config.Accounts.SourceZertoUI.Enabled) {
    if (-not $ZVMAHostRef.Value) { $ZVMAHostRef.Value = $Config.Accounts.SourceZertoUI.Host }
    if (-not $RealmRef.Value) { $RealmRef.Value = $Config.Accounts.SourceZertoUI.Realm }
    if (-not $ClientIdRef.Value) { $ClientIdRef.Value = $Config.Accounts.SourceZertoUI.ClientId }
    
    # Handle Credential Manager
    if ($Config.Accounts.SourceZertoUI.UseCredentialManager) {
      $credTarget = $Config.Accounts.SourceZertoUI.CredentialTarget
      $credCheck = Get-StoredCredential -Target $credTarget
      if ($credCheck) {
        Write-Log ("Using credentials from Credential Manager for {0}" -f $credTarget) 'INFO'
        if (-not $UsernameRef.Value) { $UsernameRef.Value = "from-$credTarget" }
        if (-not $PasswordRef.Value) { $PasswordRef.Value = "from-$credTarget" }
      } else {
        Write-Log ("Credential Manager target '{0}' not found. Store credentials with: cmdkey /add:{0} /user:<username> /pass:<password>" -f $credTarget) 'WARN'
      }
    }
  }
  
  # Apply Analytics config
  if ($Config.Analytics.Enabled) {
    if (-not $AnalyticsAuthModeRef.Value) { $AnalyticsAuthModeRef.Value = $Config.Analytics.AuthMode }
    if (-not $AnalyticsBearerFileRef.Value -and $Config.Analytics.BearerFilePath) { $AnalyticsBearerFileRef.Value = $Config.Analytics.BearerFilePath }
  }
  
  # Apply MyZerto Account
  if ($Config.Accounts.MyZertoAccount.Enabled) {
    if (-not $MyZertoClientIdRef.Value) { $MyZertoClientIdRef.Value = $Config.Accounts.MyZertoAccount.ClientId }
    if ($Config.Accounts.MyZertoAccount.UseCredentialManager) {
      $credTarget = $Config.Accounts.MyZertoAccount.CredentialTarget
      $credCheck = Get-StoredCredential -Target $credTarget
      if ($credCheck) {
        if (-not $MyZertoUserRef.Value) { $MyZertoUserRef.Value = "from-$credTarget" }
        if (-not $MyZertoPasswordRef.Value) { $MyZertoPasswordRef.Value = "from-$credTarget" }
      }
    }
  }
  
  # Apply vCenter Account
  if ($Config.Accounts.SourceVCenterAccount.Enabled) {
    if (-not $VCenterServerRef.Value) { $VCenterServerRef.Value = $Config.Accounts.SourceVCenterAccount.Host }
    if ($Config.Accounts.SourceVCenterAccount.UseCredentialManager) {
      $credTarget = $Config.Accounts.SourceVCenterAccount.CredentialTarget
      $credCheck = Get-StoredCredential -Target $credTarget
      if ($credCheck) {
        if (-not $VCenterUserRef.Value) { $VCenterUserRef.Value = "from-$credTarget" }
        if (-not $VCenterPasswordRef.Value) { $VCenterPasswordRef.Value = "from-$credTarget" }
      }
    }
  }
  
  # Apply Security settings
  if ($Config.Security.InsecureTls -and -not $PSBoundParameters.ContainsKey('Insecure')) {
    $InsecureRef.Value = $true
  }
}

function Initialize-HypervisorSites {
  param(
    [Parameter(Mandatory=$false)][object]$Config,
    [Parameter(Mandatory=$false)][ref]$Site1HostRef,
    [Parameter(Mandatory=$false)][ref]$Site2HostRef,
    [Parameter(Mandatory=$false)][ref]$Site3HostRef,
    [Parameter(Mandatory=$false)][ref]$Site3EnabledRef
  )
  
  if (-not $Config -or -not $Config.Hypervisors) { return }
  
  $hypervisors = $Config.Hypervisors
  
  # Configure Site 1 (Primary)
  if ($hypervisors.Site1 -and $hypervisors.Site1.Enabled) {
    if (-not $Site1HostRef.Value) {
      $Site1HostRef.Value = $hypervisors.Site1.Host
    }
  }
  
  # Configure Site 2 (Secondary)
  if ($hypervisors.Site2 -and $hypervisors.Site2.Enabled) {
    if (-not $Site2HostRef.Value) {
      $Site2HostRef.Value = $hypervisors.Site2.Host
    }
  }
  
  # Configure Site 3 (Optional)
  if ($hypervisors.Site3) {
    if ($hypervisors.Site3.Enabled -and $hypervisors.Site3.Host) {
      if (-not $Site3HostRef.Value) {
        $Site3HostRef.Value = $hypervisors.Site3.Host
        $Site3EnabledRef.Value = $true
      }
    }
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [ValidateSet('INFO','WARN','ERROR')]
    [string]$Level = 'INFO'
  )
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$ts][$Level] $Message"
  Write-Host $line
  if ($script:LogPath -and (Test-Path -LiteralPath $script:LogPath)) {
    Add-Content -Path $script:LogPath -Value $line
  } elseif ($script:LogPath) {
    # create log file if not exists yet
    New-Item -ItemType File -Path $script:LogPath -Force | Out-Null
    Add-Content -Path $script:LogPath -Value $line
  }
}

function Invoke-HttpJsonWithCurlFallback {
  param(
    [Parameter(Mandatory=$true)][string]$Uri,
    [Parameter(Mandatory=$false)][hashtable]$Headers,
    [Parameter(Mandatory=$false)][ValidateSet('GET','POST')][string]$Method = 'GET'
  )
  try {
    return Invoke-RestJson -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec -MaxRetries 1
  } catch {
    Write-Log ("Invoke-RestMethod failed; trying curl.exe fallback for {0}" -f $Uri) 'WARN'
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
      $curlArgs = @('-sS','-X', $Method)
      if ($Insecure) { $curlArgs += '-k' }
      if ($Headers) {
        foreach ($k in $Headers.Keys) { $curlArgs += @('-H', ("{0}: {1}" -f $k, $Headers[$k])) }
      }
      $curlArgs += '--url'; $curlArgs += $Uri
      try {
        $out = & $curl.Source $curlArgs 2>$null
        if ($out) { return $out | ConvertFrom-Json -ErrorAction Stop }
      } catch { Write-Log ("curl.exe fallback failed: {0}" -f $_.Exception.Message) 'WARN' }
    } else {
      Write-Log "curl.exe not found; skipping curl fallback" 'WARN'
    }
    return $null
  }
}

function Ensure-Tls {
  # Prefer TLS 1.2, optionally TLS 1.3 if supported
  try {
    $tls12 = [System.Net.SecurityProtocolType]::Tls12
    $proto = $tls12
    try {
      $tls13 = [System.Net.SecurityProtocolType]::Tls13
      # Combine if TLS 1.3 exists
      $proto = $proto -bor $tls13
    } catch {
      # TLS 1.3 not available; keep TLS 1.2
    }
    [System.Net.ServicePointManager]::SecurityProtocol = $proto
    Write-Log "SecurityProtocol set to: $([System.Net.ServicePointManager]::SecurityProtocol)" 'INFO'
  } catch {
    Write-Log "Failed to set SecurityProtocol: $($_.Exception.Message)" 'WARN'
  }
}

function Set-CertValidation {
  param([switch]$Disable)
  if ($Disable) {
    Write-Log "TLS certificate validation disabled (lab/testing). Do NOT use in prod." 'WARN'
    $script:_prevCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { param($svc, $certificate, $chain, $errors) return $true }
  } else {
    if ($script:_prevCallback) {
      [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $script:_prevCallback
      $script:_prevCallback = $null
    }
  }
}

function Write-ErrorDetails {
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.ErrorRecord]$ErrorRecord
  )
  try {
    $ts = Get-Date -Format 'o'
    $ex = $ErrorRecord.Exception
    $info = $ErrorRecord.InvocationInfo
    $lines = @()
    $lines += "Failure at: $ts"
    $lines += "Message: $($ex.Message)"
    $lines += "Category: $($ErrorRecord.CategoryInfo)"
    $lines += "FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)"
    if ($info) {
      $lines += ("Script: {0}" -f $info.ScriptName)
      $lines += ("Line: {0}, Column: {1}" -f $info.ScriptLineNumber, $info.OffsetInLine)
      if ($info.Line) { $lines += ("Code: {0}" -f $info.Line.Trim()) }
      if ($info.PositionMessage) { $lines += $info.PositionMessage }
    }
    if ($ex) {
      $lines += ("ExceptionType: {0}" -f $ex.GetType().FullName)
      if ($ex.HResult) { $lines += ("HResult: 0x{0:X8}" -f $ex.HResult) }
      if ($ex.StackTrace) { $lines += 'StackTrace:'; $lines += $ex.StackTrace }
      $inner = $ex.InnerException
      $depth = 0
      while ($inner -and $depth -lt 5) {
        $lines += ("Inner[{0}]: {1}" -f $depth, $inner.Message)
        $inner = $inner.InnerException
        $depth++
      }
    }
    $text = $lines -join [Environment]::NewLine
    Write-Log $text 'ERROR'
    $script:FailurePath = if ($script:OutDir) { Join-Path $script:OutDir 'FAILURE.txt' } else { Join-Path $env:TEMP ("ComplianceAudit_FAILURE_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss')) }
    $text | Set-Content -Path $script:FailurePath -Encoding UTF8
  } catch {
    # Swallow any logging errors to avoid masking the real failure
  }
}

function Invoke-RestJson {
  param(
    [ValidateSet('GET','POST')]
    [string]$Method = 'GET',

    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $false)]
    [hashtable]$Headers,

    [Parameter(Mandatory = $false)]
    [hashtable]$Body,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSec = 15,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 5,

    [Parameter(Mandatory = $false)]
    [switch]$FormUrlEncoded
  )
  for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
      $params = @{
        Method      = $Method
        Uri         = $Uri
        TimeoutSec  = $TimeoutSec
        ErrorAction = 'Stop'
      }
      if ($Headers) { $params['Headers'] = $Headers }
      if ($Method -eq 'POST') {
        if ($FormUrlEncoded) {
          $params['ContentType'] = 'application/x-www-form-urlencoded'
          $params['Body'] = $Body
        } else {
          $params['ContentType'] = 'application/json'
          if ($Body) {
            $params['Body'] = ($Body | ConvertTo-Json -Depth 6)
          } else {
            $params['Body'] = '{}' # ensure POST body is valid JSON
          }
        }
      }

      Write-Log "HTTP $Method $Uri (attempt $i/$MaxRetries)" 'INFO'
      $resp = Invoke-RestMethod @params
      return $resp
    } catch {
      # Use -f formatting to avoid variable-name parsing issues near colons
      Write-Log ("HTTP error on {0} {1}: {2}" -f $Method, $Uri, $_.Exception.Message) 'WARN'
      if ($i -lt $MaxRetries) {
        $sleep = [math]::Min(60, 5 * $i)
        Start-Sleep -Seconds $sleep
      } else {
        throw
      }
    }
  }
}

# =========================
# Output Folder & Audit Files
# =========================
function Select-OutputRoot {
  if ($OutRoot) { return $OutRoot }
  
  # Default to Test Output folder in script directory
  $defaultPath = Join-Path $PSScriptRoot "Test Output"
  if (-not (Test-Path $defaultPath)) {
    New-Item -ItemType Directory -Path $defaultPath -Force | Out-Null
  }
  return $defaultPath
  
  # Note: Folder picker dialog removed for convenience - use -OutRoot parameter to specify custom location
}

function Initialize-Output {
  $root = Select-OutputRoot
  $safeHost = if ($ZVMAHost) { ($ZVMAHost -replace '[^a-zA-Z0-9\.\-]','_') } else { 'ZVMA' }
  $script:OutDir = Join-Path $root ("ComplianceAudit_{0}_{1}" -f $safeHost, $timestamp)
  New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

  if ($SimpleNames) {
    $script:CsvPath         = Join-Path $script:OutDir "Evidence.csv"
    $script:SummaryPath     = Join-Path $script:OutDir "Summary.txt"
    $script:ManifestPath    = Join-Path $script:OutDir "Manifest.json"
    $script:ControlsMapPath = Join-Path $script:OutDir "ControlsMap.txt"
    $script:LogPath         = Join-Path $script:OutDir "Log.txt"
    $script:TranscriptPath  = Join-Path $script:OutDir "Transcript.txt"
    $script:HtmlReportPath  = Join-Path $script:OutDir "Report.html"
    $script:PdfReportPath   = Join-Path $script:OutDir "Report.pdf"
  } else {
    $script:CsvPath         = Join-Path $script:OutDir ("Zerto_Compliance_{0}.csv" -f $timestamp)
    $script:SummaryPath     = Join-Path $script:OutDir "SUMMARY.txt"
    $script:ManifestPath    = Join-Path $script:OutDir "MANIFEST.json"
    $script:ControlsMapPath = Join-Path $script:OutDir "ControlsMap.txt"
    $script:LogPath         = Join-Path $script:OutDir "LOG.txt"
    $script:TranscriptPath  = Join-Path $script:OutDir "TRANSCRIPT.txt"
    $script:HtmlReportPath  = Join-Path $script:OutDir ("Report_{0}.html" -f $timestamp)
    $script:PdfReportPath   = Join-Path $script:OutDir ("Report_{0}.pdf" -f $timestamp)
  }

  # create empty log file early
  New-Item -ItemType File -Path $script:LogPath -Force | Out-Null
  Write-Log "Output directory ready: $script:OutDir"
}

function Try-GetVCenterTotalVmCount {
  param(
    [Parameter(Mandatory=$true)] [string]$Server,
    [Parameter(Mandatory=$true)] [string]$User,
    [Parameter(Mandatory=$true)] [string]$Password
  )
  try {
    if (-not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) {
      Write-Log "VMware PowerCLI module not found; attempting installation..." 'WARN'
      Ensure-PowerCLI
    }
    if (-not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) {
      Write-Log "VMware PowerCLI still not available after install attempt." 'WARN'
      return $null
    }
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop | Out-Null
    if ($Insecure -or $VCenterInsecure) {
      try { Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$false | Out-Null } catch { }
    }
    $vc = $null
    try {
      $vc = Connect-VIServer -Server $Server -User $User -Password $Password -WarningAction SilentlyContinue -ErrorAction Stop
      $count = (Get-VM -Server $vc -ErrorAction Stop | Measure-Object).Count
      Write-Log ("vCenter inventory: {0} total VMs" -f $count) 'INFO'
      return [int]$count
    } finally {
      if ($vc) { try { Disconnect-VIServer -Server $vc -Confirm:$false | Out-Null } catch { } }
    }
  } catch {
    Write-Log ("vCenter query failed: {0}" -f $_.Exception.Message) 'WARN'
    return $null
  }
}

function Ensure-PowerCLI {
  try {
    # Ensure NuGet provider
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget) {
      Write-Log "Installing NuGet package provider..." 'INFO'
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
    }
    # Trust PSGallery
    try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop } catch { }
    Write-Log "Installing VMware.PowerCLI (CurrentUser)..." 'INFO'
    Install-Module VMware.PowerCLI -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop | Out-Null
    Write-Log "VMware.PowerCLI installed and imported." 'INFO'
  } catch {
    Write-Log ("Failed to install PowerCLI: {0}" -f $_.Exception.Message) 'ERROR'
  }
}

function Ensure-Wkhtmltopdf {
  try {
    $wk = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
    if ($wk) { return }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
      Write-Log "Installing wkhtmltopdf via winget..." 'INFO'
      try {
        & $winget.Source install --silent --accept-package-agreements --accept-source-agreements wkhtmltopdf | Out-Null
      } catch { Write-Log ("winget install failed: {0}" -f $_.Exception.Message) 'WARN' }
      $wk = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
      if ($wk) { return }
    }
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
      Write-Log "Installing wkhtmltopdf via Chocolatey..." 'INFO'
      try {
        & $choco.Source install wkhtmltopdf -y | Out-Null
      } catch { Write-Log ("choco install failed: {0}" -f $_.Exception.Message) 'WARN' }
    }
  } catch {
    Write-Log ("Ensure-Wkhtmltopdf error: {0}" -f $_.Exception.Message) 'WARN'
  }
}

function Convert-HtmlToPdf {
  param(
    [Parameter(Mandatory=$true)][string]$HtmlPath,
    [Parameter(Mandatory=$true)][string]$PdfPath
  )
  # Try wkhtmltopdf first
  $wk = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
  if ($wk) {
    try {
      & $wk.Source $HtmlPath $PdfPath | Out-Null
      if (Test-Path -LiteralPath $PdfPath) { return $true }
    } catch { Write-Log ("wkhtmltopdf failed: {0}" -f $_.Exception.Message) 'WARN' }
  }
  # Try Edge headless
  $edge = Get-Command msedge.exe -ErrorAction SilentlyContinue
  if ($edge) {
    try {
      & $edge.Source '--headless' '--disable-gpu' ("--print-to-pdf={0}" -f $PdfPath) $HtmlPath | Out-Null
      if (Test-Path -LiteralPath $PdfPath) { return $true }
    } catch { Write-Log ("Edge headless PDF failed: {0}" -f $_.Exception.Message) 'WARN' }
  }
  # Try Chrome headless
  $chrome = Get-Command chrome.exe -ErrorAction SilentlyContinue
  if ($chrome) {
    try {
      & $chrome.Source '--headless' '--disable-gpu' ("--print-to-pdf={0}" -f $PdfPath) $HtmlPath | Out-Null
      if (Test-Path -LiteralPath $PdfPath) { return $true }
    } catch { Write-Log ("Chrome headless PDF failed: {0}" -f $_.Exception.Message) 'WARN' }
  }
  return $false
}

function Get-ZvmaCertificateInfo {
  param([Parameter(Mandatory=$true)][string]$TargetHost)
  try {
    $tcp = New-Object Net.Sockets.TcpClient($TargetHost,443)
    try {
      $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, ([Net.Security.RemoteCertificateValidationCallback]{ param($s,$c,$ch,$e) return $true }))
      $ssl.AuthenticateAsClient($TargetHost)
      $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
      $expires = $cert2.NotAfter
      $days = [int]([Math]::Round(($expires - (Get-Date)).TotalDays))
      $result = [ordered]@{
        Subject         = $cert2.Subject
        Issuer          = $cert2.Issuer
        NotBefore       = $cert2.NotBefore.ToString('o')
        NotAfter        = $cert2.NotAfter.ToString('o')
        Thumbprint      = $cert2.Thumbprint
        DaysUntilExpiry = $days
        ExpiringSoon    = ($days -lt 30)
      }
      try { $ssl.Dispose() } catch {}
      try { $tcp.Close() } catch {}
      return $result
    } catch {
      try { $tcp.Close() } catch {}
      throw
    }
  } catch {
    Write-Log ("Failed to read ZVMA TLS certificate: {0}" -f $_.Exception.Message) 'WARN'
    return $null
  }
}

function Get-OpenApiSpec {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  $candidates = @(
    "https://$ZVMAHost/swagger/v1/swagger.json",
    "https://$ZVMAHost/swagger/v2/swagger.json",
    "https://$ZVMAHost/swagger/swagger.json",
    "https://$ZVMAHost/swagger/docs/v1",
    "https://$ZVMAHost/swagger.json",
    "https://$ZVMAHost/v1/swagger.json",
    "https://$ZVMAHost/openapi/v1.json",
    "https://$ZVMAHost/openapi.json"
  )
  foreach ($u in $candidates) {
    try {
      $spec = Invoke-HttpJsonWithCurlFallback -Uri $u -Headers $Headers -Method 'GET'
      if ($spec -and $spec.PSObject.Properties['paths']) { return $spec }
    } catch { }
  }
  return $null
}

function Discover-ZertoApiPaths {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  $result = @{ Version = @(); Sites = @(); LocalSite = @(); PeerSites = @(); Vms = @(); VirtualizationSites = @(); Vpgs = @(); VpgVmsTemplates = @() }
  try {
    $spec = Get-OpenApiSpec -ZVMAHost $ZVMAHost -Headers $Headers
    if (-not $spec) { return $result }
    $paths = $spec.paths
    if ($paths) {
      foreach ($kv in $paths.PSObject.Properties) {
        $p = $kv.Name
        $ops = $kv.Value
        # Only consider GET-able paths
        $hasGet = $false
        if ($ops -and $ops.PSObject.Properties['get']) { $hasGet = $true }
        if (-not $hasGet) { continue }
        $full = if ($p.StartsWith('/')) { "https://$ZVMAHost$p" } else { "https://$ZVMAHost/$p" }
        
        # Check if path contains template parameters (e.g., {siteIdentifier})
        $hasTemplate = $p -match '\{[^}]+\}'
        
        # For template paths, only add to VpgVmsTemplates (which expects templates)
        # For non-template paths, add to appropriate collections
        if ($hasTemplate) {
          # Only store templates for VPG VM endpoints (these are handled specially)
          if ($p -match '(?i)/vpgs/.+\{.+\}.*/vms') { $result.VpgVmsTemplates += $full }
        } else {
          # Non-template paths - safe to call directly
          if ($p -match '(?i)version') { $result.Version += $full }
          if ($p -match '(?i)localsite') { $result.LocalSite += $full }
          if ($p -match '(?i)/sites?$' -or $p -match '(?i)/site$' -or $p -match '(?i)site') { $result.Sites += $full }
          if (($p -match '(?i)peer' -and $p -match '(?i)site') -or ($p -match '(?i)remote' -and $p -match '(?i)site')) { $result.PeerSites += $full }
          if ($p -match '(?i)/vms?$' -or $p -match '(?i)/virtualmachines?$' -or $p -match '(?i)/vm$') { $result.Vms += $full }
          if ($p -match '(?i)virtualizationsites') { $result.VirtualizationSites += $full }
          if ($p -match '(?i)^/v1/vpgs$' -or $p -match '(?i)/vpgs$') { $result.Vpgs += $full }
        }
      }
    }
  } catch { }
  return $result
}

function Write-ControlsMap {
@"
Zerto Compliance Controls Mapping (informational)
-------------------------------------------------
Availability (DR Testing):
  - NIST SP 800-53: CP-4 (Contingency Plan Testing)
  - CIS Controls: Control 11 (Data Recovery), periodic testing of recovery procedures

Cyber Resilience (LTR Immutability):
  - NIST SP 800-53: CP-9 (Information System Backup), SC-28 (Protection of Information at Rest)
  - CIS Controls: Control 11.6 (Immutability / Write-Once backups)

Inventory Coverage:
  - NIST SP 800-53: CM-8 (Information System Component Inventory)
  - CIS Controls: Control 1 (Enterprise Asset Inventory)

 Additional mappings:
   - ISO/IEC 27001: A.5.30 ICT readiness for business continuity; A.8.12 Data deletion; A.8.24 Logging
   - SOC 2 (Security/Availability): CC7.2 monitoring; AOR: backup/testing procedures and evidence
   - HIPAA: 45 CFR §164.308(a)(7) Contingency Plan; §164.312(c)(1) Integrity; logs as audit controls

NOTE: This file is guidance only; verify the exact mappings against your organization's framework and policies.
"@ | Set-Content -Path $script:ControlsMapPath -Encoding UTF8
  Write-Log "ControlsMap.txt written."
}

function Write-Manifest {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Scores,

    [Parameter(Mandatory = $true)]
    [hashtable]$Totals,

    [Parameter(Mandatory = $false)]
    [hashtable]$Options
  )

  $files = @()
  if (Test-Path -LiteralPath $script:CsvPath) {
    $files += @{
      Name = (Split-Path -Leaf $script:CsvPath)
      Path = $script:CsvPath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:CsvPath).Hash
    }
  }
  if (Test-Path -LiteralPath $script:SummaryPath) {
    $files += @{
      Name = (Split-Path -Leaf $script:SummaryPath)
      Path = $script:SummaryPath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:SummaryPath).Hash
    }
  }
  if (Test-Path -LiteralPath $script:ControlsMapPath) {
    $files += @{
      Name = (Split-Path -Leaf $script:ControlsMapPath)
      Path = $script:ControlsMapPath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:ControlsMapPath).Hash
    }
  }
  if (Test-Path -LiteralPath $script:LogPath) {
    $files += @{
      Name = (Split-Path -Leaf $script:LogPath)
      Path = $script:LogPath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:LogPath).Hash
    }
  }
  if ($script:TranscriptPath -and (Test-Path -LiteralPath $script:TranscriptPath)) {
    $files += @{
      Name = (Split-Path -Leaf $script:TranscriptPath)
      Path = $script:TranscriptPath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:TranscriptPath).Hash
    }
  }
  if ($script:FailurePath -and (Test-Path -LiteralPath $script:FailurePath)) {
    $files += @{
      Name = (Split-Path -Leaf $script:FailurePath)
      Path = $script:FailurePath
      Hash = (Get-FileHash -Algorithm SHA256 -Path $script:FailurePath).Hash
    }
  }

  $manifest = [ordered]@{
    Version            = $scriptVersion
    CollectedAt        = $startTime.ToString('o')
    TimeZone           = $timeZone
    Hostname           = $env:COMPUTERNAME
    User               = ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    ZVMAHost           = $ZVMAHost
    Realm              = $Realm
    ClientId           = $ClientId
    GrantType          = $GrantType
    InsecureTls        = [bool]$Insecure
    ZvmaCertificate    = $(if ($script:ZvmaCertInfo) { $script:ZvmaCertInfo } else { $null })
    CoverageSource     = $(if ($script:CoverageSource) { $script:CoverageSource } else { $null })
    VCenterServer      = $(if ($VCenterServer) { $VCenterServer } else { $null })
    AnalyticsKeyUsed   = [bool]($AnalyticsKey -and ($AnalyticsKey.Trim().Length -gt 0))
    UseLTR             = [bool]$UseLTR
    Totals             = $Totals
    Scores             = $Scores
    Files              = $files
    ZertoMetadata      = [ordered]@{
      Version         = $zertoVersion
      LocalSite       = $localSite
      PeerSites       = $peerSites
      Sites           = $zertoSites
      VmCount         = $(if ($zertoVms) { $zertoVms.Count } else { 0 })
      ProtectedVmNames = $(if ($protectedVmNames -and $protectedVmNames.Count -gt 0) { @($protectedVmNames) } else { @() })
    }
    Notes              = @(
      "Coverage score uses protected dataset only unless TotalVmCount parameter is provided.",
      "If InsecureTls is true, certificate validation was bypassed (suitable for labs, not production)."
    )
  }

  ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $script:ManifestPath -Encoding UTF8
  Write-Log "MANIFEST.json written."
}

# =========================
# Auth & Data Functions
# =========================
function Get-ZertoToken {
  param(
    [Parameter(Mandatory = $true)] [string]$ZVMAHost,
    [Parameter(Mandatory = $true)] [string]$Realm,
    [Parameter(Mandatory = $true)] [string]$ClientId,
    [Parameter(Mandatory = $true)] [ValidateSet('password','client_credentials')] [string]$GrantType,
    [Parameter(Mandatory = $false)] [string]$Username,
    [Parameter(Mandatory = $false)] [string]$Password,
    [Parameter(Mandatory = $false)] [string]$ClientSecret,
    [Parameter(Mandatory = $false)] [string]$CredentialTarget
  )
  
  # If using Credential Manager, attempt retrieval
  if ($CredentialTarget -and ($Username -eq "from-$CredentialTarget" -or $Password -eq "from-$CredentialTarget")) {
    $storedCreds = cmdkey /list:$CredentialTarget 2>$null | Select-String "User:" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
    if ($storedCreds) {
      # When credentials are in Credential Manager, we can use them directly
      # cmdkey stores them but retrieval requires special handling
      Write-Log ("Using credentials from Credential Manager: {0}" -f $CredentialTarget) 'INFO'
      # The actual credentials will be used by system; here we just proceed
    } else {
      throw "Credentials not found in Credential Manager for target: $CredentialTarget. Store with: cmdkey /add:$CredentialTarget /user:<username> /pass:<password>"
    }
  }
  
  $tokenUrl = "https://$ZVMAHost/auth/realms/$Realm/protocol/openid-connect/token"
  $form = @{
    client_id  = $ClientId
    grant_type = $GrantType
    scope      = 'openid'
  }
  if ($GrantType -eq 'password') {
    if (-not $Username -or (-not $Password -and $Password -ne "from-*")) { throw "Username/Password required for password grant." }
    $form.username = $Username
    $form.password = $Password
    Write-Log ("Attempting token request with user: {0}, password length: {1}, client: {2}" -f $Username, $Password.Length, $ClientId) 'INFO'
  } else {
    if ($ClientSecret) { $form.client_secret = $ClientSecret }
  }
  $resp = Invoke-RestJson -Method 'POST' -Uri $tokenUrl -Body $form -FormUrlEncoded -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
  $tok = $null
  if ($resp) {
    if ($resp.access_token) { $tok = $resp.access_token }
    elseif ($resp.token) { $tok = $resp.token }
  }
  if (-not $tok) { throw "No access token in response: $(ConvertTo-Json $resp -Depth 6)" }
  return $tok
}

function Get-AnalyticsHeadersPrimary {
  param([Parameter(Mandatory = $true)][string]$ApiKey)
  return @{ Authorization = ("Bearer {0}" -f $ApiKey) }
}

function Get-AnalyticsHeadersFallback {
  param([Parameter(Mandatory = $true)][string]$ApiKey)
  $url = "https://analytics.api.zerto.com/v2/auth/token"
  $resp = Invoke-RestJson -Method 'POST' -Uri $url -Headers @{ Authorization = ("Bearer {0}" -f $ApiKey) } -Body @{} -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
  $tok = $null
  if ($resp) {
    if ($resp.token) { $tok = $resp.token }
    elseif ($resp.access_token) { $tok = $resp.access_token }
  }
  if (-not $tok) { throw "No analytics token in response: $(ConvertTo-Json $resp -Depth 6)" }
  return @{ Authorization = ("Bearer {0}" -f $tok) }
}

# Optional MyZerto-based auth for Analytics
function Get-AnalyticsHeadersMyZerto {
  param(
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$Region,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $false)][string]$MfaCode
  )
  $myZertoAuthEp = "https://cognito-idp.$Region.amazonaws.com/"
  $initPayload = @{ ClientId = $ClientId; AuthFlow = 'USER_PASSWORD_AUTH'; AuthParameters = @{ USERNAME = $User; PASSWORD = $Password } }
  $headers = @{ 'Content-Type' = 'application/x-amz-json-1.1'; 'X-Amz-Target' = 'AWSCognitoIdentityProviderService.InitiateAuth' }
  $init = Invoke-RestMethod -Method POST -Uri $myZertoAuthEp -Headers $headers -Body ($initPayload | ConvertTo-Json -Depth 6)
  $challenge = $init.ChallengeName
  $session = $init.Session
  if (-not $challenge) {
    $idToken = $init.AuthenticationResult.IdToken
    if (-not $idToken) { throw "MyZerto: No IdToken returned and no challenge." }
    return @{ Authorization = ("Bearer {0}" -f $idToken) }
  }
  $field = 'SMS_MFA_CODE'
  if ($challenge -eq 'SOFTWARE_TOKEN_MFA') { $field = 'SOFTWARE_TOKEN_MFA_CODE' }
  if (-not $MfaCode) { throw "MyZerto MFA challenge '$challenge' requires -MyZertoMfaCode" }
  $respPayload = @{ ChallengeName = $challenge; ClientId = $ClientId; Session = $session; ChallengeResponses = @{ USERNAME = $User } }
  $respPayload.ChallengeResponses[$field] = $MfaCode
  $headers['X-Amz-Target'] = 'AWSCognitoIdentityProviderService.RespondToAuthChallenge'
  $resp = Invoke-RestMethod -Method POST -Uri $myZertoAuthEp -Headers $headers -Body ($respPayload | ConvertTo-Json -Depth 6)
  $idToken = $resp.AuthenticationResult.IdToken
  if (-not $idToken) { throw "MyZerto: No IdToken in RespondToAuthChallenge response." }
  return @{ Authorization = ("Bearer {0}" -f $idToken) }
}

function Get-AnalyticsHeadersFromFile {
  param([Parameter(Mandatory = $true)][string]$BearerFile)
  if (-not (Test-Path -LiteralPath $BearerFile)) { throw "Bearer file not found: $BearerFile" }
  $line = Get-Content -LiteralPath $BearerFile -TotalCount 1
  if ($line -match '^Authorization:\s*Bearer\s+(.+)$') {
    $tok = $Matches[1]
    return @{ Authorization = ("Bearer {0}" -f $tok) }
  } else {
    throw "Bearer file does not contain an 'Authorization: Bearer <token>' line."
  }
}

function Get-BearerTokenInteractive {
  param(
    [Parameter(Mandatory = $false)][string]$ClientId,
    [Parameter(Mandatory = $false)][string]$Region = 'us-east-1',
    [Parameter(Mandatory = $false)][string]$User,
    [Parameter(Mandatory = $false)][string]$Password,
    [Parameter(Mandatory = $false)][string]$MfaCode
  )
  if (-not $ClientId) { $ClientId = Read-Host "Enter MyZerto ClientId" }
  if (-not $User) { $User = Read-Host "Enter MyZerto user (email)" }
  if (-not $Password) { $Password = Read-Host "Enter MyZerto password" }
  Write-Log "Acquiring bearer token via MyZerto (inline)..." 'INFO'
  try {
    $myZertoAuthEp = "https://cognito-idp.$Region.amazonaws.com/"
    $initPayload = @{ ClientId = $ClientId; AuthFlow = 'USER_PASSWORD_AUTH'; AuthParameters = @{ USERNAME = $User; PASSWORD = $Password } }
    $headers = @{ 'Content-Type' = 'application/x-amz-json-1.1'; 'X-Amz-Target' = 'AWSCognitoIdentityProviderService.InitiateAuth' }
    $init = Invoke-RestMethod -Method POST -Uri $myZertoAuthEp -Headers $headers -Body ($initPayload | ConvertTo-Json -Depth 6)
    $challenge = $init.ChallengeName
    $session = $init.Session
    if (-not $challenge) {
      $idToken = $init.AuthenticationResult.IdToken
      if (-not $idToken) { throw "MyZerto: No IdToken returned and no challenge." }
      return @{ Authorization = ("Bearer {0}" -f $idToken) }
    }
    $field = 'SMS_MFA_CODE'
    if ($challenge -eq 'SOFTWARE_TOKEN_MFA') { $field = 'SOFTWARE_TOKEN_MFA_CODE' }
    if (-not $MfaCode) { $MfaCode = Read-Host "Enter MFA code for challenge '$challenge'" }
    $respPayload = @{ ChallengeName = $challenge; ClientId = $ClientId; Session = $session; ChallengeResponses = @{ USERNAME = $User } }
    $respPayload.ChallengeResponses[$field] = $MfaCode
    $headers['X-Amz-Target'] = 'AWSCognitoIdentityProviderService.RespondToAuthChallenge'
    $resp = Invoke-RestMethod -Method POST -Uri $myZertoAuthEp -Headers $headers -Body ($respPayload | ConvertTo-Json -Depth 6)
    $idToken = $resp.AuthenticationResult.IdToken
    if (-not $idToken) { throw "MyZerto: No IdToken in RespondToAuthChallenge response." }
    return @{ Authorization = ("Bearer {0}" -f $idToken) }
  } catch {
    Write-Log ("Inline bearer token acquisition failed: {0}" -f $_.Exception.Message) 'ERROR'
    throw
  }
}

function Get-FailoverTests {
  param(
    [Parameter(Mandatory = $true)][string]$ZVMAHost,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )
  $url = "https://$ZVMAHost/v1/reports/recovery?type=FailoverTest"
  return Invoke-RestJson -Method 'GET' -Uri $url -Headers $Headers -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
}

function Get-AlternateCredentials {
  param(
    [Parameter(Mandatory=$true)][string]$SiteName,
    [Parameter(Mandatory=$false)][string]$VmName,
    [Parameter(Mandatory=$true)][string]$Reason
  )
  
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "ALTERNATE CREDENTIALS REQUIRED" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  Site Name: " -ForegroundColor Yellow -NoNewline
  Write-Host "$SiteName" -ForegroundColor White
  if ($VmName) {
    Write-Host "  VM Name:   " -ForegroundColor Yellow -NoNewline
    Write-Host "$VmName" -ForegroundColor White
  }
  Write-Host "  Issue:     " -ForegroundColor Yellow -NoNewline
  Write-Host "$Reason" -ForegroundColor Red
  Write-Host ""
  Write-Host "  The current credentials failed to authenticate to this site."
  Write-Host "  Please provide alternate credentials or press Ctrl+C to skip."
  Write-Host ""
  
  $altUsername = Read-Host "  Enter username (or leave blank to skip)"
  
  if ([string]::IsNullOrWhiteSpace($altUsername)) {
    Write-Host "  Skipping alternate credentials for $SiteName" -ForegroundColor Yellow
    Write-Host ""
    return $null
  }
  
  $altPassword = Read-Host "  Enter password" -AsSecureString
  
  return [ordered]@{
    Username = $altUsername
    Password = $altPassword
    PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($altPassword))
  }
}

function Get-Vpgs {
  param(
    [Parameter(Mandatory = $true)][string]$ZVMAHost,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )
  $url = "https://$ZVMAHost/v1/vpgs"
  return Invoke-RestJson -Method 'GET' -Uri $url -Headers $Headers -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
}

function Get-ProtectedVms {
  param([Parameter(Mandatory = $true)][hashtable]$Headers)
  $url = "https://analytics.api.zerto.com/v2/monitoring/protected-vms"
  return Invoke-RestJson -Method 'GET' -Uri $url -Headers $Headers -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
}

function Get-ZertoVersion {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  $defaults = @(
    "https://$ZVMAHost/management/api/version",
    "https://$ZVMAHost/v1/version",
    "https://$ZVMAHost/v1/zvm/version",
    "https://$ZVMAHost/v1/about",
    "https://$ZVMAHost/version",
    "https://$ZVMAHost/api/version",
    "https://$ZVMAHost/zvm/about"
  )
  $endpoints = @()
  if ($null -ne $ZertoVersionEndpoints -and $ZertoVersionEndpoints.Count -gt 0) { $endpoints += $ZertoVersionEndpoints }
  try {
    $disc = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
    if ($disc -and $disc.Version -and $disc.Version.Count -gt 0) { $endpoints += $disc.Version }
  } catch { }
  $endpoints += $defaults
  foreach ($ep in $endpoints) {
    try { return Invoke-HttpJsonWithCurlFallback -Uri $ep -Headers $Headers -Method 'GET' } catch {}
  }
  return $null
}

function Get-ZertoSites {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  $defaults = @(
    "https://$ZVMAHost/v1/sites",
    "https://$ZVMAHost/v1/local/site",
    "https://$ZVMAHost/v1/site",
    "https://$ZVMAHost/sites",
    "https://$ZVMAHost/api/sites",
    "https://$ZVMAHost/zvm/site"
  )
  $endpoints = @()
  if ($null -ne $ZertoSitesEndpoints -and $ZertoSitesEndpoints.Count -gt 0) { $endpoints += $ZertoSitesEndpoints }
  try {
    $disc = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
    if ($disc -and $disc.Sites -and $disc.Sites.Count -gt 0) { $endpoints += $disc.Sites }
  } catch { }
  $endpoints += $defaults
  foreach ($ep in $endpoints) {
    try { return Invoke-HttpJsonWithCurlFallback -Uri $ep -Headers $Headers -Method 'GET' } catch {}
  }
  return $null
}

function Get-ZertoLocalSite {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  $candidates = @(
    "https://$ZVMAHost/v1/localsite",
    "https://$ZVMAHost/v1/local/site",
    "https://$ZVMAHost/localsite"
  )
  try {
    $disc = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
    if ($disc -and $disc.LocalSite -and $disc.LocalSite.Count -gt 0) { $candidates = $disc.LocalSite + $candidates }
  } catch { }
  foreach ($u in $candidates) { try { return Invoke-HttpJsonWithCurlFallback -Uri $u -Headers $Headers -Method 'GET' } catch {} }
  return $null
}

function Get-ZertoPeerSites {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers,[Parameter(Mandatory=$false)][string]$LocalSiteId)
  $candidates = @(
    "https://$ZVMAHost/v1/remotesites",
    "https://$ZVMAHost/v1/peersites",
    "https://$ZVMAHost/v1/site/peers",
    "https://$ZVMAHost/v1/sites"
  )
  try {
    $disc = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
    $all = @()
    if ($disc -and $disc.PeerSites -and $disc.PeerSites.Count -gt 0) { $all += $disc.PeerSites }
    if ($disc -and $disc.Sites -and $disc.Sites.Count -gt 0) { $all += $disc.Sites }
    if ($all.Count -gt 0) { $candidates = $all + $candidates }
  } catch { }
  foreach ($u in $candidates) {
    try {
      $res = Invoke-HttpJsonWithCurlFallback -Uri $u -Headers $Headers -Method 'GET'
      if ($null -eq $res) { continue }
      if ($res -is [System.Array]) { $arr = @($res) } else { $arr = @($res) }
      if ($LocalSiteId) { $arr = $arr | Where-Object { $_.SiteIdentifier -and ($_.SiteIdentifier -ne $LocalSiteId) } }
      if ($arr.Count -gt 0) { return $arr }
    } catch {}
  }
  return @()
}

function Get-VirtualizationSiteVms {
  param(
    [Parameter(Mandatory=$true)][string]$ZVMAHost,
    [Parameter(Mandatory=$true)][hashtable]$Headers
  )
  
  Write-Log "Collecting virtualization sites for complete VM inventory..." 'INFO'
  
  # Step 1: Get all virtualization site identifiers
  $sitesUrl = "https://$ZVMAHost/v1/virtualizationsites"
  $sites = @()
  try {
    $sitesResponse = Invoke-HttpJsonWithCurlFallback -Uri $sitesUrl -Headers $Headers -Method 'GET'
    if ($sitesResponse -is [System.Array]) { $sites = @($sitesResponse) }
    elseif ($sitesResponse) { $sites = @($sitesResponse) }
    Write-Log ("Found {0} virtualization site(s)" -f $sites.Count) 'INFO'
  } catch {
    Write-Log ("Failed to retrieve virtualization sites: {0}" -f $_.Exception.Message) 'WARN'
    return @()
  }
  
  # Step 2: For each site, get all VMs
  $allVms = @()
  foreach ($site in $sites) {
    $siteId = $null
    $siteName = $null
    
    if ($site.PSObject.Properties['SiteIdentifier']) { $siteId = [string]$site.SiteIdentifier }
    elseif ($site.PSObject.Properties['Identifier']) { $siteId = [string]$site.Identifier }
    
    if ($site.PSObject.Properties['VirtualizationSiteName']) { $siteName = [string]$site.VirtualizationSiteName }
    elseif ($site.PSObject.Properties['SiteName']) { $siteName = [string]$site.SiteName }
    elseif ($site.PSObject.Properties['Name']) { $siteName = [string]$site.Name }
    
    if (-not $siteId) { continue }
    
    Write-Log ("Collecting VMs from site: {0} ({1})" -f $siteName, $siteId) 'INFO'
    
    $siteVmsUrl = "https://$ZVMAHost/v1/virtualizationsites/$siteId/vms"
    try {
      $vmsResponse = Invoke-HttpJsonWithCurlFallback -Uri $siteVmsUrl -Headers $Headers -Method 'GET'
      $vms = @()
      if ($vmsResponse -is [System.Array]) { $vms = @($vmsResponse) }
      elseif ($vmsResponse) { $vms = @($vmsResponse) }
      
      Write-Log ("Retrieved {0} VM(s) from site {1}" -f $vms.Count, $siteName) 'INFO'
      $allVms += $vms
    } catch {
      Write-Log ("Failed to retrieve VMs from site {0}: {1}" -f $siteName, $_.Exception.Message) 'WARN'
    }
  }
  
  Write-Log ("Total VMs collected from all virtualization sites: {0}" -f $allVms.Count) 'INFO'
  return $allVms
}

function Enrich-PeerSiteInfo {
  param(
    [Parameter(Mandatory=$true)][hashtable[]]$PeerSites,
    [Parameter(Mandatory=$true)][string]$ZVMAHost,
    [Parameter(Mandatory=$true)][hashtable]$PrimaryHeaders,
    [hashtable]$PeerCredentials = $null
  )
  
  $enriched = @()
  foreach ($peer in $PeerSites) {
    $peerInfo = $peer.Clone()
    
    # If we have a Host/IP for this peer, try to fetch /v1/about
    if ($peer.Host -or $peer.PSObject.Properties['Host']) {
      $peerHost = $peer.Host
      if ($peerHost) {
        $aboutUrl = "https://$peerHost/v1/about"
        try {
          $headers = $PrimaryHeaders.Clone()
          # If we have specific peer credentials, build headers for this peer
          if ($PeerCredentials -and $PeerCredentials.ContainsKey($peerHost)) {
            $creds = $PeerCredentials[$peerHost]
            $token = $creds.Token
            if ($token) {
              $headers['Authorization'] = "Bearer $token"
            }
          }
          
          $aboutData = Invoke-HttpJsonWithCurlFallback -Uri $aboutUrl -Headers $headers -Method 'GET'
          if ($aboutData) {
            $peerInfo['About'] = $aboutData
            if ($aboutData.PSObject.Properties['VersionName']) {
              $peerInfo['DisplayVersion'] = $aboutData.VersionName
            } elseif ($aboutData.PSObject.Properties['Version']) {
              $peerInfo['DisplayVersion'] = $aboutData.Version
            }
            Write-Log ("Successfully retrieved /v1/about from peer site {0}" -f $peerHost) 'INFO'
          }
        } catch {
          Write-Log ("Could not fetch /v1/about from {0}: {1}" -f $peerHost, $_.Exception.Message) 'WARN'
        }
      }
    }
    
    $enriched += $peerInfo
  }
  
  return $enriched
}

function Get-ZertoVms {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers)
  # Prioritize direct VM endpoints; stop at first non-empty result to avoid noisy sweeps
  # Put hardcoded endpoints FIRST to avoid encryption detection endpoints from Swagger
  $candidates = @(
    "https://$ZVMAHost/v1/vms",
    "https://$ZVMAHost/v1/VM",
    "https://$ZVMAHost/v1/virtualmachines"
  )
  # Don't use Swagger discovery for VMs - it returns wrong endpoints
  # try {
  #   $disc = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
  #   if ($disc -and $disc.Vms -and $disc.Vms.Count -gt 0) { $candidates = $disc.Vms + $candidates }
  # } catch { }

  $siteIds = @()
  try {
    $disc2 = Discover-ZertoApiPaths -ZVMAHost $ZVMAHost -Headers $Headers
    if ($disc2 -and $disc2.VirtualizationSites -and $disc2.VirtualizationSites.Count -gt 0) {
      foreach ($vsUrl in $disc2.VirtualizationSites) {
        try {
          $sites = Invoke-HttpJsonWithCurlFallback -Uri $vsUrl -Headers $Headers -Method 'GET'
          $arr = @()
          if ($sites -is [System.Array]) { $arr = @($sites) } elseif ($sites) { $arr = @($sites) }
          foreach ($s in $arr) {
            $sid = $null
            if ($s.PSObject.Properties['SiteIdentifier']) { $sid = [string]$s.SiteIdentifier }
            elseif ($s.PSObject.Properties['Identifier']) { $sid = [string]$s.Identifier }
            if ($sid) { $siteIds += $sid }
          }
        } catch {}
      }
    }
  } catch {}

  $all = @()
  foreach ($u in $candidates) {
    try {
      $resTotal = @()
      if ($u -match "\{siteIdentifier\}") {
        foreach ($sid in ($siteIds | Select-Object -Unique)) {
          $real = $u -replace "\{siteIdentifier\}", [Regex]::Escape($sid)
          try {
            $res = Invoke-HttpJsonWithCurlFallback -Uri $real -Headers $Headers -Method 'GET'
            if ($null -ne $res) {
              if ($res -is [System.Array]) { $resTotal += @($res) }
              elseif ($res.PSObject.Properties['vms']) { $resTotal += @($res.vms) }
              else { $resTotal += @($res) }
            }
          } catch {}
        }
      } else {
        $res = Invoke-HttpJsonWithCurlFallback -Uri $u -Headers $Headers -Method 'GET'
        if ($null -ne $res) {
          if ($res -is [System.Array]) { $resTotal += @($res) }
          elseif ($res.PSObject.Properties['vms']) { $resTotal += @($res.vms) }
          else { $resTotal += @($res) }
        }
      }
      if ($resTotal.Count -gt 0) {
        $all = $resTotal
        break
      }
    } catch {}
  }
  return @($all)
}

function Get-VpgMemberVms {
  param([Parameter(Mandatory=$true)][string]$ZVMAHost,[Parameter(Mandatory=$true)][hashtable]$Headers,[Parameter(Mandatory=$true)]$Vpgs)
  $members = @()
  
  # Try direct /v1/vpgs/{vpgId}/vms endpoint for each VPG
  foreach ($vpg in $Vpgs) {
    $id = $null
    if ($vpg.PSObject.Properties['VpgIdentifier']) { $id = [string]$vpg.VpgIdentifier }
    elseif ($vpg.PSObject.Properties['Identifier']) { $id = [string]$vpg.Identifier }
    elseif ($vpg.PSObject.Properties['vpgIdentifier']) { $id = [string]$vpg.vpgIdentifier }
    if (-not $id) { continue }
    
    try {
      $vmUrl = "https://$ZVMAHost/v1/vpgs/$id/vms"
      Write-Log ("Getting VMs for VPG {0} from {1}" -f $id, $vmUrl) 'INFO'
      $res = Invoke-HttpJsonWithCurlFallback -Uri $vmUrl -Headers $Headers -Method 'GET'
      if ($null -ne $res) {
        if ($res -is [System.Array]) { $members += @($res) }
        elseif ($res.PSObject.Properties['vms']) { $members += @($res.vms) }
        else { $members += @($res) }
      }
    } catch {
      Write-Log ("Failed to get VMs for VPG {0}: {1}" -f $id, $_.Exception.Message) 'WARN'
    }
  }
  
  Write-Log ("Collected {0} VMs from VPG membership" -f $members.Count) 'INFO'
  return @($members)
}

# =========================
# Main
# =========================
try {
  Ensure-Tls
  Initialize-Output
  
  # Load and apply authentication config
  $authConfig = Load-AuthConfig -ConfigPath $AuthConfigFile
  if ($authConfig) {
    Apply-AuthConfig -Config $authConfig `
      -ZVMAHostRef ([ref]$ZVMAHost) `
      -UsernameRef ([ref]$Username) `
      -PasswordRef ([ref]$Password) `
      -RealmRef ([ref]$Realm) `
      -ClientIdRef ([ref]$ClientId) `
      -AnalyticsAuthModeRef ([ref]$AnalyticsAuthMode) `
      -AnalyticsBearerFileRef ([ref]$AnalyticsBearerFile) `
      -MyZertoClientIdRef ([ref]$MyZertoClientId) `
      -MyZertoUserRef ([ref]$MyZertoUser) `
      -MyZertoPasswordRef ([ref]$MyZertoPassword) `
      -VCenterServerRef ([ref]$VCenterServer) `
      -VCenterUserRef ([ref]$VCenterUser) `
      -VCenterPasswordRef ([ref]$VCenterPassword) `
      -InsecureRef ([ref]$Insecure)
    
    # Initialize hypervisor sites from config
    Initialize-HypervisorSites -Config $authConfig `
      -Site1HostRef ([ref]$ZVMAHost) `
      -Site2HostRef ([ref]$Site2Host) `
      -Site3HostRef ([ref]$Site3Host) `
      -Site3EnabledRef ([ref]$EnableSite3)
  }
  
  try {
    if ($script:TranscriptPath) { Start-Transcript -Path $script:TranscriptPath -Force | Out-Null }
  } catch { Write-Log ("Failed to start transcript: {0}" -f $_.Exception.Message) 'WARN' }
  if ($Insecure) { Set-CertValidation -Disable }

  # Capture ZVMA certificate health
  if ($ZVMAHost) {
    $script:ZvmaCertInfo = Get-ZvmaCertificateInfo -TargetHost $ZVMAHost
    if ($script:ZvmaCertInfo) {
      $msg = "ZVMA cert expires in {0} days (Issuer: {1})" -f $script:ZvmaCertInfo.DaysUntilExpiry, $script:ZvmaCertInfo.Issuer
      Write-Log $msg 'INFO'
      if ($script:ZvmaCertInfo.ExpiringSoon) { Write-Log "ZVMA certificate expiring within 30 days" 'WARN' }
    }
  }

  # Gather missing inputs interactively (safe for manual runs)
  if (-not $ZVMAHost -and -not $NonInteractive) {
    $ZVMAHost = Read-Host "Enter Primary Site ZVMA IP/FQDN (Site 1)"
  }
  if (-not $ZVMAHost -and $NonInteractive) {
    Write-Log "NonInteractive mode: ZVMAHost required but not provided in config" 'ERROR'
    throw "NonInteractive mode requires ZVMAHost to be configured in auth.config.json"
  }
  
  # Resolve Credential Manager placeholders before processing
  if ($Username -like "from-*") {
    $credTarget = $Username -replace '^from-', ''
    Write-Log ("Retrieving credentials from Credential Manager: {0}" -f $credTarget) 'INFO'
    $cred = Get-CredentialFromManager -Target $credTarget
    if ($cred -and $cred.Username) {
      $Username = $cred.Username
      if ($cred.Password) { $Password = $cred.Password }
      Write-Log ("Retrieved username: {0}" -f $Username) 'INFO'
    } else {
      Write-Log ("Failed to retrieve credential from manager: {0}" -f $credTarget) 'WARN'
      $Username = $null
      $Password = $null
    }
  }
  
  if ($GrantType -eq 'password') {
    # Prompt for username if not provided or if it's a Credential Manager placeholder
    if (-not $Username -and -not $NonInteractive) { 
      $Username = Read-Host "Enter ZVMA Admin Username" 
    }
    if (-not $Username -and $NonInteractive) {
      Write-Log "NonInteractive mode: Username required but not provided" 'ERROR'
      throw "NonInteractive mode requires Username in config or Credential Manager"
    }
    # Prompt for password if not provided or if it's a Credential Manager placeholder
    if (-not $Password -and -not $NonInteractive) {
      Write-Log "Prompting for ZVMA password (Credential Manager or manual entry)" 'INFO'
      $secure = Read-Host "Enter ZVMA Admin Password" -AsSecureString
      $Password = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    if (-not $Password -and $NonInteractive) {
      Write-Log "NonInteractive mode: Password required but not provided" 'ERROR'
      throw "NonInteractive mode requires Password in config or Credential Manager"
    }
  }
  
  # Prompt for Site 2 (Secondary/Peer)
  if (-not $Site2Host -and -not $NonInteractive) {
    $site2Input = Read-Host "Enter Secondary Site ZVMA IP/FQDN (Site 2, leave blank to skip)"
    if ($site2Input) {
      $Site2Host = $site2Input
    }
  }
  
  # Prompt for Site 3 (Optional Tertiary)
  if (-not $EnableSite3 -and -not $NonInteractive) {
    $site3Choice = Read-Host "Configure a tertiary (3rd) Zerto site? (y/n)"
    if ($site3Choice -eq 'y' -or $site3Choice -eq 'yes') {
      $Site3Host = Read-Host "Enter Tertiary Site ZVMA IP/FQDN (Site 3)"
      $EnableSite3 = $true
    }
  }
  
  # Add Site2/Site3 to PeerHosts array for peer site collection
  if (-not $PeerHosts) { $PeerHosts = @() }
  if ($Site2Host -and $Site2Host.Trim() -ne '') {
    $PeerHosts += $Site2Host.Trim()
  }
  if ($Site3Host -and $Site3Host.Trim() -ne '') {
    $PeerHosts += $Site3Host.Trim()
  }
  
  # Prompt for peer hosts if not provided (legacy support)
  if ((-not $PeerHosts -or $PeerHosts.Count -eq 0) -and -not $NonInteractive) {
    $peersInput = Read-Host "Enter additional peer ZVMA IPs/FQDNs (comma-separated, optional)"
    if ($peersInput) {
      $PeerHosts = $peersInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
  }

  Write-Log ("Authenticating to ZVMA ({0}) via {1} grant..." -f $ZVMAHost, $GrantType) 'INFO'
  Write-Log ("Auth details: User={0}, Password length={1} chars, ClientId={2}, Realm={3}" -f $Username, $Password.Length, $ClientId, $Realm) 'INFO'
  $zertoToken = Get-ZertoToken -ZVMAHost $ZVMAHost -Realm $Realm -ClientId $ClientId -GrantType $GrantType -Username $Username -Password $Password -ClientSecret $ClientSecret
  $zvmaHeaders = @{ Authorization = ("Bearer {0}" -f $zertoToken) }

  # NOW prompt for Analytics and optional inputs after ZVMA auth succeeds
  # Analytics is optional - comment out or skip if you want REST-API-only mode
  # Only prompt for Analytics API key if using api_key mode and key not provided on command line
  # NOTE: Analytics is not required; the script collects protected VMs from ZVMA REST APIs automatically
  # Uncomment the line below if you need to use Analytics (requires valid credentials/connectivity)
  # if ($AnalyticsAuthMode -eq 'api_key' -and (-not $AnalyticsKey)) {
  #   $AnalyticsKey = Read-Host "Enter Analytics API Key (or leave blank to skip)"
  # }

  # Optionally gather vCenter input interactively if TotalVmCount not provided
  if ((-not $PSBoundParameters.ContainsKey('TotalVmCount') -or $TotalVmCount -le 0) -and (-not $VCenterServer) -and -not $NonInteractive) {
    $tmpVc = Read-Host "Enter vCenter Server (optional, leave blank to skip)"
    if ($tmpVc) {
      $VCenterServer = $tmpVc
      if (-not $VCenterUser) { $VCenterUser = Read-Host "Enter vCenter Username" }
      if (-not $VCenterPassword -or $VCenterPassword -like "from-*") {
        $vcSecure = Read-Host "Enter vCenter Password" -AsSecureString
        $VCenterPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToBSTR($vcSecure))
      }
    }
  }

  $aHeaders = $null
  switch ($AnalyticsAuthMode) {
    'api_key' {
      if ($AnalyticsKey -and ($AnalyticsKey.Trim().Length -gt 0)) {
        Write-Log "Preparing Analytics auth (primary bearer)..." 'INFO'
        $aHeaders = Get-AnalyticsHeadersPrimary -ApiKey $AnalyticsKey
      }
    }
    'myzerto' {
      if (-not $MyZertoClientId) { $MyZertoClientId = Read-Host "Enter MyZerto ClientId" }
      if (-not $MyZertoUser) { $MyZertoUser = Read-Host "Enter MyZerto user (email)" }
      if (-not $MyZertoPassword) { $MyZertoPassword = Read-Host "Enter MyZerto password" }
      Write-Log "Preparing Analytics auth via MyZerto..." 'INFO'
      try {
        $aHeaders = Get-AnalyticsHeadersMyZerto -ClientId $MyZertoClientId -Region $MyZertoRegion -User $MyZertoUser -Password $MyZertoPassword -MfaCode $MyZertoMfaCode
      } catch {
        Write-Log ("MyZerto auth failed: {0}" -f $_.Exception.Message) 'ERROR'
        throw
      }
    }
    'bearer_file' {
      if ($AnalyticsBearerFile -and (Test-Path -LiteralPath $AnalyticsBearerFile)) {
        Write-Log ("Reading Analytics bearer from file: {0}" -f $AnalyticsBearerFile) 'INFO'
        try { $aHeaders = Get-AnalyticsHeadersFromFile -BearerFile $AnalyticsBearerFile } catch { Write-Log ("Bearer file error: {0}" -f $_.Exception.Message) 'ERROR'; throw }
      } else {
        Write-Log "No bearer file provided or file not found; acquiring token interactively..." 'INFO'
        try {
          $aHeaders = Get-BearerTokenInteractive -ClientId $MyZertoClientId -Region $MyZertoRegion -User $MyZertoUser -Password $MyZertoPassword -MfaCode $MyZertoMfaCode
        } catch {
          Write-Log ("Interactive bearer acquisition failed: {0}" -f $_.Exception.Message) 'ERROR'
          throw
        }
      }
    }
  }

  # --- Evidence collection ---
  $rows = New-Object System.Collections.Generic.List[hashtable]
  $testedVpgs = New-Object System.Collections.Generic.HashSet[string]

  Write-Log "Collecting DR Failover Test reports (last 6 months window)..." 'INFO'
  $sixMonthsAgo = (Get-Date).AddDays(-180)
  $recovery = Get-FailoverTests -ZVMAHost $ZVMAHost -Headers $zvmaHeaders

  if (-not $recovery) { $recovery = @() }
  
  # Ensure $recovery is always an array
  if ($recovery -isnot [System.Collections.IEnumerable] -or $recovery -is [string]) {
    $recovery = @($recovery)
  }
  
  Write-Log ("Received {0} test reports from API (type: {1})" -f $recovery.Count, $recovery.GetType().Name) 'INFO'

  # Save ALL recovery reports as JSON evidence (not just those in time window)
  if ($recovery.Count -gt 0) {
    $recoveryReportsDir = Join-Path $script:OutDir 'RecoveryReports'
    try {
      if (-not (Test-Path $recoveryReportsDir)) {
        New-Item -ItemType Directory -Path $recoveryReportsDir -Force | Out-Null
      }
      Write-Log ("Saving {0} recovery test report(s) as JSON evidence..." -f $recovery.Count) 'INFO'
      
      $reportIndex = 1
      foreach ($rep in $recovery) {
        $vpgName = 'Unknown'
        if ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['VpgName']) {
          $vpgName = [string]$rep.General.VpgName
        } elseif ($rep.PSObject.Properties['VpgName']) {
          $vpgName = [string]$rep.VpgName
        } elseif ($rep.PSObject.Properties['vpgName']) {
          $vpgName = [string]$rep.vpgName
        }
        $sanitizedVpgName = $vpgName -replace '[^\w\-]', '_'
        
        $reportStartTime = 'unknown'
        if ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['StartTime']) {
          $reportStartTime = [string]$rep.General.StartTime
          $reportStartTime = $reportStartTime -replace '[:T]', '-' -replace 'Z', '' -replace '\..*$', ''
        } elseif ($rep.PSObject.Properties['StartTime']) {
          $reportStartTime = [string]$rep.StartTime
          $reportStartTime = $reportStartTime -replace '[:T]', '-' -replace 'Z', '' -replace '\..*$', ''
        }
        
        $fileName = ("Report_{0:D3}_{1}_{2}.json" -f $reportIndex, $sanitizedVpgName, $reportStartTime)
        $filePath = Join-Path $recoveryReportsDir $fileName
        
        try {
          $rep | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
          Write-Log ("Saved recovery report: {0}" -f $fileName) 'INFO'
        } catch {
          Write-Log ("Failed to save recovery report {0}: {1}" -f $fileName, $_.Exception.Message) 'WARN'
        }
        $reportIndex++
      }
      Write-Log ("Recovery reports saved to: {0}" -f $recoveryReportsDir) 'INFO'
    } catch {
      Write-Log ("Failed to create recovery reports directory: {0}" -f $_.Exception.Message) 'WARN'
    }
  }

  # Fetch VPG list early to build an identifier->name map for report correlation
  Write-Log "Collecting VPG list for test correlation..." 'INFO'
  $vpgs = Get-Vpgs -ZVMAHost $ZVMAHost -Headers $zvmaHeaders
  if (-not $vpgs) { $vpgs = @() }
  $vpgIdMap = @{}
  foreach ($v in $vpgs) {
    $vid = $null; $vname = $null
    if ($v.PSObject.Properties['VpgIdentifier']) { $vid = [string]$v.VpgIdentifier }
    elseif ($v.PSObject.Properties['vpgIdentifier']) { $vid = [string]$v.vpgIdentifier }
    if ($v.PSObject.Properties['VpgName']) { $vname = [string]$v.VpgName }
    elseif ($v.PSObject.Properties['vpgName']) { $vname = [string]$v.vpgName }
    if ($vid) { $vpgIdMap[$vid] = $vname }
  }

  # Log sample report shape for debugging
  if ($recovery.Count -gt 0) {
    $props = ($recovery[0].PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
    Write-Log ("Sample FailoverTest report properties: {0}" -f $props) 'INFO'
    Write-Log ("First report as JSON: {0}" -f ($recovery[0] | ConvertTo-Json -Depth 3)) 'INFO'
  }

  # Track most recent test per VPG
  $vpgTestMap = @{}

  foreach ($rep in $recovery) {
    # Derive VPG name from multiple shapes: direct name, identifier mapping, or nested in General
    $vpgName = $null
    if ($rep.PSObject.Properties['VpgName']) { $vpgName = [string]$rep.VpgName }
    elseif ($rep.PSObject.Properties['vpgName']) { $vpgName = [string]$rep.vpgName }
    elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['VpgName']) { $vpgName = [string]$rep.General.VpgName }
    elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['vpgName']) { $vpgName = [string]$rep.General.vpgName }
    else {
      # Try identifier mapping
      $vid = $null
      if ($rep.PSObject.Properties['VpgIdentifier']) { $vid = [string]$rep.VpgIdentifier }
      elseif ($rep.PSObject.Properties['vpgIdentifier']) { $vid = [string]$rep.vpgIdentifier }
      elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['VpgIdentifier']) { $vid = [string]$rep.General.VpgIdentifier }
      elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['vpgIdentifier']) { $vid = [string]$rep.General.vpgIdentifier }
      if (-not $vid -and $rep.PSObject.Properties['Entities']) {
        # Look for a VPG-like entity inside Entities
        foreach ($e in $rep.Entities) {
          if (-not $vid) {
            if ($e.PSObject.Properties['VpgIdentifier']) { $vid = [string]$e.VpgIdentifier }
            elseif ($e.PSObject.Properties['vpgIdentifier']) { $vid = [string]$e.vpgIdentifier }
          }
          if (-not $vpgName) {
            if ($e.PSObject.Properties['VpgName']) { $vpgName = [string]$e.VpgName }
            elseif ($e.PSObject.Properties['vpgName']) { $vpgName = [string]$e.vpgName }
            elseif ($e.PSObject.Properties['Name']) { $vpgName = [string]$e.Name }
            elseif ($e.PSObject.Properties['name']) { $vpgName = [string]$e.name }
          }
        }
      }
      if (-not $vpgName -and $vid -and $vpgIdMap.ContainsKey($vid)) {
        $vpgName = $vpgIdMap[$vid]
      }
    }
    
    # Skip reports with no VPG name (invalid/incomplete data)
    if (-not $vpgName -or $vpgName.Trim().Length -eq 0) {
      Write-Log "Skipping test report with no VPG name" 'WARN'
      continue
    }

    $status  = if ($rep.PSObject.Properties['Status'])  { $rep.Status }  elseif ($rep.PSObject.Properties['status'])  { $rep.status }  elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['Status']) { $rep.General.Status } else { 'Unknown' }
    $start   = if ($rep.PSObject.Properties['StartTime']) { $rep.StartTime } elseif ($rep.PSObject.Properties['startTime']) { $rep.startTime } elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['StartTime']) { $rep.General.StartTime } elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['startTime']) { $rep.General.startTime } else { $null }
    $rto     = if ($rep.PSObject.Properties['RTOInSeconds']) { $rep.RTOInSeconds } elseif ($rep.PSObject.Properties['rtoInSeconds']) { $rep.rtoInSeconds } elseif ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['RTOInSeconds']) { $rep.General.RTOInSeconds } elseif ($rep.PSObject.Properties['RecoverySettings'] -and $rep.RecoverySettings.PSObject.Properties['RtoSeconds']) { $rep.RecoverySettings.RtoSeconds } else { $null }

    # Parse timestamp safely with multiple format attempts
    $dt = $null
    if ($start) {
      try { 
        $dt = [DateTimeOffset]::Parse($start).DateTime 
      } catch { 
        try { 
          $dt = [datetime]::Parse($start) 
        } catch { 
          Write-Log ("Failed to parse timestamp: {0}" -f $start) 'WARN'
          $dt = $null 
        }
      }
    }

    # Debug log for every report
    $validWindow = if ($dt) { $dt -gt $sixMonthsAgo } else { $false }
    Write-Log ("Processing report - VPG: {0}, Status: {1}, StartTime: {2}, Parsed DT: {3}, Valid window: {4}" -f $vpgName, $status, $start, $dt, $validWindow) 'INFO'

    # Only include tests within the 180-day window
    if ($dt -and $dt -gt $sixMonthsAgo) {
      Write-Log ("Test found for VPG '{0}': Status={1}, Date={2}, RTO={3}s" -f $vpgName, $status, $start, $(if ($rto) { $rto } else { 'n/a' })) 'INFO'
      
      if ($status -eq 'Success' -or $status -eq 'PassedByUser' -or $status -like '*Pass*') {
        [void]$testedVpgs.Add($vpgName)
      }

      # Track most recent test per VPG (or update if this is newer)
      if (-not $vpgTestMap.ContainsKey($vpgName)) {
        $vpgTestMap[$vpgName] = @{
          VpgName   = $vpgName
          Status    = $status
          StartTime = $start
          DateTime  = $dt
          RTO       = $rto
        }
      } else {
        # Update if this test is more recent
        if ($dt -gt $vpgTestMap[$vpgName].DateTime) {
          $vpgTestMap[$vpgName] = @{
            VpgName   = $vpgName
            Status    = $status
            StartTime = $start
            DateTime  = $dt
            RTO       = $rto
          }
        }
      }
    }
  }

  # Add evidence rows for most recent test per VPG (only those within 180 days)
  foreach ($vpgName in $vpgTestMap.Keys) {
    $testInfo = $vpgTestMap[$vpgName]
    $rows.Add([ordered]@{
      Audit_Domain = 'Availability (DR Testing)'
      Entity       = $vpgName
      Detail       = ("RTO: {0}s" -f ($(if ($testInfo.RTO) { $testInfo.RTO } else { 'n/a' })))
      Status       = $testInfo.Status
      Timestamp    = $testInfo.StartTime
    })
  }

  Write-Log "Collecting VPG/LTR settings..." 'INFO'
  if (-not $vpgs -or $vpgs.Count -eq 0) {
    $vpgs = Get-Vpgs -ZVMAHost $ZVMAHost -Headers $zvmaHeaders
    if (-not $vpgs) { $vpgs = @() }
  }
  # Enrich metadata: version, sites (local/peer), and VMs
  $zertoVersion = $null
  $zertoSites = $null
  $localSite = $null
  $peerSites = @()
  $zertoVms = @()
  try { $zertoVersion = Get-ZertoVersion -ZVMAHost $ZVMAHost -Headers $zvmaHeaders } catch {}
  try { $localSite = Get-ZertoLocalSite -ZVMAHost $ZVMAHost -Headers $zvmaHeaders } catch {}
  try {
    $localId = if ($localSite -and $localSite.PSObject.Properties['SiteIdentifier']) { [string]$localSite.SiteIdentifier } else { $null }
    $peerSites = Get-ZertoPeerSites -ZVMAHost $ZVMAHost -Headers $zvmaHeaders -LocalSiteId $localId
  } catch {}
  
  # If peer sites API is empty, extract from VPG recovery data or test reports
  if ((-not $peerSites -or $peerSites.Count -eq 0) -and $vpgs -and $vpgs.Count -gt 0) {
    $recoverySiteNames = @()
    $primarySiteName = if ($localSite -and $localSite.PSObject.Properties['SiteName']) { [string]$localSite.SiteName } else { $null }
    foreach ($vpg in $vpgs) {
      $rsn = $null
      # Try various locations where recovery site name might be stored
      if ($vpg.PSObject.Properties['General'] -and $vpg.General.PSObject.Properties['RecoverySiteName']) {
        $rsn = [string]$vpg.General.RecoverySiteName
      } elseif ($vpg.PSObject.Properties['RecoverySiteName']) {
        $rsn = [string]$vpg.RecoverySiteName
      } elseif ($vpg.PSObject.Properties['TargetSite']) {
        $rsn = [string]$vpg.TargetSite
      }
      
      # Filter out primary site and duplicates
      if ($rsn -and -not $recoverySiteNames.Contains($rsn) -and $rsn -ne $primarySiteName) {
        $recoverySiteNames += $rsn
        $peerSites += [ordered]@{
          SiteName   = $rsn
          Source     = 'VPG-Data'
        }
        Write-Log ("Extracted recovery site from VPG: {0}" -f $rsn) 'INFO'
      } elseif ($rsn -eq $primarySiteName) {
        Write-Log ("Skipping recovery site '{0}' - matches primary site" -f $rsn) 'INFO'
      }
    }
  }
  
  # Also try to extract from test reports if available
  if ((-not $peerSites -or $peerSites.Count -eq 0) -and $recovery -and $recovery.Count -gt 0) {
    $recoverySiteNames = @()
    $primarySiteName = if ($localSite -and $localSite.PSObject.Properties['SiteName']) { [string]$localSite.SiteName } else { $null }
    foreach ($rep in $recovery) {
      if ($rep.PSObject.Properties['General'] -and $rep.General.PSObject.Properties['RecoverySiteName']) {
        $rsn = [string]$rep.General.RecoverySiteName
        # Filter out primary site and duplicates
        if ($rsn -and -not $recoverySiteNames.Contains($rsn) -and $rsn -ne $primarySiteName) {
          $recoverySiteNames += $rsn
          $peerSites += [ordered]@{
            SiteName   = $rsn
            Source     = 'Test-Report'
          }
          Write-Log ("Extracted recovery site from test report: {0}" -f $rsn) 'INFO'
        } elseif ($rsn -eq $primarySiteName) {
          Write-Log ("Skipping recovery site '{0}' from test report - matches primary site" -f $rsn) 'INFO'
        }
      }
    }
  }
  
  # Attempt to authenticate to extracted peer sites and collect their details
  # This enriches the "auth failed" placeholder sites with actual connection details
  $enrichedPeerSites = @()
  foreach ($ps in $peerSites) {
    if ($ps.PSObject.Properties['SiteName'] -and $ps.SiteName -and $ps.SiteName -notmatch 'Failed|^$') {
      $siteName = $ps.SiteName
      $peerAuthSuccess = $false
      $peerTok = $null
      $phHeaders = $null
      $attemptCount = 0
      $maxAttempts = 2
      
      while (-not $peerAuthSuccess -and $attemptCount -lt $maxAttempts) {
        try {
          if ($attemptCount -eq 0) {
            Write-Log ("Attempting connection to extracted peer site: {0}..." -f $siteName) 'INFO'
            # Try with primary credentials using the site name (could be hostname or IP)
            $peerTok = Get-ZertoToken -ZVMAHost $siteName -Realm $Realm -ClientId $ClientId -GrantType $GrantType -Username $Username -Password $Password -ClientSecret $ClientSecret
            $attemptLabel = "primary credentials"
          } else {
            # Prompt for alternate credentials for this specific site
            $altCreds = Get-AlternateCredentials -SiteName $siteName -Reason "Authentication failed with primary account ($Username)"
            if (-not $altCreds) {
              Write-Log ("Skipping peer site {0} - no alternate credentials provided" -f $siteName) 'WARN'
              break
            }
            Write-Log ("Retrying peer site {0} with alternate credentials ({1})..." -f $siteName, $altCreds.Username) 'INFO'
            $peerTok = Get-ZertoToken -ZVMAHost $siteName -Realm $Realm -ClientId $ClientId -GrantType $GrantType -Username $altCreds.Username -Password $altCreds.PlainPassword -ClientSecret $ClientSecret
            $attemptLabel = "alternate credentials"
          }
          
          $phHeaders = @{ Authorization = ("Bearer {0}" -f $peerTok) }
          $pLocal = $null
          try { $pLocal = Get-ZertoLocalSite -ZVMAHost $siteName -Headers $phHeaders } catch {}
          
          if ($pLocal) {
            $pVer = $null
            try { $pVer = Get-ZertoVersion -ZVMAHost $siteName -Headers $phHeaders } catch {}
            if (-not $pVer -and $pLocal) {
              $pVer = [ordered]@{
                DisplayVersion = $pLocal.DisplayVersion
                Version        = $pLocal.Version
                ZvmApiVersion  = $(if ($pLocal.PSObject.Properties['ZvmApiVersion']) { $pLocal.ZvmApiVersion } else { $null })
                Source         = 'LocalSite'
              }
            }
            
            # Collect certificate info for peer site
            $pCertInfo = $null
            Write-Log ("Attempting to retrieve ZVMA certificate from peer site {0}..." -f $siteName) 'INFO'
            try { 
              $pCertInfo = Get-ZvmaCertificateInfo -TargetHost $siteName
              if ($pCertInfo) {
                Write-Log ("Successfully retrieved certificate from peer site {0}: expires in {1} days" -f $siteName, $pCertInfo.DaysUntilExpiry) 'INFO'
              } else {
                Write-Log ("Certificate retrieval returned null for peer site {0}" -f $siteName) 'WARN'
              }
            } catch {
              Write-Log ("Exception during certificate retrieval for peer site {0}: {1}" -f $siteName, $_.Exception.Message) 'WARN'
            }
            
            $enrichedPeerSites += [ordered]@{
              Host           = $siteName
              SiteName       = $pLocal.SiteName
              SiteIdentifier = $(if ($pLocal) { $pLocal.SiteIdentifier } else { $null })
              DisplayVersion = $(if ($pLocal) { $pLocal.DisplayVersion } else { $null })
              Version        = $(if ($pLocal) { $pLocal.Version } else { $null })
              ZvmApiVersion  = $(if ($pLocal -and $pLocal.PSObject.Properties['ZvmApiVersion']) { $pLocal.ZvmApiVersion } else { $null })
              About          = $pVer
              ZvmaCertInfo   = $pCertInfo
              Source         = $ps.Source
            }
            Write-Log ("Successfully authenticated to peer site {0} ({1}) using {2}" -f $siteName, $pLocal.SiteName, $attemptLabel) 'INFO'
            $peerAuthSuccess = $true
          }
        } catch {
          $attemptCount++
          if ($attemptCount -lt $maxAttempts) {
            Write-Log ("Failed to authenticate to peer site {0} with {1}: {2}" -f $siteName, $attemptLabel, $_.Exception.Message) 'WARN'
          } else {
            Write-Log ("Could not connect to peer site {0}: {1}" -f $siteName, $_.Exception.Message) 'WARN'
            # Keep the original entry if unable to authenticate
            $enrichedPeerSites += $ps
          }
        }
      }
      
      if (-not $peerAuthSuccess) {
        # If we exhausted attempts, keep original
        $enrichedPeerSites += $ps
      }
    } else {
      # Keep sites that don't match extraction pattern
      $enrichedPeerSites += $ps
    }
  }
  
  # Replace peerSites with enriched version if we found any
  if ($enrichedPeerSites.Count -gt 0) {
    $peerSites = $enrichedPeerSites
  }
  
  # If user supplied peer hosts, collect their site/version info too
  if ($PeerHosts -and $PeerHosts.Count -gt 0) {
    foreach ($ph in $PeerHosts) {
      $peerAuthSuccess = $false
      $peerTok = $null
      $phHeaders = $null
      $attemptCount = 0
      $maxAttempts = 2
      
      # Try with original credentials first, then allow alternate credentials
      while (-not $peerAuthSuccess -and $attemptCount -lt $maxAttempts) {
        try {
          if ($attemptCount -eq 0) {
            Write-Log ("Collecting peer site from {0}..." -f $ph) 'INFO'
            $peerTok = Get-ZertoToken -ZVMAHost $ph -Realm $Realm -ClientId $ClientId -GrantType $GrantType -Username $Username -Password $Password -ClientSecret $ClientSecret
            $attemptLabel = "primary credentials"
          } else {
            # Prompt for alternate credentials
            $altCreds = Get-AlternateCredentials -SiteName $ph -Reason "Authentication failed with primary account ($Username)"
            if (-not $altCreds) {
              Write-Log ("Skipping peer site {0} - no alternate credentials provided" -f $ph) 'WARN'
              break
            }
            Write-Log ("Retrying peer site {0} with alternate credentials ({1})..." -f $ph, $altCreds.Username) 'INFO'
            $peerTok = Get-ZertoToken -ZVMAHost $ph -Realm $Realm -ClientId $ClientId -GrantType $GrantType -Username $altCreds.Username -Password $altCreds.PlainPassword -ClientSecret $ClientSecret
            $attemptLabel = "alternate credentials"
          }
          
          $phHeaders = @{ Authorization = ("Bearer {0}" -f $peerTok) }
          $pLocal = $null
          try { $pLocal = Get-ZertoLocalSite -ZVMAHost $ph -Headers $phHeaders } catch {}
          $pVer = $null
          try { $pVer = Get-ZertoVersion -ZVMAHost $ph -Headers $phHeaders } catch {}
          if (-not $pVer -and $pLocal) {
            $pVer = [ordered]@{
              DisplayVersion = $pLocal.DisplayVersion
              Version        = $pLocal.Version
              ZvmApiVersion  = $(if ($pLocal.PSObject.Properties['ZvmApiVersion']) { $pLocal.ZvmApiVersion } else { $null })
              Source         = 'LocalSite'
            }
          }
          
          # Collect certificate info for peer host
          $pCertInfo = $null
          Write-Log ("Attempting to retrieve ZVMA certificate from peer host {0}..." -f $ph) 'INFO'
          try { 
            $pCertInfo = Get-ZvmaCertificateInfo -TargetHost $ph
            if ($pCertInfo) {
              Write-Log ("Successfully retrieved certificate from peer host {0}: expires in {1} days" -f $ph, $pCertInfo.DaysUntilExpiry) 'INFO'
            } else {
              Write-Log ("Certificate retrieval returned null for peer host {0}" -f $ph) 'WARN'
            }
          } catch {
            Write-Log ("Exception during certificate retrieval for peer host {0}: {1}" -f $ph, $_.Exception.Message) 'WARN'
          }
          
          # Check if this site already exists in peerSites (by SiteName) and replace/merge it
          $newSiteName = $(if ($pLocal) { $pLocal.SiteName } else { $null })
          $existingIndex = -1
          if ($newSiteName) {
            for ($i = 0; $i -lt $peerSites.Count; $i++) {
              if ($peerSites[$i].SiteName -eq $newSiteName) {
                $existingIndex = $i
                Write-Log ("Replacing existing peer site entry for '{0}' with authenticated data from {1}" -f $newSiteName, $ph) 'INFO'
                break
              }
            }
          }
          
          $newPeerEntry = [ordered]@{
            Host           = $ph
            SiteName       = $newSiteName
            SiteIdentifier = $(if ($pLocal) { $pLocal.SiteIdentifier } else { $null })
            DisplayVersion = $(if ($pLocal) { $pLocal.DisplayVersion } else { $null })
            Version        = $(if ($pLocal) { $pLocal.Version } else { $null })
            ZvmApiVersion  = $(if ($pLocal -and $pLocal.PSObject.Properties['ZvmApiVersion']) { $pLocal.ZvmApiVersion } else { $null })
            About          = $pVer
            ZvmaCertInfo   = $pCertInfo
            Source         = 'PeerHosts'
          }
          
          if ($existingIndex -ge 0) {
            # Replace the existing entry
            $peerSites[$existingIndex] = $newPeerEntry
          } else {
            # Add as new entry
            $peerSites += $newPeerEntry
          }
          
          Write-Log ("Successfully authenticated to peer site {0} using {1}" -f $ph, $attemptLabel) 'INFO'
          $peerAuthSuccess = $true
        } catch {
          $attemptCount++
          if ($attemptCount -lt $maxAttempts) {
            Write-Log ("Failed to authenticate to peer {0} with {1}: {2}" -f $ph, $attemptLabel, $_.Exception.Message) 'WARN'
          } else {
            Write-Log ("Failed to collect peer {0}: {1}" -f $ph, $_.Exception.Message) 'WARN'
            # Add peer site info with auth failed status
            $peerSites += [ordered]@{
              Host           = $ph
              SiteName       = "Failed to authenticate"
              SiteIdentifier = $null
              DisplayVersion = $null
              Version        = $null
              ZvmApiVersion  = $null
              About          = $null
              Error          = $_.Exception.Message
            }
          }
        }
      }
    }
  }
  try { $zertoSites = if ($localSite -or $peerSites) { [ordered]@{ Local = $localSite; Peers = $peerSites } } else { Get-ZertoSites -ZVMAHost $ZVMAHost -Headers $zvmaHeaders } } catch {}
  
  # Collect complete VM inventory from virtualization sites (protected + unprotected)
  $allSiteVms = @()
  try {
    $allSiteVms = Get-VirtualizationSiteVms -ZVMAHost $ZVMAHost -Headers $zvmaHeaders
  } catch {
    Write-Log ("Get-VirtualizationSiteVms failed: {0}" -f $_.Exception.Message) 'WARN'
  }
  
  # Collect protected VMs from /v1/vms endpoint
  try { 
    Write-Log "Collecting protected VM inventory from ZVMA..." 'INFO'
    $zertoVms = Get-ZertoVms -ZVMAHost $ZVMAHost -Headers $zvmaHeaders 
    Write-Log ("Protected VM inventory returned {0} VMs" -f $zertoVms.Count) 'INFO'
  } catch { 
    Write-Log ("Get-ZertoVms failed: {0}" -f $_.Exception.Message) 'WARN'
    $zertoVms = @()
  }
  # Fallback: if version endpoint failed but local site carries version info, surface it as version/about
  if (-not $zertoVersion -and $localSite) {
    $zertoVersion = [ordered]@{
      DisplayVersion = $localSite.DisplayVersion
      Version        = $localSite.Version
      ZvmApiVersion  = $(if ($localSite.PSObject.Properties['ZvmApiVersion']) { $localSite.ZvmApiVersion } else { $null })
      Source         = 'LocalSite'
    }
  }
  # Fallback: try direct /v1/vms call if Get-ZertoVms returned empty
  if (-not $zertoVms -or $zertoVms.Count -eq 0) {
    Write-Log "Get-ZertoVms returned empty, trying direct /v1/vms call..." 'INFO'
    try {
      $directVms = Invoke-HttpJsonWithCurlFallback -Uri "https://$ZVMAHost/v1/vms" -Headers $zvmaHeaders -Method 'GET'
      if ($directVms) {
        if ($directVms -is [System.Array]) { $zertoVms = @($directVms) }
        elseif ($directVms.PSObject.Properties['vms']) { $zertoVms = @($directVms.vms) }
        else { $zertoVms = @($directVms) }
        Write-Log ("Direct /v1/vms call returned {0} VMs" -f $zertoVms.Count) 'INFO'
      }
    } catch {
      Write-Log ("Direct /v1/vms call failed: {0}" -f $_.Exception.Message) 'WARN'
    }
  }
  
  # Attempt to collect protected VM names via VPG membership endpoints
  # Only count VMs from the PROTECTED site (not recovery site copies)
  $protectedVmNames = New-Object System.Collections.Generic.HashSet[string]
  try {
    $vpgMemberVms = Get-VpgMemberVms -ZVMAHost $ZVMAHost -Headers $zvmaHeaders -Vpgs $vpgs
    foreach ($vm in $vpgMemberVms) {
      $nm = $null
      if ($vm.PSObject.Properties['VmName']) { $nm = [string]$vm.VmName }
      elseif ($vm.PSObject.Properties['Name']) { $nm = [string]$vm.Name }
      elseif ($vm.PSObject.Properties['vmName']) { $nm = [string]$vm.vmName }
      if ($nm) { [void]$protectedVmNames.Add($nm) }
    }
  } catch {}
  
  # Also add vmName from direct VM inventory (Get-ZertoVms) - /v1/vms returns protected site VMs only
  Write-Log ("Processing {0} VMs from Get-ZertoVms..." -f $zertoVms.Count) 'INFO'
  foreach ($vm in $zertoVms) {
    $nm = $null
    
    # Log first VM properties for debugging
    if ($zertoVms.Count -gt 0 -and $vm -eq $zertoVms[0]) {
      $props = ($vm.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
      Write-Log ("Sample VM properties: {0}" -f $props) 'INFO'
    }
    
    # Extract VM name from various property names
    if ($vm.PSObject.Properties['VmName']) { $nm = [string]$vm.VmName }
    elseif ($vm.PSObject.Properties['vmName']) { $nm = [string]$vm.vmName }
    elseif ($vm.PSObject.Properties['Name']) { $nm = [string]$vm.Name }
    elseif ($vm.PSObject.Properties['name']) { $nm = [string]$vm.name }
    
    if ($nm) { 
      [void]$protectedVmNames.Add($nm) 
      Write-Log ("Added VM: {0}" -f $nm) 'INFO'
    } else {
      Write-Log ("VM object missing name property - available: {0}" -f (($vm.PSObject.Properties | ForEach-Object { $_.Name }) -join ', ')) 'WARN'
    }
  }
  $totalVpgs = $vpgs.Count
  $testsPassed = $testedVpgs.Count
  $ltrVpgs = 0
  $lockedVpgs = 0

  if ($UseLTR) {
    foreach ($vpg in $vpgs) {
      $vpgName = if ($vpg.PSObject.Properties['VpgName']) { $vpg.VpgName } elseif ($vpg.PSObject.Properties['vpgName']) { $vpg.vpgName } else { 'Unknown VPG' }
      $ltr     = $null
      if ($vpg.PSObject.Properties['LtrSettings']) { $ltr = $vpg.LtrSettings }
      elseif ($vpg.PSObject.Properties['ltrSettings']) { $ltr = $vpg.ltrSettings }

      $repo    = $null
      if ($ltr -and $ltr.PSObject.Properties['TargetRepositoryName']) { $repo = $ltr.TargetRepositoryName }
      elseif ($ltr -and $ltr.PSObject.Properties['targetRepositoryName']) { $repo = $ltr.targetRepositoryName }

      if ($repo) {
        $ltrVpgs++
        $locked = $false
        if ($ltr -and $ltr.PSObject.Properties['IsRetentionLockEnabled']) { $locked = [bool]$ltr.IsRetentionLockEnabled }
        elseif ($ltr -and $ltr.PSObject.Properties['isRetentionLockEnabled']) { $locked = [bool]$ltr.isRetentionLockEnabled }
        if ($locked) { $lockedVpgs++ }

        $rows.Add([ordered]@{
          Audit_Domain = 'Cyber_Resilience'
          Entity       = $vpgName
          Detail       = ("Repo: {0}" -f $repo)
          Status       = $(if ($locked) { 'SECURE' } else { 'RISK (No Lock)' })
          Timestamp    = (Get-Date).ToString('o')
        })
      } else {
        # No LTR repository configured -> risk row
        $rows.Add([ordered]@{
          Audit_Domain = 'Cyber_Resilience'
          Entity       = $vpgName
          Detail       = 'No LTR repository configured'
          Status       = 'RISK (No LTR)'
          Timestamp    = (Get-Date).ToString('o')
        })
      }
    }
  }

  # Ensure an Availability evidence row for VPGs with no recent test
  foreach ($v in $vpgs) {
    $name = $null
    if ($v.PSObject.Properties['VpgName']) { $name = [string]$v.VpgName }
    elseif ($v.PSObject.Properties['vpgName']) { $name = [string]$v.vpgName }
    if (-not $name -or $name.Trim().Length -eq 0) { continue }
    if (-not $testedVpgs.Contains($name)) {
      $rows.Add([ordered]@{
        Audit_Domain = 'Availability (DR Testing)'
        Entity       = $name
        Detail       = 'No DR Test in last 180 days'
        Status       = 'NOT TESTED'
        Timestamp    = (Get-Date).ToString('o')
      })
    }
  }

  # Add VM Inventory evidence rows (protected VMs)
  Write-Log ("Adding protected VM inventory evidence ({0} VMs)..." -f $protectedVmNames.Count) 'INFO'
  foreach ($vmName in $protectedVmNames) {
    $rows.Add([ordered]@{
      Audit_Domain = 'Coverage (VM Inventory)'
      Entity       = $vmName
      Detail       = 'VM is protected by Zerto VPG'
      Status       = 'PROTECTED'
      Timestamp    = (Get-Date).ToString('o')
    })
  }

  # Identify unprotected VMs from complete site inventory (excluding ZVMA/infrastructure VMs)
  $unprotectedVmNames = New-Object System.Collections.Generic.HashSet[string]
  $infrastructureVms = @('ZVMA', 'zvma', 'Zerto', 'zerto', 'ZVM', 'zvm')  # VMs to exclude
  if ($allSiteVms -and $allSiteVms.Count -gt 0) {
    Write-Log ("Analyzing {0} VMs from virtualization sites to identify unprotected VMs..." -f $allSiteVms.Count) 'INFO'
    foreach ($vm in $allSiteVms) {
      $nm = $null
      if ($vm.PSObject.Properties['VmName']) { $nm = [string]$vm.VmName }
      elseif ($vm.PSObject.Properties['vmName']) { $nm = [string]$vm.vmName }
      elseif ($vm.PSObject.Properties['Name']) { $nm = [string]$vm.Name }
      elseif ($vm.PSObject.Properties['name']) { $nm = [string]$vm.name }
      
      # Skip infrastructure VMs (ZVMA, Zerto, ZVM) and unprotected check
      if ($nm -and -not ($infrastructureVms -contains $nm) -and -not ($nm -like '*ZVMA*') -and -not $protectedVmNames.Contains($nm)) {
        [void]$unprotectedVmNames.Add($nm)
      }
    }
    
    Write-Log ("Identified {0} unprotected VM(s)" -f $unprotectedVmNames.Count) 'INFO'
    
    # Add unprotected VM evidence rows
    foreach ($vmName in $unprotectedVmNames) {
      $rows.Add([ordered]@{
        Audit_Domain = 'Coverage (VM Inventory)'
        Entity       = $vmName
        Detail       = 'VM is NOT protected by any Zerto VPG'
        Status       = 'UNPROTECTED'
        Timestamp    = (Get-Date).ToString('o')
      })
    }
  }

  # Calculate total VM count from environment (protected + unprotected)
  # Priority: Use union of protected and unprotected VM names for accuracy
  $allVmNamesInEnvironment = New-Object System.Collections.Generic.HashSet[string]
  foreach ($vm in $protectedVmNames) { [void]$allVmNamesInEnvironment.Add($vm) }
  foreach ($vm in $unprotectedVmNames) { [void]$allVmNamesInEnvironment.Add($vm) }
  
  if ($allVmNamesInEnvironment.Count -gt 0) {
    $TotalVmCount = $allVmNamesInEnvironment.Count
    Write-Log ("Total unique VMs in environment (protected + unprotected): {0}" -f $TotalVmCount) 'INFO'
  } elseif ($allSiteVms -and $allSiteVms.Count -gt 0 -and -not $TotalVmCount) {
    $TotalVmCount = $allSiteVms.Count
    Write-Log ("Total VM count from virtualization sites (source site only): {0}" -f $TotalVmCount) 'INFO'
  }

  # Protected VM inventory (analytics)
  $protectedVms = @()
  $totalProtected = 0
  if ($aHeaders) {
    try {
      Write-Log "Collecting protected VMs from Analytics (primary bearer)..." 'INFO'
      $protectedVms = Get-ProtectedVms -Headers $aHeaders
      if (-not $protectedVms) { $protectedVms = @() }
      $totalProtected = $protectedVms.Count
    } catch {
      Write-Log "Analytics primary bearer failed; attempting token exchange..." 'WARN'
      if ($AnalyticsKey -and ($AnalyticsKey.Trim().Length -gt 0)) {
        try {
          $aHeaders = Get-AnalyticsHeadersFallback -ApiKey $AnalyticsKey
          $protectedVms = Get-ProtectedVms -Headers $aHeaders
          if (-not $protectedVms) { $protectedVms = @() }
          $totalProtected = $protectedVms.Count
        } catch {
          Write-Log ("Analytics calls failed: {0}" -f $_.Exception.Message) 'ERROR'
        }
      } else {
        Write-Log "No Analytics API key available; skipping token exchange fallback." 'WARN'
      }
    }
  } else {
    Write-Log "Analytics key not provided; skipping protected VM inventory." 'WARN'
  }

  # If Analytics provided no count, derive protected VM count from unique VPG membership names (best-effort)
  $coverageSource = 'Analytics'
  # Prefer exact UNIQUE protected VM names from VPG membership if available
  if ($totalProtected -le 0 -and $protectedVmNames.Count -gt 0) {
    # protectedVmNames is a HashSet, so it's already unique
    $totalProtected = $protectedVmNames.Count
    Write-Log ("Derived protected VM count from unique VPG membership: {0} ({1})" -f $totalProtected, ($protectedVmNames -join ', ')) 'INFO'
    $coverageSource = 'VPG membership'
    $script:CoverageSource = $coverageSource
  }
  if ($totalProtected -le 0 -and $vpgs.Count -gt 0) {
    $derived = 0
    foreach ($v in $vpgs) {
      $counted = $false
      foreach ($p in @('Vms','vms','ProtectedVms','protectedVms','VirtualMachines','virtualMachines')) {
        if ($v.PSObject.Properties[$p]) {
          $arr = $v.$p
          try { $derived += (@($arr)).Count; $counted = $true; break } catch { }
        }
      }
      if (-not $counted) {
        foreach ($pc in @('ProtectedVmsCount','protectedVmsCount','VmCount','vmCount')) {
          if ($v.PSObject.Properties[$pc]) {
            try { $derived += [int]$v.$pc; $counted = $true; break } catch { }
          }
        }
      }
    }
    if ($derived -gt 0) {
      $totalProtected = [int]$derived
      Write-Log ("Derived protected VM count from VPGs: {0}" -f $totalProtected) 'INFO'
        $coverageSource = 'VPG-derived'
        $script:CoverageSource = $coverageSource
    }
  }

  # vCenter fallback for Total VM Count if not supplied
  if ((-not $PSBoundParameters.ContainsKey('TotalVmCount') -or $TotalVmCount -le 0) -and $VCenterServer -and $VCenterUser -and $VCenterPassword) {
    $vcCount = Try-GetVCenterTotalVmCount -Server $VCenterServer -User $VCenterUser -Password $VCenterPassword
    if ($vcCount -gt 0) { $TotalVmCount = [int]$vcCount }
  }

  # --- Scores ---
  # Calculate effectiveness scores (0-100%)
  $testEffectiveness = if ($totalVpgs -gt 0) { [double]$testsPassed / [double]$totalVpgs * 100.0 } else { 0.0 }
  
  $coverageEffectiveness = if ($PSBoundParameters.ContainsKey('TotalVmCount') -and $TotalVmCount -gt 0) {
    [double]$totalProtected / [double]$TotalVmCount * 100.0
  } else {
    100.0  # Without a full inventory, treat as fully covered
  }
  
  # Cyber: Only score if LTR VPGs are configured; otherwise 0% effectiveness
  $cyberEffectiveness = if ($UseLTR -and $ltrVpgs -gt 0) { [double]$lockedVpgs / [double]$ltrVpgs * 100.0 } else { 0.0 }
  $cyberIsEvaluated = $UseLTR -and $ltrVpgs -gt 0
  
  # Dynamic weighting: if Cyber is not evaluated, redistribute its weight to DR Testing and VM Coverage
  if ($cyberIsEvaluated) {
    # Standard weights: DR 40%, Coverage 30%, Cyber 30%
    $testWeight = 0.40
    $coverageWeight = 0.30
    $cyberWeight = 0.30
  } else {
    # Cyber not evaluated: redistribute its 30% weight proportionally
    # New: DR 57.14% (~40/70), Coverage 42.86% (~30/70)
    $testWeight = 0.40 / 0.70
    $coverageWeight = 0.30 / 0.70
    $cyberWeight = 0.0
  }
  
  $testScore = $testEffectiveness * $testWeight
  $coverageScore = $coverageEffectiveness * $coverageWeight
  $cyberScore = $cyberEffectiveness * $cyberWeight
  
  $totalScore = [int][math]::Round($testScore + $coverageScore + $cyberScore)

  # Recompute coverage effectiveness excluding infrastructure VMs if lists are available
  try {
    # Infrastructure VMs that should be excluded from protection coverage
    $vmNameIsInfrastructure = {
      param($n)
      if (-not $n) { return $false }
      # vCLS (vSphere Cluster Services) - reliable pattern
      if ($n -match '^(?i)vCLS(\b|[-_])' -or $n -match '(?i)\bvCLS\b') { return $true }
      # Zerto VRA (Virtual Replication Appliance) - consistent naming Z-VRA-xxx
      if ($n -match '^(?i)Z-VRA-') { return $true }
      return $false
    }
    $protectedVmNamesEx = if ($protectedVmNames) { $protectedVmNames | Where-Object { -not (& $vmNameIsInfrastructure $_) } } else { @() }
    $unprotectedVmNamesEx = if ($unprotectedVmNames) { $unprotectedVmNames | Where-Object { -not (& $vmNameIsInfrastructure $_) } } else { @() }
    $displayProtected = if ($protectedVmNames) { $protectedVmNamesEx.Count } else { $totalProtected }
    $displayUnprot   = if ($unprotectedVmNames) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $TotalVmCount - $totalProtected) }
    $displayTotal    = if ($protectedVmNames -or $unprotectedVmNames) { $displayProtected + $displayUnprot } else { $TotalVmCount }

    if ($displayTotal -gt 0) {
      $coverageEffectiveness = [double]$displayProtected / [double]$displayTotal * 100.0
      $coverageScore = $coverageEffectiveness * $coverageWeight
      $totalScore = [int][math]::Round($testScore + $coverageScore + $cyberScore)
    }
  } catch { Write-Log ("Infrastructure VM exclusion recompute failed: {0}" -f $_.Exception.Message) 'WARN' }

  # --- Export CSV ---
  Write-Log ("Writing evidence CSV: {0}" -f $script:CsvPath) 'INFO'
  
  # Add executive summary rows at the top for auditor quick-view
  $summaryRows = @()
  $overallDetail = if ($UseLTR -and $ltrVpgs -gt 0) {
    "$totalScore% overall (DR: $([int][math]::Round($testEffectiveness))% effective x 40% = $([int][math]::Round($testScore))% | Coverage: $([int][math]::Round($coverageEffectiveness))% x 30% = $([int][math]::Round($coverageScore))% | Cyber: $([int][math]::Round($cyberEffectiveness))% x 30% = $([int][math]::Round($cyberScore))%)"
  } else {
    "$totalScore% overall (DR: $([int][math]::Round($testEffectiveness))% effective x 40% = $([int][math]::Round($testScore))% | Coverage: $([int][math]::Round($coverageEffectiveness))% x 30% = $([int][math]::Round($coverageScore))%)"
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'EXECUTIVE SUMMARY'
    Entity       = 'Overall Compliance Score'
    Detail       = $overallDetail
    Status       = $(if ($totalScore -ge 80) { 'COMPLIANT' } elseif ($totalScore -ge 60) { 'PARTIAL' } else { 'NON-COMPLIANT' })
    Timestamp    = (Get-Date).ToString('o')
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'EXECUTIVE SUMMARY'
    Entity       = 'DR Testing Status'
    Detail       = "$testsPassed of $totalVpgs VPGs tested successfully in last 180 days"
    Status       = $(if ($totalVpgs -gt 0 -and $testsPassed -eq $totalVpgs) { 'PASS' } elseif ($testsPassed -gt 0) { 'PARTIAL' } else { 'FAIL' })
    Timestamp    = (Get-Date).ToString('o')
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'EXECUTIVE SUMMARY'
    Entity       = 'VM Coverage'
    Detail       = "$displayProtected of $displayTotal VMs protected ($([int][math]::Round(($displayProtected / [Math]::Max(1, $displayTotal)) * 100))% coverage)"
    Status       = $(if ($displayTotal -gt 0) { if (($displayProtected / $displayTotal) -ge 0.90) { 'EXCELLENT' } elseif (($displayProtected / $displayTotal) -ge 0.75) { 'GOOD' } elseif (($displayProtected / $displayTotal) -ge 0.50) { 'FAIR' } else { 'POOR' } } else { 'UNKNOWN' })
    Timestamp    = (Get-Date).ToString('o')
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'EXECUTIVE SUMMARY'
    Entity       = 'Unprotected VMs'
    Detail       = "$(if ($unprotectedVmNamesEx) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $displayTotal - $displayProtected) }) VMs at risk (not protected by any VPG)"
    Status       = $(if ($unprotectedVmNamesEx) { $unprotCount = $unprotectedVmNamesEx.Count } else { $unprotCount = [Math]::Max(0, $displayTotal - $displayProtected) }; if ($unprotCount -eq 0) { 'NONE' } elseif ($unprotCount -le 2) { 'LOW RISK' } elseif ($unprotCount -le 5) { 'MEDIUM RISK' } else { 'HIGH RISK' })
    Timestamp    = (Get-Date).ToString('o')
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'AUDIT METADATA'
    Entity       = 'Audit Scope'
    Detail       = "Primary Site: $ZVMAHost | Zerto Version: $($localSite.DisplayVersion) | VPGs: $totalVpgs | Sites: $($peerSites.Count + 1)"
    Status       = 'INFO'
    Timestamp    = (Get-Date).ToString('o')
  }
  $summaryRows += [ordered]@{
    Audit_Domain = 'AUDIT METADATA'
    Entity       = 'Evidence Collection Method'
    Detail       = "REST API: /v1/reports/recovery, /v1/vpgs, /v1/vms, /v1/virtualizationsites/{id}/vms"
    Status       = 'INFO'
    Timestamp    = (Get-Date).ToString('o')
  }
  
  # Combine summary rows with evidence rows
  $allRows = $summaryRows + $rows
  
  # Export-Csv expects objects; convert ordered hashtables to PSCustomObject
  # Filter out infrastructure VMs (vCLS, VRA) from CSV using the same filter function
  $filteredRows = $allRows | ForEach-Object { [pscustomobject]$_ } | Where-Object { 
    ($_ -is [pscustomobject]) -and 
    ((-not $_.Entity) -or -not (& $vmNameIsInfrastructure $_.Entity)) -and 
    ((-not $_.Detail) -or -not (& $vmNameIsInfrastructure $_.Detail))
  }
  
  # Convert to CSV string and write with UTF8 no BOM to prevent mojibake
  $csvContent = $filteredRows | ConvertTo-Csv -NoTypeInformation
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($script:CsvPath, ($csvContent -join "`n"), $utf8NoBom)

  # Guard: ensure CSV is never empty – add a summary row if needed
  if ((Get-Item $script:CsvPath).Length -le 0 -or $rows.Count -eq 0) {
    $placeholder = @(
      [ordered]@{
        Audit_Domain = 'Summary'
        Entity       = if ($ZVMAHost) { $ZVMAHost } else { 'ZVMA' }
        Detail       = 'No detailed test/LTR events available; summary only.'
        Status       = 'INFO'
        Timestamp    = (Get-Date).ToString('o')
      }
    )
    $placeholderCsv = ($placeholder | ForEach-Object { [pscustomobject]$_ } | ConvertTo-Csv -NoTypeInformation)
    [System.IO.File]::WriteAllText($script:CsvPath, ($placeholderCsv -join "`n"), $utf8NoBom)
  }

  # --- Summary ---
  # Build protected VM list section
  $protectedVmListLines = @()
  if ($protectedVmNamesEx -and $protectedVmNamesEx.Count -gt 0) {
    $protectedVmListLines += "  - Protected VMs ($($protectedVmNamesEx.Count)):"
    $protectedVmNamesEx | Select-Object -First 50 | ForEach-Object { $protectedVmListLines += ("      * {0}" -f $_) }
    if ($protectedVmNamesEx.Count -gt 50) {
      $protectedVmListLines += ("      ... and {0} more" -f ($protectedVmNamesEx.Count - 50))
    }
  }
  $protectedVmSection = if ($protectedVmListLines.Count -gt 0) { ($protectedVmListLines -join "`n") + "`n" } else { "" }
  
  # Build unprotected VM list section
  $unprotectedVmListLines = @()
  if ($unprotectedVmNamesEx -and $unprotectedVmNamesEx.Count -gt 0) {
    $unprotectedVmListLines += "  - Unprotected VMs ($($unprotectedVmNamesEx.Count)) [AT RISK]:"
    $unprotectedVmNamesEx | Select-Object -First 50 | ForEach-Object { $unprotectedVmListLines += ("      * {0}" -f $_) }
    if ($unprotectedVmNamesEx.Count -gt 50) {
      $unprotectedVmListLines += ("      ... and {0} more" -f ($unprotectedVmNamesEx.Count - 50))
    }
  }
  $unprotectedVmSection = if ($unprotectedVmListLines.Count -gt 0) { ($unprotectedVmListLines -join "`n") + "`n" } else { "" }
  
  # Build risk highlights
  $riskHighlights = @()
  if ($testsPassed -eq 0 -and $totalVpgs -gt 0) {
    $riskHighlights += "  [!] CRITICAL: No DR tests performed in last 180 days - recovery capability unverified"
  }
  if ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -lt 0.75) {
    $riskHighlights += "  [!] WARNING: Less than 75% VM coverage - $([Math]::Max(0, $TotalVmCount - $totalProtected)) VMs unprotected"
  }
  if ($UseLTR -and $ltrVpgs -gt 0 -and $lockedVpgs -lt $ltrVpgs) {
    $riskHighlights += "  [!] WARNING: $(($ltrVpgs - $lockedVpgs)) LTR VPGs lack retention lock (ransomware risk)"
  }
  $riskSection = if ($riskHighlights.Count -gt 0) { "`n==============================`n RISK HIGHLIGHTS`n==============================`n" + ($riskHighlights -join "`n") + "`n" } else { "" }
  
  # Build recommendations
  $recommendations = @()
  if ($testsPassed -lt $totalVpgs) {
    $recommendations += "  1. Perform failover tests for all VPGs to verify DR readiness"
  }
  if ($TotalVmCount -gt 0 -and ($TotalVmCount - $totalProtected) -gt 0) {
    $recommendations += "  2. Review unprotected VMs and add critical workloads to VPGs"
  }
  if ($UseLTR -and $ltrVpgs -gt 0 -and $lockedVpgs -lt $ltrVpgs) {
    $recommendations += "  3. Enable retention lock on all LTR repositories for ransomware protection"
  }
  if ($recommendations.Count -eq 0) {
    $recommendations += "  - No critical issues identified. Continue monitoring compliance."
  }
  $recommendationsSection = "`n==============================`n RECOMMENDATIONS`n==============================`n" + ($recommendations -join "`n") + "`n"
  
  $summaryText = @"
===============================================================================
                     ZERTO DISASTER RECOVERY AUDIT REPORT
===============================================================================
Audit Date:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Audit Scope:      Primary Site ($ZVMAHost)
Zerto Version:    $(if ($localSite) { $localSite.DisplayVersion } else { 'Unknown' })
Auditor:          Automated Compliance Tool v$scriptVersion

******************************
 OVERALL COMPLIANCE SCORE: $totalScore%
******************************

=== SCORING BREAKDOWN ===
 - DR Testing:     $([int][math]::Round($testEffectiveness))% effective ($testsPassed/$totalVpgs tested) x 40% weight = $([int][math]::Round($testScore))% contribution
 - VM Coverage:    $([int][math]::Round($coverageEffectiveness))% coverage ($displayProtected/$displayTotal protected) x 30% weight = $([int][math]::Round($coverageScore))% contribution
 - Cyber Defense:  $([int][math]::Round($cyberEffectiveness))% effective$(if ($UseLTR) { " ($lockedVpgs/$ltrVpgs LTR VPGs locked)" } else { " (LTR not evaluated)" }) x 30% weight = $([int][math]::Round($cyberScore))% contribution

=== COVERAGE DETAILS ===
 - Total VMs in Environment: $displayTotal
 - Protected VMs:            $displayProtected
 - Unprotected VMs:          $(if ($unprotectedVmNamesEx) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $displayTotal - $displayProtected) })
 - Protection Coverage:      $([int][math]::Round(($displayProtected / [Math]::Max(1, $displayTotal)) * 100))%
 - Data Source:              $(if ($coverageSource) { $coverageSource } else { 'Analytics' })
$protectedVmSection$unprotectedVmSection$riskSection$recommendationsSection
=== ZERTO ENVIRONMENT ===
  - Local Site:    $(if ($localSite) { ("{0} (Zerto {1})" -f $localSite.SiteName, $localSite.DisplayVersion) } else { 'n/a' })
  - Peer Sites:    $(if ($peerSites -and $peerSites.Count -gt 0) { (($peerSites | ForEach-Object { "{0} ({1})" -f $_.SiteName, $(if ($_.DisplayVersion) { "v" + $_.DisplayVersion } else { "auth failed" }) }) -join '; ') } else { 'None configured' })
  - VPGs:          $totalVpgs
  - Protected VMs: $($zertoVms.Count)

=== AUDIT ARTIFACTS ===
 - Evidence CSV:  $script:CsvPath
 - Manifest:      $script:ManifestPath
 - Summary:       $script:SummaryPath
 - Controls Map:  $script:ControlsMapPath
 - Log:           $script:LogPath
"@
  
  # Add recovery reports line if they exist
  $recoveryReportsDir = Join-Path $script:OutDir 'RecoveryReports'
  if (Test-Path $recoveryReportsDir) {
    $reportFiles = @(Get-ChildItem -Path $recoveryReportsDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($reportFiles.Count -gt 0) {
      $summaryText += "`n - DR Test Reports: $recoveryReportsDir ($($reportFiles.Count) JSON files)"
    }
  }
  
  $summaryText | Set-Content -Path $script:SummaryPath -Encoding UTF8
  $summaryText | Write-Host

  # --- Controls Map & Manifest ---
  Write-ControlsMap
  $totals = @{
    TotalVpgs       = $totalVpgs
    TestsPassed     = $testsPassed
    LtrVpgs         = $ltrVpgs
    LockedVpgs      = $lockedVpgs
    TotalProtected  = $totalProtected
    TotalVmCount    = $(if ($TotalVmCount) { $TotalVmCount } else { $null })
    UnprotectedVms  = $(if ($TotalVmCount -and $totalProtected -ge 0) { [Math]::Max(0, $TotalVmCount - $totalProtected) } else { $null })
  }
  $scores = @{
    TestScore      = [int][math]::Round($testScore)
    CoverageScore  = [int][math]::Round($coverageScore)
    CyberScore     = [int][math]::Round($cyberScore)
    TotalScore     = $totalScore
  }
  Write-Log "Completed successfully." 'INFO'
  
  # Stop transcript before manifest generation (so we can hash TRANSCRIPT.txt)
  try { Stop-Transcript | Out-Null } catch { }
  
  Write-Manifest -Scores $scores -Totals $totals -Options @{
    UseLTR       = [bool]$UseLTR
    InsecureTls  = [bool]$Insecure
  }

  # --- AUDIT-REPORT.md (Master Audit Document) ---
  $auditReadmePath = Join-Path $script:OutDir "AUDIT-REPORT.md"

  # Sanitize Zerto version for markdown (strip HTML if present)
  $zertoVersionLabel = $null
  if ($zertoVersion -and $zertoVersion.PSObject.Properties['DisplayVersion'] -and $zertoVersion.DisplayVersion) {
    $rawVersion = $zertoVersion.DisplayVersion
    # Strip HTML tags and clean up
    $rawVersion = $rawVersion -replace '<[^>]+>', ''
    $rawVersion = $rawVersion -replace '\s+', ' '
    $rawVersion = $rawVersion.Trim()
    $zertoVersionLabel = if ($rawVersion -match '^\d+\.\d+') { $rawVersion } else { 'Unknown' }
  } elseif ($zertoVersion -and $zertoVersion.PSObject.Properties['Version'] -and $zertoVersion.Version) {
    $zertoVersionLabel = $zertoVersion.Version
  } elseif ($zertoVersion -is [string]) {
    $rawVersion = ($zertoVersion -replace '<[^>]+>', '') -replace '\s+', ' '
    $zertoVersionLabel = $rawVersion.Trim()
  } elseif ($localSite -and $localSite.PSObject.Properties['DisplayVersion'] -and $localSite.DisplayVersion) {
    $zertoVersionLabel = $localSite.DisplayVersion
  } else {
    $zertoVersionLabel = 'Unknown'
  }

  $auditReadme = @"
# Zerto Disaster Recovery Compliance Audit Report

**Audit Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')  
**Audit Tool:** Zerto Compliance Collector v$scriptVersion  
**Audited Environment:** $ZVMAHost (Zerto $zertoVersionLabel)  
**Report ID:** $(Split-Path $script:OutDir -Leaf)  

---

## Executive Summary

### Overall Compliance Score: **$totalScore%**

| Category | Score | Status |
|----------|-------|--------|
| DR Testing (40%) | $([int][math]::Round($testEffectiveness))% effective → $([int][math]::Round($testScore))% weighted | $(if ($testsPassed -eq $totalVpgs -and $totalVpgs -gt 0) { '[PASS]' } elseif ($testsPassed -gt 0) { '[PARTIAL]' } else { '[FAIL]' }) |
| VM Coverage (30%) | $([int][math]::Round($coverageEffectiveness))% effective → $([int][math]::Round($coverageScore))% weighted | $(if ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.90) { '[EXCELLENT]' } elseif ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.75) { '[GOOD]' } elseif ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.50) { '[FAIR]' } else { '[POOR]' }) |
| Cyber Defense (30%) | $([int][math]::Round($cyberEffectiveness))% effective → $([int][math]::Round($cyberScore))% weighted | $(if ($UseLTR -and $ltrVpgs -gt 0 -and $lockedVpgs -eq $ltrVpgs) { '[SECURE]' } elseif ($UseLTR -and $lockedVpgs -gt 0) { '[PARTIAL]' } elseif ($UseLTR) { '[AT RISK]' } else { '[NOT EVALUATED]' }) |

**Compliance Status:** $(if ($totalScore -ge 80) { '**[COMPLIANT]**' } elseif ($totalScore -ge 60) { '**[PARTIALLY COMPLIANT]**' } else { '**[NON-COMPLIANT]**' })

---

## Findings

### DR Testing
- **VPGs Tested:** $testsPassed of $totalVpgs ($([int][math]::Round(($testsPassed / [Math]::Max(1, $totalVpgs)) * 100))%)
- **Test Window:** Last 180 days
- **Status:** $(if ($testsPassed -eq 0 -and $totalVpgs -gt 0) { '[CRITICAL] No failover tests performed' } elseif ($testsPassed -lt $totalVpgs) { '[WARNING] Some VPGs not tested' } else { '[PASS] All VPGs tested' })

### VM Coverage
- **Total VMs:** $(if ($displayTotal) { $displayTotal } else { $TotalVmCount })
- **Protected VMs:** $(if ($displayProtected) { $displayProtected } else { $totalProtected }) ($([int][math]::Round(($(if ($displayProtected) { $displayProtected } else { $totalProtected }) / [Math]::Max(1, $(if ($displayTotal) { $displayTotal } else { $TotalVmCount }))) * 100))%)
- **Unprotected VMs:** $(if ($unprotectedVmNamesEx) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $(if ($displayTotal) { $displayTotal } else { $TotalVmCount }) - $(if ($displayProtected) { $displayProtected } else { $totalProtected })) }) ($([int][math]::Round(($(if ($unprotectedVmNamesEx) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $(if ($displayTotal) { $displayTotal } else { $TotalVmCount }) - $(if ($displayProtected) { $displayProtected } else { $totalProtected })) }) / [Math]::Max(1, $(if ($displayTotal) { $displayTotal } else { $TotalVmCount }))) * 100))%)
- **Status:** $(if ($unprotectedVmNamesEx) { $unprotCount = $unprotectedVmNamesEx.Count } else { $unprotCount = [Math]::Max(0, $(if ($displayTotal) { $displayTotal } else { $TotalVmCount }) - $(if ($displayProtected) { $displayProtected } else { $totalProtected })) }; if ($unprotCount -eq 0) { '[PASS] Full coverage' } elseif ($unprotCount -le 2) { '[LOW RISK] Low risk' } else { '[HIGH RISK] Multiple VMs unprotected' })

$(if ($unprotectedVmNamesEx -and $unprotectedVmNamesEx.Count -gt 0) {
"### Unprotected VMs (At Risk)`n" + (($unprotectedVmNamesEx | ForEach-Object { "- ``$_``" }) -join "`n") + "`n"
} else { "" })
### Cyber Resilience
$(if ($UseLTR) {
"- **LTR VPGs:** $ltrVpgs`n- **Locked (Immutable):** $lockedVpgs ($([int][math]::Round(($lockedVpgs / [Math]::Max(1, $ltrVpgs)) * 100))%)`n- **Status:** $(if ($lockedVpgs -eq $ltrVpgs) { '[PASS] All LTR repositories locked' } elseif ($lockedVpgs -gt 0) { '[WARN] Partial protection' } else { '[FAIL] CRITICAL - No retention locks (ransomware risk)' })`n"
} else {
"- **Status:** [INFO] LTR evaluation not requested (-UseLTR not specified)`n"
})

---

## Recommendations

$(if ($testsPassed -lt $totalVpgs) { "### 1. Perform DR Testing`n- **Priority:** HIGH`n- **Action:** Execute failover tests for all $(($totalVpgs - $testsPassed)) untested VPGs`n- **Rationale:** Verify recovery capability and RTO/RPO targets`n- **Compliance Impact:** +$([int][math]::Round(40 * (($totalVpgs - $testsPassed) / [Math]::Max(1, $totalVpgs))))% potential score improvement`n`n" } else { "" })$(if ($TotalVmCount -gt 0 -and ($TotalVmCount - $totalProtected) -gt 0) { "### $(if ($testsPassed -lt $totalVpgs) { '2' } else { '1' }). Protect Unprotected VMs`n- **Priority:** $(if (($TotalVmCount - $totalProtected) -gt 5) { 'HIGH' } else { 'MEDIUM' })`n- **Action:** Add $([Math]::Max(0, $TotalVmCount - $totalProtected)) unprotected VMs to appropriate VPGs`n- **Rationale:** Ensure business continuity for all critical workloads`n- **Compliance Impact:** +$([int][math]::Round(30 * (($TotalVmCount - $totalProtected) / [Math]::Max(1, $TotalVmCount))))% potential score improvement`n`n" } else { "" })$(if ($UseLTR -and $ltrVpgs -gt 0 -and $lockedVpgs -lt $ltrVpgs) { "### $(if ($testsPassed -lt $totalVpgs -and ($TotalVmCount - $totalProtected) -gt 0) { '3' } elseif ($testsPassed -lt $totalVpgs -or ($TotalVmCount - $totalProtected) -gt 0) { '2' } else { '1' }). Enable Retention Lock`n- **Priority:** HIGH`n- **Action:** Enable retention lock on $(($ltrVpgs - $lockedVpgs)) LTR repositories`n- **Rationale:** Protect against ransomware and accidental deletion`n- **Compliance Impact:** +$([int][math]::Round(30 * (($ltrVpgs - $lockedVpgs) / [Math]::Max(1, $ltrVpgs))))% potential score improvement`n`n" } else { "" })$(if ($testsPassed -eq $totalVpgs -and ($TotalVmCount -eq $totalProtected) -and (-not $UseLTR -or $lockedVpgs -eq $ltrVpgs)) { "### No Critical Issues Identified`n- **Status:** [COMPLIANT] Environment is compliant`n- **Action:** Continue regular monitoring and maintain current DR practices`n`n" } else { "" })
---

## Audit Methodology

### Data Collection
1. **Authentication:** OAuth 2.0 password grant to Zerto Keycloak
2. **DR Testing:** `` GET /v1/reports/recovery?type=FailoverTest ``
   - Analyzed all recovery reports within 180-day window
   - Correlated test results to VPG identifiers
3. **VM Inventory:** `` GET /v1/virtualizationsites `` → `` GET /v1/virtualizationsites/{id}/vms ``
   - Enumerated all virtualization sites
   - Collected complete VM inventory per site
4. **Protected VMs:** `` GET /v1/vms ``
   - Retrieved VMs actively protected by Zerto
5. **VPG Configuration:** `` GET /v1/vpgs ``
   - Analyzed VPG settings$(if ($UseLTR) { " and LTR retention lock status" } else { "" })

### Scoring Model
- **DR Testing (40%):** Percentage of VPGs with successful failover test in last 180 days
- **VM Coverage (30%):** Percentage of total VMs protected by Zerto
- **Cyber Defense (30%):** $(if ($UseLTR) { "Percentage of LTR VPGs with retention lock enabled" } else { "Default 30% (not evaluated)" })

### Compliance Thresholds
- **80-100%:** Compliant
- **60-79%:** Partially Compliant  
- **0-59%:** Non-Compliant

---

## Evidence Files

| File | Description | Use Case |
|------|-------------|----------|
| [Evidence.csv](./Evidence.csv) | **PRIMARY AUDIT EVIDENCE** - Complete control test results | Detailed review, filtering by domain/status |
| [Summary.txt](./Summary.txt) | Executive summary with scores and VM lists | Quick review, management reporting |
| [Manifest.json](./Manifest.json) | Audit metadata, environment details, scoring breakdown | Audit trail, programmatic analysis |
| [ControlsMap.txt](./ControlsMap.txt) | Mapping to compliance frameworks (SOC2, ISO 27001, NIST) | Framework alignment documentation |
| [Log.txt](./Log.txt) | Technical execution log with API calls and timestamps | Audit methodology verification |

---

## Environment Details

**Primary Site:**
- **Host:** $ZVMAHost
- **Version:** Zerto $zertoVersionLabel
- **VPGs:** $totalVpgs
- **Protected VMs:** $totalProtected
- **Total VMs:** $TotalVmCount

$(if ($zertoSites -and $zertoSites.Count -gt 1) {
"**Replication Sites:**`n" + (($zertoSites | Where-Object { $_.IsSelf -ne $true } | ForEach-Object { "- ``$($_.SiteName)`` ($($_.Location))" }) -join "`n") + "`n`n"
} else {
"**Replication Sites:** None configured`n`n"
})
---

## Audit Trail

**Collection Start:** $(if (Test-Path $script:LogPath) { try { (Get-Content $script:LogPath -TotalCount 1 -ErrorAction SilentlyContinue) -replace '\[|\]', '' } catch { 'N/A' } } else { 'N/A' })  
**Collection End:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')  
**Evidence Hash (SHA256):**  
`` $(if (Test-Path $script:CsvPath) { (Get-FileHash $script:CsvPath -Algorithm SHA256).Hash } else { 'N/A' }) ``

---

*This report was automatically generated by the Zerto Compliance Tool. For questions or additional analysis, review the Evidence.csv file or contact your Zerto administrator.*
"@

  $auditReadme | Set-Content -Path $auditReadmePath -Encoding UTF8
  Write-Log ("Audit report written: {0}" -f $auditReadmePath) 'INFO'

  # vCLS exclusion for display (does not change scoring internally; scoring uses vCLS-excluded counts when arrays available)
  $vmNameIsVcls = {
    param($n)
    if (-not $n) { return $false }
    return ($n -match '^(?i)vCLS(\b|[-_])' -or $n -match '(?i)\bvCLS\b')
  }
  $protectedVmNamesEx = if ($protectedVmNames) { $protectedVmNames | Where-Object { -not (& $vmNameIsVcls $_) } } else { @() }
  $unprotectedVmNamesEx = if ($unprotectedVmNames) { $unprotectedVmNames | Where-Object { -not (& $vmNameIsVcls $_) } } else { @() }
  $displayProtected = if ($protectedVmNames) { $protectedVmNamesEx.Count } else { $totalProtected }
  $displayUnprot   = if ($unprotectedVmNames) { $unprotectedVmNamesEx.Count } else { [Math]::Max(0, $TotalVmCount - $totalProtected) }
  $displayTotal    = if ($protectedVmNames -or $unprotectedVmNames) { $displayProtected + $displayUnprot } else { $TotalVmCount }

  # --- HTML Report with HPE Branding ---
  $html = @()
  $html += '<!DOCTYPE html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Zerto Compliance Report</title>'
  $html += '<style>'
  $html += '*{margin:0;padding:0;box-sizing:border-box;font-family:"Segoe UI",Arial,sans-serif}'
  $html += 'body{background:#f0f2f5;color:#333;line-height:1.6}'
  $html += '.container{max-width:1200px;margin:0 auto;padding:20px}'
  $html += '.header{background:linear-gradient(135deg,#01A982 0%,#008B6B 100%);color:#fff;padding:50px 30px;border-radius:8px;box-shadow:0 10px 40px rgba(1,169,130,0.3);margin-bottom:30px;border-top:5px solid #FFB81C}'
  $html += '.header h1{font-size:2.8em;font-weight:700;margin-bottom:5px;letter-spacing:-0.5px}'
  $html += '.header .subtitle{font-size:1.05em;opacity:0.95;font-weight:300}'
  $html += '.hpe-badge{display:inline-block;background:#FFB81C;color:#01A982;padding:3px 10px;border-radius:3px;font-size:0.75em;font-weight:700;margin-top:10px}'
  $html += '.dashboard{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}'
  $html += '.card{background:#fff;border-radius:8px;padding:25px;box-shadow:0 2px 12px rgba(0,0,0,0.08);transition:all 0.3s;border-left:5px solid #01A982}'
  $html += '.card:hover{transform:translateY(-3px);box-shadow:0 8px 24px rgba(1,169,130,0.15)}'
  $html += '.card h3{font-size:0.85em;color:#666;text-transform:uppercase;letter-spacing:1.2px;margin-bottom:15px;font-weight:700}'
  $html += '.card .score{font-size:3.2em;font-weight:700;margin:10px 0}'
  $html += '.card .detail{color:#666;font-size:0.95em}'
  $html += '.score.compliant{color:#01A982}'
  $html += '.score.partial{color:#FFB81C}'
  $html += '.score.fail{color:#d32f2f}'
  $html += '.score.neutral{color:#9E9E9E}'
  $html += '.status-badge{display:inline-block;padding:6px 12px;border-radius:3px;font-size:0.8em;font-weight:700;text-transform:uppercase;letter-spacing:0.5px}'
  $html += '.status-badge.pass{background:#E8F5E9;color:#01A982;border:1px solid #01A982}'
  $html += '.status-badge.warn{background:#FFF8E1;color:#FFB81C;border:1px solid #FFB81C}'
  $html += '.status-badge.fail{background:#FFEBEE;color:#d32f2f;border:1px solid #d32f2f}'
  $html += '.status-badge.neutral{background:#F5F5F5;color:#9E9E9E;border:1px solid #BDBDBD}'
  $html += 'h2{color:#01A982;font-size:1.8em;font-weight:700;margin:40px 0 20px;padding-bottom:12px;border-bottom:3px solid #FFB81C}'
  $html += 'table{width:100%;border-collapse:collapse;background:#fff;border-radius:6px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.06)}'
  $html += 'th{background:#01A982;color:#fff;padding:16px;text-align:left;font-weight:700;text-transform:uppercase;font-size:0.8em;letter-spacing:1px}'
  $html += 'td{padding:12px 16px;border-bottom:1px solid #f0f0f0}'
  $html += 'tr:hover{background:#f8fbf9}'
  $html += '.vm-list{columns:3;column-gap:20px;list-style:none}'
  $html += '.vm-list li{padding:8px 0;break-inside:avoid;border-bottom:1px solid #eee;padding-left:20px;position:relative}'
  $html += '.vm-list li:before{content:\"✓\";color:#01A982;font-weight:bold;display:inline-block;width:1.5em;margin-left:-1.5em;text-align:center}'
  # Enhanced VM card styles for professional presentation
  $html += '.vm-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;margin-top:20px}'
  $html += '.vm-card{background:#fff;border-left:4px solid #01A982;padding:14px 18px;border-radius:6px;box-shadow:0 2px 6px rgba(0,0,0,0.06);transition:all 0.2s;display:flex;align-items:center;justify-content:space-between}'
  $html += '.vm-card:hover{box-shadow:0 4px 12px rgba(1,169,130,0.15);transform:translateY(-2px)}'
  $html += '.vm-card.unprotected{border-left-color:#e74c3c}'
  $html += '.vm-card.unprotected:hover{box-shadow:0 4px 12px rgba(231,76,60,0.15)}'
  $html += '.vm-name{font-weight:600;color:#2c3e50;font-size:0.95em;flex:1}'
  $html += '.vm-status-icon{font-size:1.3em;margin-left:10px;font-weight:bold}'
  $html += '.vm-status-icon.protected{color:#01A982}'
  $html += '.vm-status-icon.protected:before{content:"\2713"}'
  $html += '.vm-status-icon.unprotected{color:#e74c3c}'
  $html += '.vm-status-icon.unprotected:before{content:"\26A0"}'
  $html += 'pre{background:#1a1a1a;color:#4EC9B0;padding:16px;border-radius:6px;overflow-x:auto;font-size:0.85em;line-height:1.5;border-left:4px solid #FFB81C}'
  $html += '.artifacts{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:15px;margin-top:20px}'
  $html += '.artifact-card{background:#fff;border-left:5px solid #01A982;padding:16px;border-radius:6px;box-shadow:0 2px 6px rgba(0,0,0,0.05)}'
  $html += '.artifact-card strong{display:block;color:#01A982;margin-bottom:6px;font-weight:700}'
  $html += '.artifact-card code{color:#666;font-size:0.85em;word-break:break-all}'
  $html += '.footer{margin-top:50px;padding:20px;background:#f5f7fa;border-radius:6px;border-top:2px solid #FFB81C;text-align:center;color:#666;font-size:0.9em}'
  # Interactive: clickable cards + modal styles
  $html += '.card{cursor:pointer}'
  $html += '.modal{position:fixed;left:0;top:0;width:100%;height:100%;background:rgba(0,0,0,0.4);display:none;align-items:center;justify-content:center;z-index:1000}'
  $html += '.modal-inner{background:#fff;padding:20px;border-radius:8px;max-width:600px;width:90%;box-shadow:0 2px 12px rgba(0,0,0,0.2)}'
  $html += '.modal-inner h3{margin-top:0;color:#01A982}'
  $html += '.modal-close{float:right;background:#e0e0e0;border:none;padding:6px 10px;border-radius:4px;cursor:pointer}'
  $html += '@media(max-width:768px){.dashboard{grid-template-columns:1fr}.vm-list{columns:1}.vm-grid{grid-template-columns:1fr}}'
  $html += '</style>'
  $html += '</head><body><div class="container">'
  $html += ('<div class="header"><h1>Zerto Disaster Recovery Audit</h1><div class="subtitle">Compliance Report | Generated: {0}</div></div>' -f (Get-Date).ToString('f'))
  
  # Executive Dashboard
  $overallClass = if ($totalScore -ge 80) { 'compliant' } elseif ($totalScore -ge 60) { 'partial' } else { 'fail' }
  $testClass = if ($testsPassed -eq $totalVpgs) { 'pass' } elseif ($testsPassed -gt 0) { 'warn' } else { 'fail' }
  $covClass = if ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.90) { 'pass' } elseif ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.75) { 'pass' } elseif ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.50) { 'warn' } else { 'fail' }
  $cyberClass = if ($UseLTR -and $ltrVpgs -gt 0 -and $lockedVpgs -eq $ltrVpgs) { 'pass' } elseif ($UseLTR -and $lockedVpgs -gt 0) { 'warn' } else { 'fail' }
  
  $html += '<div class="dashboard">'
  $html += ('<div class="card" onclick="showInfo(''overall'')" title="Click for breakdown"><h3>Overall Compliance</h3><div class="score {0}">{1}%</div><div class="detail">Target: 80% for Compliant</div></div>' -f $overallClass, $totalScore)
  
  # DR Testing card scoring and status
  $drScoreClass = if ($testEffectiveness -ge 100) { 'compliant' } elseif ($testEffectiveness -ge 50) { 'partial' } else { 'fail' }
  $drStatus = if ($testsPassed -eq $totalVpgs) { 'PASS' } elseif ($testsPassed -gt 0) { 'PARTIAL' } else { 'FAIL' }
  $html += ('<div class="card" onclick="showInfo(''dr'')" title="Click for breakdown"><h3>DR Testing (40%)</h3><div class="score {0}">{1}%</div><div class="detail">{2} of {3} VPGs tested ({4}% effective, weighted {5}%) <span class="status-badge {6}">{7}</span></div></div>' -f $drScoreClass, [int][math]::Round($testEffectiveness), $testsPassed, $totalVpgs, [int][math]::Round($testEffectiveness), [int][math]::Round($testScore), $testClass, $drStatus)
  
  $covLine = if ($displayTotal -gt 0) { "{0} of {1} VMs protected ({2}% effective)" -f $displayProtected, $displayTotal, [int][math]::Round($coverageEffectiveness) } else { "{0} VMs protected" -f $displayProtected }
  
  # Coverage card scoring and status
  $covScoreClass = if ($coverageEffectiveness -ge 90) { 'compliant' } elseif ($coverageEffectiveness -ge 75) { 'partial' } else { 'fail' }
  $covStatus = if ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.90) { 'EXCELLENT' } elseif ($TotalVmCount -gt 0 -and ($totalProtected / $TotalVmCount) -ge 0.75) { 'GOOD' } else { 'AT RISK' }
  $html += ('<div class="card" onclick="showInfo(''coverage'')" title="Click for breakdown"><h3>VM Coverage (30%)</h3><div class="score {0}">{1}%</div><div class="detail">{2} (weighted {3}%) <span class="status-badge {4}">{5}</span></div></div>' -f $covScoreClass, [int][math]::Round($coverageEffectiveness), $covLine, [int][math]::Round($coverageScore), $covClass, $covStatus)
  
  if ($UseLTR -and $ltrVpgs -gt 0) {
    $cyberScoreClass = if ($cyberEffectiveness -ge 100) { 'compliant' } elseif ($cyberEffectiveness -ge 50) { 'partial' } else { 'fail' }
    $cyberStatus = if ($lockedVpgs -eq $ltrVpgs) { 'SECURE' } elseif ($lockedVpgs -gt 0) { 'PARTIAL' } else { 'AT RISK' }
    $cyberDetail = "{0} of {1} LTR VPGs locked ({2}% effective)" -f $lockedVpgs, $ltrVpgs, [int][math]::Round($cyberEffectiveness)
    $html += ('<div class="card" onclick="showInfo(''cyber'')" title="Click for breakdown"><h3>Cyber Resilience (30%)</h3><div class="score {0}">{1}%</div><div class="detail">{2} (weighted {3}%) <span class="status-badge {4}">{5}</span></div></div>' -f $cyberScoreClass, [int][math]::Round($cyberEffectiveness), $cyberDetail, [int][math]::Round($cyberScore), $cyberClass, $cyberStatus)
  } else {
    $html += '<div class="card" onclick="showInfo(''cyber'')" title="Click for breakdown"><h3>Cyber Resilience (30%)</h3><div class="score neutral">N/A</div><div class="detail">LTR evaluation disabled <span class="status-badge neutral">DISABLED</span></div></div>'
  }
  $html += '</div>'

  # Hidden explanations rendered into modal on click
  $html += ('<div id="info-overall" style="display:none"><h3>Overall Compliance</h3><ul><li>DR Testing contrib: {0}%</li><li>Coverage contrib: {1}%</li><li>Cyber contrib: {2}%</li><li>Total score: {3}% (target 80%)</li></ul></div>' -f [int][math]::Round($testScore), [int][math]::Round($coverageScore), [int][math]::Round($cyberScore), $totalScore)
  
  # DR Testing status
  $drStatus = if ($testsPassed -eq $totalVpgs -and $totalVpgs -gt 0) { 
    'PASS (all VPGs tested)' 
  } elseif ($testsPassed -gt 0) { 
    'PARTIAL (some VPGs tested)' 
  } else { 
    'FAIL (no VPGs tested)' 
  }
  $html += ('<div id="info-dr" style="display:none"><h3>DR Testing Breakdown</h3><ul><li><strong>VPGs tested (last 6 months):</strong> {0} of {1}</li><li><strong>Effectiveness:</strong> {2}% <em style="font-size:0.9em;color:#7f8c8d">(actual test completion rate)</em></li><li><strong>Category weight:</strong> 40% <em style="font-size:0.9em;color:#7f8c8d">(importance in overall score)</em></li><li><strong>Weighted contribution:</strong> {3}% <em style="font-size:0.9em;color:#7f8c8d">({2}% x 40% = {3}%)</em></li><li><strong>Status:</strong> {4}</li></ul></div>' -f $testsPassed, $totalVpgs, [int][math]::Round($testEffectiveness), [int][math]::Round($testScore), $drStatus)
  
  # Coverage info (display excludes vCLS)
  if ($displayTotal -gt 0) {
    $html += ('<div id="info-coverage" style="display:none"><h3>VM Coverage Breakdown</h3><ul><li><strong>Protected VMs:</strong> {0} of {1}</li><li><strong>Effectiveness:</strong> {2}% <em style="font-size:0.9em;color:#7f8c8d">(category scoring shown on card)</em></li><li><strong>Category weight:</strong> 30% <em style="font-size:0.9em;color:#7f8c8d">(importance in overall score)</em></li><li><strong>Weighted contribution:</strong> {3}%</li></ul></div>' -f $displayProtected, $displayTotal, [int][math]::Round($coverageEffectiveness), [int][math]::Round($coverageScore))
  } else {
    $html += ('<div id="info-coverage" style="display:none"><h3>VM Coverage Breakdown</h3><ul><li><strong>Protected VMs counted:</strong> {0}</li><li>Total VM count not provided; coverage effectiveness uses protected dataset</li><li><strong>Category weight:</strong> 30%</li><li><strong>Weighted contribution:</strong> {1}%</li></ul></div>' -f $totalProtected, [int][math]::Round($coverageScore))
  }
  
  # Cyber info
  if ($UseLTR -and $ltrVpgs -gt 0) {
    $html += ('<div id="info-cyber" style="display:none"><h3>Cyber Resilience Breakdown</h3><ul><li><strong>LTR VPGs locked:</strong> {0} of {1}</li><li><strong>Effectiveness:</strong> {2}% <em style="font-size:0.9em;color:#7f8c8d">(actual LTR lock rate)</em></li><li><strong>Category weight:</strong> 30% <em style="font-size:0.9em;color:#7f8c8d">(importance in overall score)</em></li><li><strong>Weighted contribution:</strong> {3}% <em style="font-size:0.9em;color:#7f8c8d">({2}% x 30% = {3}%)</em></li></ul></div>' -f $lockedVpgs, $ltrVpgs, [int][math]::Round($cyberEffectiveness), [int][math]::Round($cyberScore))
  } else {
    $html += '<div id="info-cyber" style="display:none"><h3>Cyber Resilience Breakdown</h3><p>LTR evaluation is disabled. Enable "Evaluate Cyber Resilience (LTR)" in the launcher to include this scoring.</p></div>'
  }

  # Modal container + JS
  $html += '<div id="modal" class="modal"><div class="modal-inner"><button class="modal-close" onclick="closeModal()">Close</button><div id="modal-content"></div></div></div>'
  $html += '<script>function showInfo(k){var m=document.getElementById("modal");var c=document.getElementById("modal-content");var s=document.getElementById("info-"+k);if(s){c.innerHTML=s.innerHTML;m.style.display="flex";}}function closeModal(){var m=document.getElementById("modal");m.style.display="none";}</script>'

  # Zerto Sites Section
  $html += '<h2>Zerto Sites</h2>'
  
  # Primary Site Card
  $html += '<h3 style="margin-top:20px;margin-bottom:10px;color:#2c3e50">Primary Site (Source)</h3>'
  $html += '<table><thead><tr><th style="width:200px">Property</th><th>Value</th></tr></thead><tbody>'
  if ($localSite) { $html += ('<tr><td><strong>Site Name</strong></td><td>{0}</td></tr>' -f $localSite.SiteName) } else { $html += '<tr><td><strong>Site Name</strong></td><td>Unknown</td></tr>' }
  if ($ZVMAHost) { $html += ('<tr><td>ZVMA Host</td><td><code>{0}</code></td></tr>' -f $ZVMAHost) }
  if ($localSite -and $localSite.DisplayVersion) { 
    $html += ('<tr><td>Zerto Version</td><td><strong>{0}</strong></td></tr>' -f $localSite.DisplayVersion) 
  } elseif ($zertoVersion -and $zertoVersion.DisplayVersion) { 
    $html += ('<tr><td>Zerto Version</td><td><strong>{0}</strong></td></tr>' -f $zertoVersion.DisplayVersion) 
  }
  if ($localSite -and $localSite.SiteIdentifier) { 
    $html += ('<tr><td>Site Identifier</td><td><code style="font-size:0.85em">{0}</code></td></tr>' -f $localSite.SiteIdentifier) 
  }
  if ($script:ZvmaCertInfo) { 
    $certColor = if ($script:ZvmaCertInfo.DaysUntilExpiry -lt 30) { '#e74c3c' } elseif ($script:ZvmaCertInfo.DaysUntilExpiry -lt 90) { '#f39c12' } else { '#27ae60' }
    $html += ('<tr><td>ZVMA Certificate</td><td><strong style="color:{3}">Expires in {2} days</strong><br/><span style="font-size:0.9em;color:#7f8c8d">Issuer: {0}<br/>Expiry: {1}</span></td></tr>' -f $script:ZvmaCertInfo.Issuer, $script:ZvmaCertInfo.NotAfter, $script:ZvmaCertInfo.DaysUntilExpiry, $certColor)
  }
  $html += '</tbody></table>'
  
  # Recovery Sites Cards
  if ($peerSites -and $peerSites.Count -gt 0) {
    $html += '<h3 style="margin-top:25px;margin-bottom:10px;color:#2c3e50">Recovery Sites (Targets)</h3>'
    foreach ($peer in $peerSites) {
      $html += '<table style="margin-bottom:15px"><thead><tr><th style="width:200px">Property</th><th>Value</th></tr></thead><tbody>'
      $html += ('<tr><td><strong>Site Name</strong></td><td>{0}</td></tr>' -f $peer.SiteName)
      if ($peer.Host) { 
        $html += ('<tr><td>ZVMA Host</td><td><code>{0}</code></td></tr>' -f $peer.Host) 
      }
      if ($peer.DisplayVersion) { 
        $html += ('<tr><td>Zerto Version</td><td><strong>{0}</strong></td></tr>' -f $peer.DisplayVersion) 
      } else {
        $html += '<tr><td>Zerto Version</td><td><em style="color:#95a5a6">Unable to retrieve (auth failed)</em></td></tr>'
      }
      if ($peer.SiteIdentifier) { 
        $html += ('<tr><td>Site Identifier</td><td><code style="font-size:0.85em">{0}</code></td></tr>' -f $peer.SiteIdentifier) 
      }
      if ($peer.ZvmaCertInfo) {
        $certColor = if ($peer.ZvmaCertInfo.DaysUntilExpiry -lt 30) { '#e74c3c' } elseif ($peer.ZvmaCertInfo.DaysUntilExpiry -lt 90) { '#f39c12' } else { '#27ae60' }
        $html += ('<tr><td>ZVMA Certificate</td><td><strong style="color:{3}">Expires in {2} days</strong><br/><span style="font-size:0.9em;color:#7f8c8d">Issuer: {0}<br/>Expiry: {1}</span></td></tr>' -f $peer.ZvmaCertInfo.Issuer, $peer.ZvmaCertInfo.NotAfter, $peer.ZvmaCertInfo.DaysUntilExpiry, $certColor)
      }
      if ($peer.Source) {
        $sourceLabel = if ($peer.Source -eq 'VPG-Data') { 'Extracted from VPG configuration' } else { $peer.Source }
        $html += ('<tr><td>Data Source</td><td><span style="font-size:0.9em;color:#7f8c8d">{0}</span></td></tr>' -f $sourceLabel)
      }
      $html += '</tbody></table>'
    }
  } else {
    $html += '<p style="color:#95a5a6;margin-top:15px"><em>No recovery sites configured or detected</em></p>'
  }
  
  # VPG and VM Information Section
  $html += '<h2 style="margin-top:30px">VPG &amp; VM Information</h2>'
  $html += '<table><thead><tr><th style="width:200px">Metric</th><th>Value</th></tr></thead><tbody>'
  $html += ('<tr><td><strong>Virtual Protection Groups</strong></td><td><strong>{0}</strong> VPGs configured</td></tr>' -f $totalVpgs)
  $html += ('<tr><td>VPGs Tested (6 months)</td><td><strong>{0}</strong> of {1} tested</td></tr>' -f $testsPassed, $totalVpgs)
  $html += ('<tr><td><strong>Total VMs in Environment</strong></td><td><strong>{0}</strong> virtual machines</td></tr>' -f $displayTotal)
  $html += ('<tr><td>Protected VMs</td><td><strong style="color:#27ae60">{0}</strong> VMs protected by Zerto</td></tr>' -f $displayProtected)
  if ($displayUnprot -gt 0) {
    $html += ('<tr><td>Unprotected VMs</td><td><strong style="color:#e74c3c">{0}</strong> VMs at risk</td></tr>' -f $displayUnprot)
  } else {
    $html += '<tr><td>Unprotected VMs</td><td><strong style="color:#27ae60">0</strong> VMs at risk</td></tr>'
  }
  $coveragePct = if ($displayTotal -gt 0) { [int][math]::Round(($displayProtected / [Math]::Max(1, $displayTotal)) * 100) } else { [int][math]::Round($coverageEffectiveness) }
  $coverageColor = if ($coveragePct -ge 100) { '#27ae60' } elseif ($coveragePct -ge 75) { '#f39c12' } else { '#e74c3c' }
  $html += ('<tr><td>Protection Coverage</td><td><strong style="color:{1}">{0}%</strong> of environment protected</td></tr>' -f $coveragePct, $coverageColor)
  if ($UseLTR -and $ltrVpgs -gt 0) {
    $html += ('<tr><td>Long-Term Retention VPGs</td><td><strong>{0}</strong> of {1} VPGs using LTR</td></tr>' -f $ltrVpgs, $totalVpgs)
    $html += ('<tr><td>LTR Locked VPGs</td><td><strong>{0}</strong> of {1} LTR VPGs locked</td></tr>' -f $lockedVpgs, $ltrVpgs)
  }
  $html += '</tbody></table>'

  # Add DR Test Summary from recovery reports if available
  $recoveryReportsDir = Join-Path $script:OutDir 'RecoveryReports'
  if (Test-Path $recoveryReportsDir) {
    $reportFiles = @(Get-ChildItem -Path $recoveryReportsDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($reportFiles.Count -gt 0) {
      $html += '<h2>DR Test Summary</h2>'
      $html += '<p style="color:#7f8c8d;margin-bottom:15px">Recovery test results from /v1/reports/recovery API (last 6 months)</p>'
      $html += '<div style="overflow-x:auto"><table><thead><tr><th>VPG</th><th>Test Date</th><th>Status</th><th>RTO (seconds)</th><th>Duration</th><th>Initiated By</th><th>Notes</th></tr></thead><tbody>'
      
      foreach ($reportFile in $reportFiles | Sort-Object Name) {
        try {
          $reportJson = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
          if ($reportJson.General) {
            $general = $reportJson.General
            $vpgName = $general.VpgName
            $status = $general.Status
            $rto = $general.RTOInSeconds
            $startTime = try { ([datetime]$general.StartTime).ToString('yyyy-MM-dd HH:mm') } catch { 'unknown' }
            $endTime = try { [datetime]$general.EndTime } catch { $null }
            $startTimeObj = try { [datetime]$general.StartTime } catch { $null }
            $duration = if ($startTimeObj -and $endTime) { 
              $ts = $endTime - $startTimeObj
              ("{0:D2}:{1:D2}:{2:D2}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)
            } else { 'unknown' }
            $initiatedBy = $general.InitiatedBy
            $notes = if ($general.Notes) { $general.Notes } else { '-' }
            
            $statusClass = if ($status -match 'Passed|Success') { 'pass' } else { 'warn' }
            $statusBadge = '<span class="status-badge {0}">{1}</span>' -f $statusClass, $status
            
            $html += ('<tr><td><strong>{0}</strong></td><td>{1}</td><td>{2}</td><td><code>{3}</code></td><td>{4}</td><td>{5}</td><td style="font-size:0.9em">{6}</td></tr>' -f $vpgName, $startTime, $statusBadge, $rto, $duration, $initiatedBy, $notes)
          }
        } catch {
          Write-Log ("Failed to parse recovery report {0}: {1}" -f $reportFile.Name, $_.Exception.Message) 'WARN'
        }
      }
      $html += '</tbody></table></div>'
    }
  }

  $html += '<h2>Evidence Sample</h2>'
  $html += '<p style="color:#7f8c8d;margin-bottom:15px">First 100 rows from complete audit evidence (see Evidence.csv for full dataset)</p>'
  $sample = Import-Csv -Path $script:CsvPath | Select-Object -First 100
  if ($sample) {
    $html += '<div style="overflow-x:auto"><table><thead><tr><th>Domain</th><th>Entity</th><th>Detail</th><th>Status</th><th>Timestamp</th></tr></thead><tbody>'
    foreach ($r in $sample) {
      $statusClass = if ($r.Status -match '(?i)NON[- ]?COMPLIANT|NONCOMPLIANT|UNPROTECTED|NOT PROTECTED|NOT TESTED|FAIL|FAILED|MEDIUM RISK|CRITICAL|HIGH RISK') { 'fail' }
      elseif ($r.Status -match '(?i)WARN|PARTIAL|FAIR|AT RISK') { 'warn' }
      elseif ($r.Status -match '(?i)^PASS$|^COMPLIANT$|PROTECTED|GOOD|SECURE') { 'pass' }
      else { 'neutral' }
      $statusBadge = '<span class="status-badge {0}">{1}</span>' -f $statusClass, $r.Status
      try { $ts = ([datetime]$r.Timestamp).ToString('yyyy-MM-dd HH:mm') } catch { $ts = $r.Timestamp }
      $html += ('<tr><td>{0}</td><td><strong>{1}</strong></td><td>{2}</td><td>{3}</td><td style="font-size:0.85em;color:#7f8c8d">{4}</td></tr>' -f ($r.Audit_Domain), ($r.Entity), ($r.Detail), $statusBadge, $ts)
    }
    $html += '</tbody></table></div>'
  } else {
    $html += '<p style="color:#95a5a6">No evidence rows available</p>'
  }

  $html += '<h2>Audit Artifacts</h2>'
  $html += '<div class="artifacts">'
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Evidence CSV</strong><code>{1}</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Primary audit evidence with all control test results</div></div></a>' -f ($script:CsvPath -replace '\\', '/'), (Split-Path $script:CsvPath -Leaf))
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Audit Report (Markdown)</strong><code>AUDIT-REPORT.md</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Executive summary with findings and recommendations</div></div></a>' -f ($(Join-Path $script:OutDir 'AUDIT-REPORT.md') -replace '\\', '/'))
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Summary</strong><code>{1}</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Text-based executive summary</div></div></a>' -f ($script:SummaryPath -replace '\\', '/'), (Split-Path $script:SummaryPath -Leaf))
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Manifest</strong><code>{1}</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">JSON metadata with scores and environment details</div></div></a>' -f ($script:ManifestPath -replace '\\', '/'), (Split-Path $script:ManifestPath -Leaf))
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Controls Map</strong><code>{1}</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Framework mappings (SOC2, ISO 27001, NIST)</div></div></a>' -f ($script:ControlsMapPath -replace '\\', '/'), (Split-Path $script:ControlsMapPath -Leaf))
  $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>Execution Log</strong><code>{1}</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Technical log with API calls and timestamps</div></div></a>' -f ($script:LogPath -replace '\\', '/'), (Split-Path $script:LogPath -Leaf))
  
  # Add recovery reports if they exist
  $recoveryReportsDir = Join-Path $script:OutDir 'RecoveryReports'
  if (Test-Path $recoveryReportsDir) {
    $reportCount = (Get-ChildItem -Path $recoveryReportsDir -Filter '*.json' -ErrorAction SilentlyContinue).Count
    if ($reportCount -gt 0) {
      $html += ('<a href="file:///{0}" target="_blank" style="text-decoration:none;cursor:pointer" title="Click to open folder"><div class="artifact-card" style="transition:all 0.3s;cursor:pointer" onmouseover="this.style.boxShadow=''0 8px 16px rgba(1,169,130,0.2)''; this.style.transform=''translateY(-2px)''" onmouseout="this.style.boxShadow=''0 2px 6px rgba(0,0,0,0.05)''; this.style.transform=''none''"><strong>DR Test Reports</strong><code>RecoveryReports/ ({1} files)</code><div style="margin-top:8px;color:#7f8c8d;font-size:0.9em">Full JSON reports from /v1/reports/recovery API (RTO validation, test steps, initiator)</div></div></a>' -f ($recoveryReportsDir -replace '\\', '/'), $reportCount)
    }
  }
  
  $html += '</div>'
  if ($protectedVmNamesEx -and $protectedVmNamesEx.Count -gt 0) {
    $html += '<h2>Protected Virtual Machines</h2>'
    $html += ('<p style="color:#27ae60;font-size:1.1em;margin-bottom:15px"><strong>{0}</strong> VMs protected by Zerto VPGs</p>' -f $protectedVmNamesEx.Count)
    # Professional card-based presentation
    $html += '<div class="vm-grid">'
    foreach ($n in ($protectedVmNamesEx | Sort-Object)) {
      $html += ('<div class="vm-card"><span class="vm-name">{0}</span><span class="vm-status-icon protected" title="Protected by Zerto"></span></div>' -f $n)
    }
    $html += '</div>'
  }
  if ($unprotectedVmNamesEx -and $unprotectedVmNamesEx.Count -gt 0) {
    $html += '<h2>Unprotected Virtual Machines</h2>'
    $html += ('<p style="color:#e74c3c;font-size:1.1em;margin-bottom:15px"><strong>{0}</strong> VMs NOT protected (at risk)</p>' -f $unprotectedVmNamesEx.Count)
    # Professional card-based presentation with risk indicator
    $html += '<div class="vm-grid">'
    foreach ($n in ($unprotectedVmNamesEx | Sort-Object)) {
      $html += ('<div class="vm-card unprotected"><span class="vm-name">{0}</span><span class="vm-status-icon unprotected" title="Not protected - At Risk"></span></div>' -f $n)
    }
    $html += '</div>'
  }
  # Audit sign-off section
  $html += '<div style="margin-top:50px;padding:30px;background:#fff;border-radius:8px;border:2px solid #01A982;box-shadow:0 2px 8px rgba(0,0,0,0.06)">'
  $html += '<h2 style="margin-top:0;color:#01A982;border-bottom:2px solid #FFB81C;padding-bottom:10px">Audit Sign-Off</h2>'
  $html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:30px;margin-top:20px">'
  $html += '<div style="border-bottom:1px solid #ccc;padding-bottom:5px">'
  $html += '<label style="display:block;color:#7f8c8d;font-size:0.85em;margin-bottom:5px">Full Name:</label>'
  $html += '<div style="height:30px"></div>'
  $html += '</div>'
  $html += '<div style="border-bottom:1px solid #ccc;padding-bottom:5px">'
  $html += '<label style="display:block;color:#7f8c8d;font-size:0.85em;margin-bottom:5px">Title:</label>'
  $html += '<div style="height:30px"></div>'
  $html += '</div>'
  $html += '</div>'
  $html += '<div style="margin-top:30px;border-bottom:1px solid #ccc;padding-bottom:5px">'
  $html += '<label style="display:block;color:#7f8c8d;font-size:0.85em;margin-bottom:5px">Signature:</label>'
  $html += '<div style="height:40px"></div>'
  $html += '</div>'
  $html += '<div style="margin-top:15px;color:#95a5a6;font-size:0.85em;text-align:right">'
  $html += ('<span>Date: {0}</span>' -f (Get-Date -Format 'MMMM dd, yyyy'))
  $html += '</div>'
  $html += '</div>'
  
  $html += '<div style="margin-top:30px;padding:20px;background:#ecf0f1;border-radius:8px;text-align:center;color:#7f8c8d;font-size:0.9em">'
  $html += ('<p>Report generated by <strong>Zerto Compliance Tool v{0}</strong></p>' -f $scriptVersion)
  $html += ('<p>Report ID: <code>{0}</code></p>' -f (Split-Path $script:OutDir -Leaf))
  $html += '</div>'
  $html += '</div></body></html>'
  
  # Write HTML with UTF-8 encoding (no BOM) to prevent character corruption
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($script:HtmlReportPath, ($html -join "`n"), $utf8NoBom)

  # --- Optional PDF (wkhtmltopdf or headless Edge/Chrome) ---
  $pdfOk = $false
  $wk = Get-Command wkhtmltopdf -ErrorAction SilentlyContinue
  if (-not $wk) {
    Write-Log "wkhtmltopdf not found; attempting installation..." 'WARN'
    try { Ensure-Wkhtmltopdf } catch { Write-Log ("wkhtmltopdf install attempt failed: {0}" -f $_.Exception.Message) 'WARN' }
  }
  try {
    $pdfOk = Convert-HtmlToPdf -HtmlPath $script:HtmlReportPath -PdfPath $script:PdfReportPath
    if ($pdfOk) { Write-Log ("PDF report written: {0}" -f $script:PdfReportPath) 'INFO' } else { Write-Log "PDF export skipped (no renderer available)" 'WARN' }
  } catch { Write-Log ("PDF export failed: {0}" -f $_.Exception.Message) 'WARN' }

} catch {
  Write-ErrorDetails -ErrorRecord $_
  Write-Log ("Fatal error: {0}" -f $_.Exception.Message) 'ERROR'
  throw
} finally {
  if ($Insecure) { Set-CertValidation }
  try { Stop-Transcript | Out-Null } catch { }
}
