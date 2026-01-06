# Pre-Deployment Environment Checklist

**Zerto Compliance Tool v2.1.0**  
**Date:** _______________  
**Environment:** _______________  
**Tested By:** _______________

---

## 📋 Pre-Installation Requirements

### Windows Server/Workstation

- [ ] Windows Server 2016 or later (or Windows 10/11 Pro/Enterprise)
- [ ] 500 MB available disk space (minimum)
- [ ] Local Administrator access on target machine
- [ ] PowerShell 5.1+ available
  ```powershell
  $PSVersionTable.PSVersion
  ```

### Network & Connectivity

- [ ] Outbound HTTPS accessible to primary ZVMA
  - Port 443 (Zerto 10.x Linux)
  - Port 9669 (Zerto 9.x Windows)
  ```powershell
  # Test Zerto 10.x
  Test-NetConnection -ComputerName <ZVMA-IP> -Port 443
  # Test Zerto 9.x
  Test-NetConnection -ComputerName <ZVMA-IP> -Port 9669
  ```
- [ ] DNS resolution working (if using hostnames)
  ```powershell
  Resolve-DnsName <ZVMA-hostname>
  ```
- [ ] No restrictive firewall rules blocking PowerShell execution
- [ ] Internet connectivity available (for .NET installation)

### .NET Runtime

- [ ] Check for existing .NET 8.0 Desktop Runtime
  ```powershell
  dotnet --list-runtimes
  ```
- [ ] If not installed, verify internet access for download
- [ ] At least 500 MB disk space for runtime installation

---

## 🔐 Zerto Environment Validation

### ZVMA Access

- [ ] Zerto version 8.5 or later
  ```powershell
  # Will be verified during installation
  ```
- [ ] Valid Zerto user account with API read access
  - Username: _______________
  - Verified: [ ] Yes [ ] No
- [ ] Password tested and working
  - [ ] Yes [ ] No

### Primary Site (Source)

- [ ] ZVMA IP/Hostname: _______________
- [ ] Network connectivity verified
- [ ] API port accessible (443 for Zerto 10.x / 9669 for Zerto 9.x)
- [ ] Valid SSL certificate (or Lab Mode checkbox available)
- [ ] User credentials functional

### Secondary Site (if applicable)

- [ ] ZVMA IP/Hostname: _______________
- [ ] Network connectivity verified
- [ ] API port accessible (443 for Zerto 10.x / 9669 for Zerto 9.x)
- [ ] Credentials verified (same as primary / different)
  - [ ] Same credentials
  - [ ] Different credentials (specify below)
  - Secondary Username: _______________
- [ ] Valid SSL certificate (or Lab Mode checkbox available)

### Additional Sites (3+ if applicable)

- [ ] Site 3 IP/Hostname: _______________
- [ ] Site 4 IP/Hostname: _______________
- [ ] Site 5 IP/Hostname: _______________
- [ ] All sites network accessible
- [ ] Credentials validated for each

---

## 📦 Deployment Files

### Required Files Present

- [ ] `ZertoComplianceLauncher.exe` (GUI application)
- [ ] `ZertoComplianceNew.ps1` (PowerShell script)
- [ ] `Install-ZertoComplianceLauncher.ps1` (installer)
- [ ] `Uninstall-ZertoComplianceLauncher.ps1` (cleanup)
- [ ] `dotnet-install.ps1` (.NET installer)
- [ ] `DEPLOYMENT_GUIDE.html` (documentation)
- [ ] `QUICK_START.md` (quick reference)

### File Integrity

- [ ] All files copied to deployment location
- [ ] File sizes match expected sizes (see PACKAGE_MANIFEST.json)
- [ ] No corrupted files detected

---

## 🛠️ Installation Steps

### Step 1: Prepare Environment

- [ ] Create deployment working directory
  ```powershell
  mkdir "C:\ZertoCompliance_Deploy"
  ```
- [ ] Copy all package files to working directory
- [ ] Verify all files present and accessible

### Step 2: Install .NET 8.0 (if needed)

- [ ] Run dotnet-install.ps1 with admin privileges
  ```powershell
  powershell -ExecutionPolicy Bypass -File dotnet-install.ps1
  ```
- [ ] Wait for completion (2-5 minutes)
- [ ] Verify installation
  ```powershell
  dotnet --version
  ```
- [ ] .NET version: _______________
- [ ] Installation: [ ] Successful [ ] Failed

### Step 3: Run Installer

- [ ] Run as Administrator
  ```powershell
  powershell -ExecutionPolicy Bypass -File Install-ZertoComplianceLauncher.ps1
  ```
- [ ] Monitor progress window
- [ ] Wait for completion
- [ ] Installation log location: _______________
- [ ] Installation: [ ] Successful [ ] Failed

### Step 4: Verify Installation

- [ ] Check installation directory exists
  ```powershell
  Test-Path "C:\Program Files\ZertoCompliance"
  ```
- [ ] Verify required files in Program Files
  ```powershell
  ls "C:\Program Files\ZertoCompliance"
  ```
- [ ] Desktop shortcut created: [ ] Yes [ ] No
- [ ] Application launches successfully
  ```powershell
  & "C:\Program Files\ZertoCompliance\ZertoComplianceLauncher.exe"
  ```

---

## ⚙️ Configuration Testing

### Launch Application

- [ ] Application window opens successfully
- [ ] No error dialogs
- [ ] All UI controls visible and responsive

### Configure Primary Site

- [ ] Source Site field accepts input
- [ ] Zerto GUI User Name field accepts input
- [ ] Password field accepts input (masked)
- [ ] All fields populate correctly

### Configure Secondary Site (if applicable)

- [ ] Secondary Site field visible
- [ ] "Secondary site has different credentials" checkbox functional
- [ ] Secondary Username/Password fields visible (when checked)
- [ ] All fields functional

### Configure Advanced Options

- [ ] Lab Mode checkbox visible and functional
- [ ] Evaluate Cyber Resilience (LTR) checkbox functional
- [ ] Create Scheduled Task checkbox functional
- [ ] Schedule frequency dropdown works

### Test Run

- [ ] Enter valid ZVMA credentials
- [ ] Enter valid username/password
- [ ] Click "Run Now" button
- [ ] Progress bar appears
- [ ] Status updates appear in real-time
- [ ] Scan completes (status: "✓ Compliance scan completed successfully!")
- [ ] Completion dialog appears with report options
- [ ] Report can be opened from completion dialog
- [ ] Folder can be opened from completion dialog

---

## 📊 Validation Results

### Test Scan Execution

- [ ] Scan: [ ] Successful [ ] Failed
- [ ] Duration: _______________ seconds
- [ ] Report generated: [ ] Yes [ ] No
- [ ] Report location: _______________

### Report Validation

- [ ] HTML report opens in browser
- [ ] Report displays dashboard cards
- [ ] Scores calculated correctly
  - Overall Score: _____ %
  - DR Testing: _____ %
  - VM Coverage: _____ %
  - Cyber Resilience: _____ %
- [ ] Sites section displays primary site
- [ ] Recovery sites (if any) visible
- [ ] VPG/VM information present
- [ ] Interactive modals work (click cards to expand)
- [ ] JSON manifest file created
- [ ] LOG.txt file created
- [ ] All output files present

---

## 🔍 Post-Installation Checks

### Help & Support

- [ ] Help button launches email client with correct contact
- [ ] Contact email: aaron.lastoff@hpe.com
- [ ] Subject pre-filled: "Zerto Compliance Tool"

### File Locations

- [ ] Program Files location: C:\Program Files\ZertoCompliance\
- [ ] Output folder accessible and writable
- [ ] Output folder location: _______________

### Uninstall Test (Optional)

- [ ] Run uninstall script
  ```powershell
  powershell -ExecutionPolicy Bypass -File Uninstall-ZertoComplianceLauncher.ps1
  ```
- [ ] Application removed from Program Files
- [ ] Scheduled tasks removed (if any)
- [ ] Uninstall: [ ] Successful [ ] Failed

---

## 🚀 Deployment Readiness

### Pre-Flight Check

- [ ] All requirements met
- [ ] Installation successful
- [ ] Test scan completed successfully
- [ ] Report generated and validated
- [ ] Help/Support functional
- [ ] Uninstall tested (optional)

### Sign-Off

**Ready for Production Deployment:** [ ] Yes [ ] No

**Approved By:** _______________  
**Date:** _______________  
**Notes:** 

_______________________________________________

_______________________________________________

_______________________________________________

---

## 📝 Known Issues or Deviations

| Issue | Resolution | Status |
|-------|-----------|--------|
| | | [ ] Open [ ] Closed |
| | | [ ] Open [ ] Closed |
| | | [ ] Open [ ] Closed |

---

## 🔗 References

- Full Documentation: DEPLOYMENT_GUIDE.html
- Quick Start Guide: QUICK_START.md
- Support Contact: aaron.lastoff@hpe.com
- Tool Version: 2.1.0
- Release Date: December 25, 2025

---

## Appendix: Troubleshooting Reference

### Common Commands

**Test ZVMA Connectivity:**
```powershell
# Zerto 10.x Linux
Test-NetConnection -ComputerName <ZVMA-IP> -Port 443
# Zerto 9.x Windows
Test-NetConnection -ComputerName <ZVMA-IP> -Port 9669
```

**Verify .NET Installation:**
```powershell
dotnet --list-runtimes
```

**Check PowerShell Version:**
```powershell
$PSVersionTable.PSVersion
```

**View Application Logs:**
```powershell
# After a failed scan, check:
# C:\Users\[Username]\Documents\ZertoCompliance\[FolderName]\LOG.txt
```

**Reset Network Credentials:**
```powershell
# Clear cached credentials if needed
cmdkey /delete:192.168.111.20
```

---

**Checklist Version:** 1.0  
**Last Updated:** December 25, 2025
