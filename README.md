# Zerto Compliance Tool - Automated DR Testing & VM Protection Audit

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![.NET](https://img.shields.io/badge/.NET-8.0-purple)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

🎯 **Professional Zerto Virtual Replication Compliance Auditing, DR Testing Analytics & Cyber Resilience Monitoring**

---

## 📦 Quick Download

**👉 [Download Latest Release (v2.1.0)](https://github.com/ALastoff/zerto-compliance-tool/releases/latest) 👈**

**Pre-built package** — No building required! Includes compiled executable, installer, and documentation.

For developers or advanced users, see [Installation from Source](#installation-from-source) below.

The Zerto Compliance Tool is an open-source automation solution for Zerto Virtual Manager (ZVM/ZVMA) environments that helps IT administrators, disaster recovery teams, and MSPs monitor DR testing effectiveness, track VM protection coverage, validate cyber resilience configurations, and generate executive-ready compliance reports.

### 🔍 Perfect for:

• **Zerto Administrators** managing disaster recovery infrastructure  
• **MSPs & Service Providers** tracking multi-tenant Zerto compliance  
• **IT Compliance Teams** auditing SOC 2, ISO 27001, HIPAA DR controls  
• **Disaster Recovery Managers** validating RTO/RPO testing schedules  
• **VMware vSphere Admins** monitoring protected workload coverage

### ⚡ Key Capabilities:

Query Zerto REST APIs to generate **interactive HTML dashboards** showing DR testing effectiveness, VM protection gaps, cyber resilience posture, VPG health status, and compliance scoring with actionable recommendations. Supports **Zerto 9.x and 10.x** authentication on Windows with PowerShell 5.1+ and .NET 8.0 GUI launcher.

**Keywords:** Zerto compliance, disaster recovery audit tool, VM protection monitoring, DR testing automation, VPG compliance checker, cyber resilience scoring, business continuity audit, Zerto PowerShell automation, RTO RPO validation, ransomware protection assessment

---

## Features

• 📊 **Interactive HTML Dashboard** with KPIs, drill-down breakdowns, and recommendations  
• 📈 **Multi-Format Export**: HTML, CSV, JSON, Markdown for executive reporting  
• 🔐 **Secure Authentication**: Windows Credential Manager integration + config file support  
• 🌍 **Multi-Site Support**: Primary + Secondary + Additional sites (3+)  
• 📍 **Recovery Reports Collection**: Centralizes VPG test reports in audit artifacts  
• 🎯 **Weighted Scoring**: DR Testing (40%), VM Coverage (30%), Cyber Resilience (30%)  
• ⚠️ **Intelligent Alerts**: Color-coded recommendations for undertested VPGs  
• 🔒 **Security-First**: TLS validation, Lab Mode for testing, no password logging  
• 📝 **Comprehensive Artifacts**: Evidence CSV, control maps, transcripts, manifests

---

## System Requirements

### What You Need:

• ✅ **Windows** Server 2016+ or Windows 10/11  
• ✅ **.NET 8.0 Desktop Runtime** - Auto-installed via included `dotnet-install.ps1`  
• ✅ **PowerShell 5.1+** - Included with Windows  
• ✅ **Network Access** to Zerto ZVMA (HTTPS port 443 for 10.x, port 9669 for 9.x)  
• ✅ **Zerto Credentials** - Read-Only Administrator or higher  
• ✅ **Local Administrator** privileges for installation

💡 **Note:** All dependencies are included - just download, install, and run!

---

## Quick Start (Pre-Built Release)

### 1. Download Release Package

**👉 [Download ComplianceTool_DeploymentPackage.zip](https://github.com/ALastoff/zerto-compliance-tool/releases/latest)**

Extract the ZIP to any location (e.g., `C:\Tools\zerto-compliance-tool`)

### 2. Install Dependencies

**From the extracted folder**:

```powershell
# Install .NET 8.0 Desktop Runtime (if needed)
powershell -ExecutionPolicy Bypass -File .\dotnet-install.ps1

# Run environment setup
powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
```

### 3. Install Application

```powershell
# Navigate to Installer folder
cd .\Installer

# Run installer (requires Administrator)
powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1
```

The installer:
- Copies files to `C:\Program Files\ZertoCompliance\`
- Creates Desktop and Start Menu shortcuts
- Verifies .NET runtime availability

### 4. Launch & Configure

```powershell
# Launch from shortcut or:
"C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe"
```

**Configuration:**
1. **Source Site**: Enter primary ZVMA IP/hostname (e.g., `192.168.111.20`)
2. **Zerto GUI User Name**: Enter Zerto admin username (e.g., `admin`)
3. **Password**: Enter corresponding password
4. **Secondary Site** (optional): Add secondary ZVMA for dual-site audits
5. **Additional Sites** (optional): Comma-separated list for 3+ site environments
6. **Output Folder**: Choose report destination (default: `Documents\ZertoCompliance`)
7. **Lab Mode**: Enable SSL skip for testing environments only
8. **Cyber Resilience**: Enable LTR vault lock evaluation

### 5. Run Audit

Click **"Run Now"** to execute compliance scan. Monitor progress in output window. Report opens automatically when complete.

### 6. Review Reports

Reports are generated in: `ComplianceAudit_<host>_<YYYY-MM-DD_HHMMSS>/`

**Key Files:**
- 📄 `Report_<timestamp>.html` — Interactive dashboard (open in browser)
- 📊 `Zerto_Compliance_<timestamp>.csv` — Tabular evidence for Excel/BI
- 📋 `AUDIT-REPORT.md` — Markdown executive summary
- 📦 `RecoveryReports/` — VPG recovery test JSON reports
- 📝 `SUMMARY.txt`, `MANIFEST.json`, `ControlsMap.txt`, `LOG.txt`

---

## Scoring Breakdown

Your compliance score is calculated from three weighted categories:

```
Overall Score = (DR Testing % × 0.40) 
              + (VM Coverage % × 0.30) 
              + (Cyber Resilience % × 0.30)
```

### Example Calculation:

| Category | Effectiveness | Weight | Points |
|----------|--------------|--------|--------|
| DR Testing | 50% | 40% | **20** |
| VM Coverage | 80% | 30% | **24** |
| Cyber Resilience | 0% | 30% | **0** |
| **Total Score** | — | — | **44%** |

**Click dashboard cards** in the HTML report to see detailed breakdowns!

---

## Authentication

### Primary Site Authentication:

The tool supports multiple authentication methods:

**Method 1: GUI Input** (Default)
- Enter credentials directly in launcher GUI
- Used for immediate/ad-hoc audits

**Method 2: Windows Credential Manager**
- Store credentials securely in Windows Credential Manager
- Target format: `zerto:<hostname>`
- Automatic retrieval during execution

**Method 3: Config File**
- Create `auth.config.json` with site credentials
- See `Documentation/SECURE-CREDENTIALS.md` for format

### Multi-Site Authentication:

**Same Credentials:**
- Uncheck "Different credentials for secondary site"
- Primary credentials used for all sites

**Different Credentials:**
- Check "Different credentials for secondary site"
- Enter separate username/password for secondary
- Additional sites use primary credentials (config file override available)

### Security Notes:

- ✅ Passwords **never logged** or stored in reports
- ✅ **HTTPS-only** communication with ZVMA
- ✅ Credentials validated per-site independently
- ⚠️ **Lab Mode** (SSL skip) disabled by default, marked in red
- ✅ All reports stored **locally** - no cloud connectivity

---

## Configuration

### Lab Mode (SSL Verification Bypass):

**Default:** TLS validation enabled (`verify_tls: true`)

**For Production:**
```powershell
# Keep Lab Mode unchecked in GUI
# Import valid certificates per IMPORT-CERTIFICATE.md
```

**For Testing Environments:**
```powershell
# Check "Lab mode (skip SSL verification)" in GUI
# ⚠️ WARNING: Only use in isolated test environments
```

### Output Directory:

**Default:** `%USERPROFILE%\Documents\ZertoCompliance`

**Custom Location:**
- Click **Browse** button in GUI
- Select preferred output folder
- Reports organized by timestamp subdirectories

---

## CLI Usage (Advanced)

For automation and non-interactive scenarios, use PowerShell script directly:

> Replace the example IPs (`192.168.111.20`, `192.168.222.20`) with your own ZVM/ZVMA hostnames or IPs.

### Basic Audit:

```powershell
.\Run-ComplianceAudit.ps1 `
  -PrimaryZvmaHost "192.168.111.20" `
  -Username "admin" `
  -Password "YourPassword" `
  -OutputPath "C:\Reports"
```

### Multi-Site Audit:

```powershell
.\Run-ComplianceAudit.ps1 `
  -PrimaryZvmaHost "192.168.111.20" `
  -SecondaryZvmaHost "192.168.222.20" `
  -Username "admin" `
  -Password "YourPassword" `
  -OutputPath "C:\Reports"
```

### With Cyber Resilience:

```powershell
.\Run-ComplianceAudit.ps1 `
  -PrimaryZvmaHost "192.168.111.20" `
  -Username "admin" `
  -Password "YourPassword" `
  -UseLtr `
  -OutputPath "C:\Reports"
```

### Lab Mode:

```powershell
.\Run-ComplianceAudit.ps1 `
  -PrimaryZvmaHost "192.168.111.20" `
  -Username "admin" `
  -Password "YourPassword" `
  -Insecure `
  -OutputPath "C:\Reports"
```

See `Run-ComplianceAudit.ps1 -Help` for full parameter reference.

---

## Troubleshooting

### Quick Fixes

Enable verbose logging for diagnostics:
```powershell
.\Run-ComplianceAudit.ps1 -PrimaryZvmaHost "192.168.111.20" -Verbose
Get-Content .\ComplianceAudit_*\LOG.txt -Tail 50
```

### Common Issues

| Problem | Solution |
|---------|----------|
| ".NET runtime not found" | Run `dotnet-install.ps1` or download from dotnet.microsoft.com |
| "Authentication failed" | Verify ZVMA IP, username/password, check port 9669/443 access |
| "TLS validation error" | Enable Lab Mode for testing, or install valid cert on ZVMA |
| "Secondary site fails" | Verify secondary IP, check "Different credentials" if needed |
| "Launcher won't open" | Check `%TEMP%\ZertoComplianceLauncher.log` for startup errors |
| "Empty reports" | Run with `-Verbose`, check LOG.txt for API errors |

### 📖 Complete Documentation

For detailed guidance, see:
- **`QUICK_START.md`** - ⚡ 5-minute setup checklist
- **`DEPLOYMENT_GUIDE.html`** - 📘 Full installation and configuration walkthrough
- **`Documentation/TROUBLESHOOTING.md`** - 🔧 Advanced diagnostics
- **`Documentation/SECURE-CREDENTIALS.md`** - 🔐 Credential management best practices
- **`Documentation/HYPERVISOR-CONFIGURATION.md`** - 🖥️ Multi-site setup examples

---

## Upgrade

### Upgrade Process:

1. **Backup** existing reports and configuration
2. **Download** latest release from GitHub
3. **Run installer**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Installer\Install-ZertoComplianceLauncher.ps1
   ```
4. **Launch** from shortcut

The installer overwrites files in `C:\Program Files\ZertoCompliance\` and preserves shortcuts.

See **`UPGRADE.md`** for detailed upgrade instructions and rollback procedures.

---

## Uninstall

To remove the tool completely:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\ZertoCompliance\Uninstall-ZertoComplianceLauncher.ps1"
```

This removes:
- Installation directory (`C:\Program Files\ZertoCompliance\`)
- Desktop shortcut
- Start Menu shortcut

**Note:** Audit reports in your output directory are preserved.

---

## Installation from Source

**For developers and advanced users** who want to build from source code:

### 1. Clone Repository

```bash
git clone https://github.com/ALastoff/zerto-compliance-tool.git
cd zerto-compliance-tool
```

### 2. Install .NET SDK

**Required:** .NET SDK 8.0 or later (not just Runtime)

Download from: https://dotnet.microsoft.com/download/dotnet

### 3. Build and Install

```powershell
# Unblock files (Windows)
Get-ChildItem -Recurse | Unblock-File

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Run environment setup
powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1

# Build and install
cd .\Installer
powershell -ExecutionPolicy Bypass -File .\Build-And-Install.ps1
```

---

## Contributing

We welcome contributions from the Zerto community!

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Make** your changes and write/update tests
4. **Follow** code style: PSScriptAnalyzer for PowerShell, C# conventions for .NET
5. **Commit** with clear messages (`git commit -m 'Add amazing feature'`)
6. **Push** and open a Pull Request

**Report bugs:** [GitHub Issues](https://github.com/ALastoff/zerto-compliance-tool/issues)  
**Request features:** [GitHub Discussions](https://github.com/ALastoff/zerto-compliance-tool/discussions)

---

## Documentation

- 📘 **[DEPLOYMENT_GUIDE.html](DEPLOYMENT_GUIDE.html)** - Complete installation and configuration
- ⚡ **[QUICK_START.md](QUICK_START.md)** - 5-minute setup guide
- 📋 **[PRE-DEPLOYMENT_CHECKLIST.md](PRE-DEPLOYMENT_CHECKLIST.md)** - Pre-flight validation
- 🔄 **[UPGRADE.md](UPGRADE.md)** - Version upgrade procedures
- 🔐 **[Documentation/SECURE-CREDENTIALS.md](Documentation/SECURE-CREDENTIALS.md)** - Credential management
- 🖥️ **[Documentation/HYPERVISOR-CONFIGURATION.md](Documentation/HYPERVISOR-CONFIGURATION.md)** - Multi-site examples
- 🏢 **[Documentation/ENTERPRISE-FEATURES.md](Documentation/ENTERPRISE-FEATURES.md)** - Roadmap and feature requests

---

## Roadmap

- ✅ **Multi-site support** (Primary + Secondary + Additional)
- ✅ **Recovery reports centralization**
- ✅ **Cyber resilience scoring** (LTR vault lock evaluation)
- 🔲 **Email alerting** for low compliance scores
- 🔲 **Trend analysis** across multiple audit runs
- 🔲 **PowerBI integration** with JSON/CSV exports
- 🔲 **Custom thresholds** for scoring weights
- 🔲 **API endpoint** for programmatic access
- 🔲 **Linux support** via PowerShell Core

---

## Support & Community

### Get Help:

• 🔧 **Troubleshooting**: [Documentation/](Documentation/) folder - Diagnostic guides  
• 🐛 **Bug Reports**: [GitHub Issues](https://github.com/ALastoff/zerto-compliance-tool/issues)  
• 💡 **Feature Requests**: [GitHub Discussions](https://github.com/ALastoff/zerto-compliance-tool/discussions)  
• 🔒 **Security Issues**: See Legal Disclaimer below for responsible disclosure

### Direct Support:

For complex issues or collaboration:

• 📧 **Email**: [aaron.lastoff@hpe.com](mailto:aaron.lastoff@hpe.com)  
• 🐙 **GitHub**: [@ALastoff](https://github.com/ALastoff)  
• 💼 **LinkedIn**: [Aaron Lastoff](https://www.linkedin.com/in/aaron-lastoff/)

Want to enhance the Zerto Compliance Tool? Open an issue or reach out via email for collaboration opportunities!

---

## License

MIT License – see [LICENSE](LICENSE) file for details (if applicable).

---

## Acknowledgments

Built with ❤️ for the Zerto community by disaster recovery automation enthusiasts.

**Special thanks to:**
- **Zerto/HPE** for providing comprehensive REST APIs
- **PowerShell** and **.NET** communities for excellent frameworks
- **Contributors** and testers who helped improve this tool

---

## Legal Disclaimer

⚠️ **IMPORTANT:** This script is provided as an example only and is not supported under any Zerto support program or service.

The author and Zerto disclaim all implied warranties, including merchantability and fitness for a particular purpose. In no event shall Zerto or the author be liable for damages arising from the use or inability to use this script.

**Use at your own risk.** Always test in non-production environments first.

---

**Author:** Aaron Lastoff  
**Company:** Zerto (HPE)  
**Version:** 2.1.0  
**Date:** January 2026
