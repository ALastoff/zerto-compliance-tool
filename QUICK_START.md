# Zerto Compliance Tool - Quick Start Guide | DR Testing & VM Protection Audit

**Version:** 2.1.0 | **Release Date:** December 25, 2025

> **Fast-track guide for installing and running automated Zerto compliance audits. Evaluate disaster recovery testing, VM protection coverage, and cyber resilience in 5 minutes.**

## Legal Disclaimer

This script is provided as an example only and is not supported under any Zerto support program or service.

The author and Zerto disclaim all implied warranties, including merchantability and fitness for a particular purpose.
In no event shall Zerto or the author be liable for damages arising from the use or inability to use this script.
Use at your own risk.

## 📦 What's Included

- `ZertoComplianceLauncher.exe` - GUI Application
- `ZertoComplianceNew.ps1` - Core PowerShell Assessment Script
- `Install-ZertoComplianceLauncher.ps1` - Automated Installer
- `Uninstall-ZertoComplianceLauncher.ps1` - Cleanup Script
- `DEPLOYMENT_GUIDE.html` - Full Installation & Configuration Guide
- `dotnet-install.ps1` - .NET 8.0 Runtime Installer

## ⚡ Quick Start (5 Minutes)

### 1. Install .NET (If Needed)
```powershell
powershell -ExecutionPolicy Bypass -File dotnet-install.ps1
```

### 2. Install (Choose one)

**Option A: Using Release ZIP (recommended for end users)**
```powershell
# From the extracted Deployment Package root
powershell -ExecutionPolicy Bypass -File .\Installer\Install-ZertoComplianceLauncher.ps1
```

**Option B: From Source (requires .NET SDK)**
```powershell
# From repo root
cd .\Installer
powershell -ExecutionPolicy Bypass -File .\Build-And-Install.ps1
# or, if you already built:
powershell -ExecutionPolicy Bypass -File .\Installer\Install-ZertoComplianceLauncher.ps1 -SourceDir ..\Launcher\bin\Release\publish
```

### 3. Launch Application
```powershell
"C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe"
```

### 4. Configure & Run
- **Source Site:** Enter primary ZVMA IP/hostname
- **Zerto GUI User Name:** Enter your Zerto admin username (e.g., `admin`)
- **Password:** Enter corresponding password
- Click **"Run Now"** to start the compliance scan

### 5. Review Report
The completion dialog will offer to open the HTML report or folder with results.

## ✅ System Requirements

| Component | Requirement |
|-----------|------------|
| OS | Windows Server 2016+ or Windows 10/11 |
| .NET | 8.0 Desktop Runtime (auto-installed) |
| PowerShell | 5.1+ (included with Windows) |
| Network | HTTPS access to Zerto ZVMA (port 443 for 10.x, port 9669 for 9.x) |
| Privileges | Local Administrator |

## 🎯 Key Features

✓ **DR Testing Assessment** - VPG test frequency (40% of score)  
✓ **VM Protection Coverage** - % of VMs protected (30% of score)  
✓ **Cyber Resilience** - LTR vault lock status (30% of score)  
✓ **Multi-Site Support** - Single, dual, or 3+ site analysis  
✓ **Interactive Reports** - HTML5 reports with click-through details  
✓ **Lab Mode** - SSL verification bypass for testing

## 📊 Scoring Breakdown

Your compliance score is calculated from:

```
Overall Score = (DR Testing % × 0.40) 
              + (VM Coverage % × 0.30) 
              + (Cyber Resilience % × 0.30)
```

**Example:**
- DR Testing: 50% effectiveness = 20 points (50% × 40%)
- VM Coverage: 80% protected = 24 points (80% × 30%)
- Cyber Resilience: 0% locks = 0 points (0% × 30%)
- **Total Score: 44%**

Click the dashboard cards in the report to see detailed breakdowns!

## 🔐 Security Notes

- Passwords are **never logged** or stored in reports
- **HTTPS only** communication with ZVMA
- Credentials validated per-site independently
- **Lab Mode** (SSL skip) is disabled by default and marked in red
- All reports stored **locally** - no cloud connectivity

## 🆘 Common Issues

| Problem | Solution |
|---------|----------|
| ".NET runtime not found" | Run `dotnet-install.ps1` or download from dotnet.microsoft.com |
| "Authentication failed" | Verify ZVMA IP, username/password, and port 9669 access |
| "SSL certificate failed" | Enable Lab Mode for testing, or install valid cert on ZVMA |
| "Secondary site fails" | Check secondary site IP and verify same/different credentials option |

## 🔧 Troubleshooting (EXE doesn’t open)

- **Confirm Windows Desktop runtime:**
    ```powershell
    & "$env:ProgramFiles\dotnet\dotnet" --list-runtimes
    ```
    Ensure `Microsoft.WindowsDesktop.App 8.0.x` is listed.

- **Run environment setup first:**
    ```powershell
    powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
    ```

- **Check launcher log:** The app logs startup errors to:
    - `"%TEMP%\ZertoComplianceLauncher.log"`
    View the last lines:
    ```powershell
    Get-Content "$env:TEMP\ZertoComplianceLauncher.log" -Tail 50
    ```

- **Try elevated launch:**
    ```powershell
    Start-Process "C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe" -Verb RunAs
    ```

- **SmartScreen/MOTW:** If downloaded from the internet, unzip to a local folder and ensure no Mark-of-the-Web blocks. (The packaged EXE is copied without MOTW.)

## 📞 Support

**Need Help?**  
Click the **Help** button in the application to email support.

**Contact:** aaron.lastoff@hpe.com  
**Subject:** Zerto Compliance Tool

## 📋 Full Documentation

See `DEPLOYMENT_GUIDE.html` for:
- Detailed installation instructions
- Configuration walkthrough with screenshots placeholders
- Multi-site setup guide
- Complete troubleshooting guide
- Report interpretation

## 🔄 Uninstalling

To remove the tool:
```powershell
powershell -ExecutionPolicy Bypass -File Uninstall-ZertoComplianceLauncher.ps1
```

## 📝 Version History

**v2.1.0 (Dec 25, 2025)**
- Secondary credentials support for different multi-site credentials
- Additional sites (3+) comma-separated configuration
- Improved score explanation modals (effectiveness vs weighted contribution)
- Fixed duplicate recovery site filtering (primary site no longer appears in recovery list)
- Enhanced Help button with email integration
- "Zerto GUI User Name" label for clarity
- FindLatestReport sorting for guaranteed latest report opening

**v2.0.0**
- Initial release with single/dual-site support
- Core compliance scoring engine
- HTML report generation

---

## About This Tool

The Zerto Compliance Tool helps IT administrators automate disaster recovery compliance assessments. Monitor VPG testing frequency, track VM protection gaps, validate cyber resilience configurations, and generate professional audit reports—all without manual spreadsheet tracking.

**Perfect for:** VMware vSphere admins, disaster recovery managers, compliance officers, MSPs, IT security teams

**Keywords:** Zerto compliance audit, DR testing automation, VM protection monitoring, VPG compliance checker, disaster recovery reporting, Zerto PowerShell tool, cyber resilience assessment, business continuity audit, Zerto automation script, RTO RPO validation

---

**For detailed step-by-step instructions, open `DEPLOYMENT_GUIDE.html` in a web browser.**
