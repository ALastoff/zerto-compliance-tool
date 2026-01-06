# Zerto Compliance Tool - GUI Launcher

## Overview

This C# WinForms application provides a professional GUI launcher for the Zerto Compliance PowerShell script. It allows users to:
- Enter ZVMA credentials securely
- Select output folder
- Run compliance scans with a single click
- Schedule recurring compliance scans using Windows Task Scheduler

## Prerequisites

- .NET 6.0 SDK or later
- Windows OS
- PowerShell 5.1 or later
- Visual Studio 2022 (or `dotnet` CLI)

## Project Structure

```
Launcher/
├── ZertoComplianceLauncher.csproj  # Project file
├── Program.cs                       # Entry point
├── MainForm.cs                      # Main GUI form
└── README.md                        # This file
```

## Build Instructions

### Option 1: Visual Studio

1. Open `ZertoComplianceLauncher.csproj` in Visual Studio 2022
2. Right-click project → **Restore NuGet Packages**
3. Build → **Build Solution** (or press `Ctrl+Shift+B`)
4. Executable will be in `bin\Release\net6.0-windows\ZertoComplianceLauncher.exe`

### Option 2: Command Line (dotnet CLI)

```powershell
# Navigate to Launcher directory
cd "c:\Users\Administrator\Documents\Scripts\Compliance Tool\Launcher"

# Restore dependencies
dotnet restore

# Build Release version
dotnet build -c Release

# Output: bin\Release\net6.0-windows\ZertoComplianceLauncher.exe
```

### Self-Contained Deployment (No Runtime Required)

If you want a single-file EXE with no dependencies (no .NET runtime check):

```powershell
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

Output: `bin\Release\net8.0-windows\win-x64\publish\ZertoComplianceLauncher.exe` (~150 MB, includes runtime)

**Note:** This requires downloading .NET runtime packs during build. Use framework-dependent deployment if network policies block NuGet downloads.

### Old Enterprise Deployment Section

This approach keeps the EXE small and uses a bootstrapper to check for .NET runtime.

**File Structure:**
```
C:\Program Files\ZertoCompliance\
├── ZertoComplianceLauncher.bat           # Bootstrapper (checks runtime)
├── ZertoComplianceLauncher-Bootstrapper.ps1  # PowerShell bootstrapper
├── ZertoComplianceLauncher.exe           # Main launcher
├── ZertoComplianceNew.ps1                # Compliance script
├── auth.config.json (optional)
└── README.md
```

**Installation Script:**
```powershell
# Run as Administrator
cd "c:\Users\Administrator\Documents\Scripts\Compliance Tool\Installer"
$src = "c:\Users\Administrator\Documents\Scripts\Compliance Tool\Launcher\bin\Release\net8.0-windows"
.\Install-ZertoComplianceLauncher.ps1 -SourceDir $src
```

This installer:
- Copies all files to `C:\Program Files\ZertoCompliance`
- Creates desktop shortcut pointing to the bootstrapper `.bat` file
- Creates Start Menu shortcut
- Optionally signs binaries if `-PfxPath` or `-CertThumbprint` provided

**User Experience:**
1. Users double-click "Zerto Compliance Tool" shortcut
2. Bootstrapper checks for .NET 8 Desktop Runtime
3. If missing: Shows download prompt with link to https://dotnet.microsoft.com/download/dotnet/8.0
4. If present: Launches the tool immediately

### Basic Deployment (Manual)

1. Copy `ZertoComplianceLauncher.exe` and `ZertoComplianceLauncher.bat` to the same folder as `ZertoComplianceNew.ps1`
2. Users double-click the `.bat` file to launch (checks runtime first)
3. Or run the `.exe` directly if .NET 8 Desktop Runtime is already installed

### Self-Contained Deployment (No Runtime Required)

**File Structure:**
```
C:\Program Files\ZertoCompliance\
├── ZertoComplianceLauncher.exe
├── ZertoComplianceNew.ps1
├── auth.config.json (optional)
└── README.md
```

**Installation Script:**
```powershell
# Create installation directory
$installPath = "C:\Program Files\ZertoCompliance"
New-Item -ItemType Directory -Path $installPath -Force

# Copy files
Copy-Item "ZertoComplianceLauncher.exe" -Destination $installPath
Copy-Item "ZertoComplianceNew.ps1" -Destination $installPath

# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\Zerto Compliance Tool.lnk")
$Shortcut.TargetPath = "$installPath\ZertoComplianceLauncher.exe"
$Shortcut.Save()
```

## Usage

1. **Launch the application**
   - Double-click `ZertoComplianceLauncher.exe`

2. **Enter credentials**
   - ZVMA Host: `192.168.111.20`
   - Username: `admin@zerto.local`
   - Password: `your-password`
   - Peer Hosts (optional): `192.168.222.20`

3. **Select output folder**
   - Click **Browse** to choose where reports will be saved
   - Default: `Documents\ZertoCompliance`

4. **Run scan**
   - Click **Run Now** to execute immediately
   - Progress bar shows execution status
   - Opens report automatically when complete

5. **Schedule recurring scans** (optional)
   - Check **Create scheduled task**
   - Select frequency: Daily, Weekly, or Monthly
   - Click **Schedule Task** to create Windows scheduled task

## Features

### Security
- Password field uses masked input (`UseSystemPasswordChar`)
- Credentials passed directly to PowerShell (not stored on disk)
- Option to run scheduled tasks as SYSTEM account

### User Experience
- Clean, professional WinForms interface
- Zerto brand colors (green #01A982, yellow #FFB81C)
- Real-time progress indication
- Automatic report opening after completion
- Input validation with helpful error messages

### Integration
- Locates PowerShell script automatically (same directory or parent)
- Passes parameters correctly (supports peer hosts, output directory)
- Captures script output and errors
- Detects successful completion and finds generated report

### Scheduling
- Creates Windows Task Scheduler tasks
- Options: Daily (2 AM), Weekly (Monday 2 AM), Monthly (1st day 2 AM)
- Runs as SYSTEM account (no user login required)
- Uses `schtasks.exe` for maximum compatibility

## Troubleshooting

### EXE does not open
- Run environment setup first:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
   ```
- Confirm Windows Desktop runtime is present:
   ```powershell
   & "$env:ProgramFiles\dotnet\dotnet" --list-runtimes
   ```
   Ensure `Microsoft.WindowsDesktop.App 8.0.x` is listed.
- Check launcher startup log:
   ```powershell
   Get-Content "$env:TEMP\ZertoComplianceLauncher.log" -Tail 50
   ```
- Try launching elevated:
   ```powershell
   Start-Process "C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe" -Verb RunAs
   ```

### "ZertoComplianceNew.ps1 not found"
- Ensure the PowerShell script is in the same folder as the exe
- Or place it one level up (e.g., exe in `Launcher\bin\Release\`, script in root)

### "Failed to create scheduled task"
- Run the launcher as Administrator (right-click → Run as administrator)
- Task creation requires elevated privileges

### "Script execution failed"
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- Launcher uses `-ExecutionPolicy Bypass` to avoid restrictions
- Verify ZVMA host is accessible and credentials are correct

### Report doesn't open automatically
- Check that output folder path is valid
- Report is named `Report.html` in latest `ZertoCompliance_ZVMA_*` folder
- Manually browse to output folder if needed

## Advanced Customization

### Change Default Output Path
Edit `MainForm.cs` line 88:
```csharp
txtOutputPath.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ZertoCompliance");
```

### Change Schedule Defaults
Edit `MainForm.cs` line 108:
```csharp
cmbScheduleFrequency.SelectedIndex = 0; // 0=Daily, 1=Weekly, 2=Monthly
```

### Add Application Icon
1. Place `zerto-icon.ico` in project root
2. Icon will be used for exe and window title bar (already configured in `.csproj`)

### Enable Debug Logging
Add to `RunComplianceScript()` method to show PowerShell output:
```csharp
MessageBox.Show(outputText, "Script Output", MessageBoxButtons.OK, MessageBoxIcon.Information);
```

## Code Signing (Recommended for Production)

To avoid Windows SmartScreen warnings:

```powershell
# Obtain code signing certificate (DigiCert, Sectigo, etc.)
# Sign the executable
signtool sign /f "certificate.pfx" /p "password" /t http://timestamp.digicert.com "ZertoComplianceLauncher.exe"
```

### Customer-Provided Code Signing (Internal, No Cost)

For internal deployments, you can use your own organization’s certificate (AD CS or self-signed) to sign the launcher and PowerShell script without buying a public CA cert.

#### Option A: Enterprise CA (AD CS)
- Request a Code Signing certificate from your internal CA
- Export a PFX file with private key for signing
- Distribute the public cert to target machines (via GPO) into `Trusted Root` and `Trusted Publishers`

#### Option B: Self-Signed (lab/testing)
```powershell
# Create a self-signed code-signing certificate
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=ZertoCompliance" -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeySpec Signature

# Export PFX and public cert
$pwd = ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath "C:\Certs\ZertoCompliance.pfx" -Password $pwd
Export-Certificate -Cert $cert -FilePath "C:\Certs\ZertoCompliance.cer"

# Trust certificate on target machines (run as admin)
Import-Certificate -FilePath "C:\Certs\ZertoCompliance.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "C:\Certs\ZertoCompliance.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

#### Sign the EXE and PowerShell Script
Use the included signing script (requires Windows SDK for `signtool` to sign the EXE):
```powershell
cd "c:\Users\Administrator\Documents\Scripts\Compliance Tool\Installer"

# Sign using a PFX (recommended)
./Sign-ZertoCompliance.ps1 -PfxPath "C:\Certs\ZertoCompliance.pfx" -PfxPassword "P@ssw0rd!" `
   -ExePath "C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe" `
   -Ps1Path "C:\Program Files\ZertoCompliance\ZertoComplianceNew.ps1"

# Or sign using a certificate already in the store
./Sign-ZertoCompliance.ps1 -CertThumbprint "THUMBPRINTHERE" -MachineStore `
   -ExePath "C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe" `
   -Ps1Path "C:\Program Files\ZertoCompliance\ZertoComplianceNew.ps1"
```

#### Verify Signatures
```powershell
Get-AuthenticodeSignature "C:\Program Files\ZertoCompliance\ZertoComplianceNew.ps1" | Format-List Status,StatusMessage,SignerCertificate
```

#### Optional: Sign During Install
Pass a PFX or thumbprint to the installer to sign automatically:
```powershell
cd "c:\Users\Administrator\Documents\Scripts\Compliance Tool\Installer"
./Install-ZertoComplianceLauncher.ps1 -PfxPath "C:\Certs\ZertoCompliance.pfx" -PfxPassword "P@ssw0rd!"
# Or
./Install-ZertoComplianceLauncher.ps1 -CertThumbprint "THUMBPRINTHERE" -MachineStore
```

Notes:
- Public internet distribution still benefits from a CA-issued cert for SmartScreen reputation.
- Internal deployments do not require public CA: use AD CS or self-signed + GPO trust.

## Future Enhancements

Potential additions:
- [ ] Real-time log output window (show PowerShell script progress)
- [ ] History view (list previous reports with open/compare options)
- [ ] Multi-ZVMA support (scan multiple sites in one run)
- [ ] Encrypted credential storage (Windows Data Protection API)
- [ ] Email report distribution (SMTP configuration)
- [ ] Dashboard view (show last scan results in launcher)

## License

Copyright © 2025 Zerto. Internal use only.

## Support

For issues or questions:
- Review PowerShell script documentation: `ZertoComplianceNew.ps1`
- Check Windows Event Viewer for scheduled task errors
- Contact Zerto support team
