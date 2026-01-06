# Zerto Compliance Collector - Secure Credential Setup Guide

## Overview

This guide explains how to securely configure credentials for the Zerto Compliance Collector using Windows Credential Manager with DPAPI (Data Protection API) encryption.

## Why This Approach?

✅ **Secure**: Credentials are encrypted using Windows DPAPI  
✅ **No Plain Text**: Passwords never stored in readable form  
✅ **Built-in**: Uses native Windows security, no external tools needed  
✅ **User/Machine Scoped**: Encryption tied to user or machine  
✅ **Easy to Revoke**: Simple `cmdkey /delete` to remove  

## Quick Start (5 minutes)

### Step 1: Store Credentials in Windows Credential Manager

Run the setup script:

```powershell
cd "C:\Users\Administrator\Documents\Scripts\Compliance Tool"
.\Setup-Credentials.ps1
```

This interactive script will prompt you to:
- Enter username and password for each account
- Store them securely in Windows Credential Manager

### Step 2: Update auth.config.json

Edit `auth.config.json` and enable the accounts you configured:

```json
{
  "Accounts": {
    "SourceZertoUI": {
      "Host": "192.168.111.20",
      "Port": 443,
      "UseCredentialManager": true,
      "CredentialTarget": "Zerto-Source-UI",
      "Enabled": true
    }
  }
}
```

### Step 3: Run the Compliance Collector

```powershell
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json -SimpleNames -TotalVmCount 9
```

The script will automatically retrieve credentials from Credential Manager.

---

## Credential Targets

| Target | Purpose | Default Username |
|--------|---------|------------------|
| `Zerto-Source-UI` | Source ZVMA UI account | `admin` |
| `Zerto-Target-UI` | Target ZVMA UI account | `admin` |
| `Zerto-Source-OS` | Source ZVMA OS/SSH account | `zadmin` |
| `Zerto-Target-OS` | Target ZVMA OS/SSH account | `zadmin` |
| `MyZerto-Account` | MyZerto Analytics account | `<your-email>` |
| `vCenter-Source` | Source vCenter account | `administrator@vsphere.local` |
| `vCenter-Target` | Target vCenter account | `administrator@vsphere.local` |

---

## Manual Credential Management

### Store a credential manually:

```powershell
cmdkey /add:Zerto-Source-UI /user:admin /pass:YourPassword
```

### List all stored credentials:

```powershell
cmdkey /list
```

### Delete a credential:

```powershell
cmdkey /delete:Zerto-Source-UI
```

---

## Security Notes

### How DPAPI Works

1. **Encryption**: When you store a credential, Windows encrypts it using DPAPI
2. **User-Scoped**: By default, only the logged-in user can decrypt it
3. **Machine-Scoped**: Optionally, any user on the machine can decrypt it
4. **Login Required**: Credentials are inaccessible if system is locked

### Local Isolation

- Credentials are stored locally in `%APPDATA%\Microsoft\Credentials\`
- Cannot be accessed from another machine
- Cannot be accessed by another user (by default)

### Compliance Benefits

✅ Audit logging available via Windows Event Log  
✅ No passwords in configuration files  
✅ No credentials in script parameters  
✅ No credentials in PowerShell history  
✅ Meets HIPAA, PCI-DSS, SOC 2 requirements for credential storage  

---

## Troubleshooting

### Credential Not Found

```
Error: Credentials not found in Credential Manager for target: Zerto-Source-UI
```

**Solution**: Run `.\Setup-Credentials.ps1` and store credentials for that target.

### Access Denied

```
Error: Access Denied - Cannot store credential
```

**Solution**: May require administrator privileges. Run PowerShell as Administrator:

```powershell
Start-Process powershell -Verb RunAs
```

### Script Can't Retrieve Credentials

If the script runs but can't access stored credentials:

1. Verify credentials exist: `cmdkey /list`
2. Check that `"UseCredentialManager": true` in auth.config.json
3. Verify `"CredentialTarget"` matches the stored target name exactly
4. Run setup script again to re-store credentials

---

## Advanced: Credential Manager API Integration

For even more security, consider extending this to:

1. **Azure Key Vault**: Store credentials in Azure
2. **HashiCorp Vault**: Enterprise secret management
3. **Active Directory**: Domain-based credential storage

Contact your IT security team for guidance on these options.

---

## File Structure

```
Compliance Tool/
├── ZertoComplianceNew.ps1          # Main script (uses credentials)
├── auth.config.json                # Configuration (no passwords!)
├── Setup-Credentials.ps1           # Helper to store credentials
└── SECURE-CREDENTIALS.md           # This file
```

---

## Example: Complete Setup

### 1. Store Source Zerto credentials:

```powershell
.\Setup-Credentials.ps1
# When prompted for "Zerto-Source-UI":
#   Username: admin
#   Password: Dorchester/ma1987
```

### 2. Configure auth.config.json:

```json
{
  "Accounts": {
    "SourceZertoUI": {
      "Host": "192.168.111.20",
      "Port": 443,
      "Realm": "zerto",
      "UseCredentialManager": true,
      "CredentialTarget": "Zerto-Source-UI",
      "Enabled": true
    }
  }
}
```

### 3. Run the collector:

```powershell
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json
```

✓ Credentials are now securely managed!

---

## Support

For questions or issues:
- Review Windows Credential Manager documentation
- Check PowerShell error logs
- Verify credentials with `cmdkey /list`
- Run Setup-Credentials.ps1 again if issues persist

