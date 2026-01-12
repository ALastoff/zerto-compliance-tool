# Zerto Compliance Tool v2.1.0 - Pre-Built Release

## 🚀 Ready-to-Run Deployment Package

**No building required!** This release includes the pre-compiled executable and all dependencies.

### ✅ What's Included

- **Pre-built Windows GUI launcher** (`ZertoComplianceLauncher.exe`)
- **PowerShell audit engine** (`Run-ComplianceAudit.ps1`)
- **Automated installers** (Install/Uninstall scripts)
- **Documentation** (Quick Start, Deployment Guide, Configuration Guides)
- **.NET Runtime installer** (`dotnet-install.ps1`) - auto-installs if needed
- **Sample configurations** and setup scripts

### 📦 Download & Install

**Download:** `ComplianceTool_DeploymentPackage.zip` (attached below)

**Installation Steps:**

1. **Extract ZIP** to any location (e.g., `C:\Tools\zerto-compliance-tool`)

2. **Install .NET Runtime** (if needed):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\dotnet-install.ps1
   ```

3. **Run Environment Setup**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Setup-Environment.ps1
   ```

4. **Install Application**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1
   ```

5. **Launch** from Desktop shortcut or Start Menu

### 💻 System Requirements

- **OS:** Windows Server 2016+ or Windows 10/11
- **.NET:** 8.0 Desktop Runtime (auto-installed via included script)
- **PowerShell:** 5.1+ (included with Windows)
- **Network:** HTTPS access to Zerto ZVMA (port 443 for v10.x, port 9669 for v9.x)
- **Privileges:** Local Administrator for installation
- **Zerto:** Read-Only Administrator credentials or higher

### 🎯 Key Features

✓ **DR Testing Assessment** - VPG test frequency analysis (40% of compliance score)  
✓ **VM Protection Coverage** - Protected vs unprotected VM analysis (30% of score)  
✓ **Cyber Resilience Scoring** - LTR vault lock and air-gap evaluation (30% of score)  
✓ **Multi-Site Support** - Single, dual, or 3+ Zerto site architectures  
✓ **Interactive HTML Dashboards** - Click-through reports with KPIs and recommendations  
✓ **Multi-Format Export** - HTML, CSV, JSON, Markdown for executive reporting  
✓ **Secure Credential Storage** - Windows Credential Manager integration  
✓ **Recovery Reports Collection** - Automatically gathers VPG test reports

### 📊 What You Get

After running an audit, you'll receive:

- **Interactive HTML Dashboard** with drill-down analysis
- **CSV Evidence Export** for Excel/BI tools
- **Markdown Executive Summary** for documentation
- **Recovery Reports** collected from VPG tests
- **Control Map & Audit Log** for compliance tracking

### 🔐 Security & Compliance

- TLS/SSL validation for production environments
- Lab Mode option for testing (skips SSL validation)
- No password logging or credential exposure
- Supports Windows Credential Manager for secure storage
- Read-only API access to Zerto infrastructure

### 📚 Documentation

Included in the package:

- **START_HERE.txt** - Quick reference card
- **QUICK_START.md** - 5-minute installation guide
- **DEPLOYMENT_GUIDE.html** - Comprehensive setup documentation
- **Configuration Guides** - Hypervisor filtering, credential management, multi-site setup

### 🆕 What's New in v2.1.0

- **Improved installer robustness** - Auto-detects and handles missing dependencies
- **Enhanced documentation** - Clear distinction between pre-built packages and source builds
- **Dynamic scoring** - Cyber Resilience weight is removed and redistributed when LTR is not evaluated
- **GitHub Release workflow** - Simplified distribution for end users
- **Updated Quick Start** - Streamlined 5-minute installation process
- **Sanitized documentation** - Enterprise-ready examples (no internal IPs/paths)

---

### 👨‍💻 For Developers

If you want to build from source code instead of using this pre-built package:

1. Clone the repository: `git clone https://github.com/ALastoff/zerto-compliance-tool.git`
2. Install .NET SDK 8.0+ from https://dotnet.microsoft.com/download/dotnet
3. Follow the "Installation from Source" section in the README

---

### 📄 License

MIT License - Free for commercial and personal use

### ⚠️ Legal Disclaimer

This tool is provided as an example only and is not supported under any Zerto support program or service. The author and Zerto disclaim all implied warranties. Use at your own risk.

### 🤝 Support

- **Issues:** https://github.com/ALastoff/zerto-compliance-tool/issues
- **Documentation:** See included guides and README
- **Community:** Contributions welcome via pull requests

---

**Perfect for:** Zerto Administrators, MSPs, IT Compliance Teams, DR Managers, VMware vSphere Admins
