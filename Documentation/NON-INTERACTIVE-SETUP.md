# Non-Interactive Mode Setup Guide

## Overview
Non-interactive mode allows the compliance script to run without any prompts, using only pre-configured credentials and settings. This is ideal for:
- Scheduled/automated runs
- Task Scheduler execution
- CI/CD pipelines
- Quick repeated runs without re-entering credentials

---

## Setup Steps

### 1. Configure auth.config.json

Ensure your `auth.config.json` has all required hypervisor details populated:

```json
{
  "Hypervisors": {
    "Site1": {
      "Host": "primary-zvma.example.com",
      "Enabled": true,
      "CredentialTarget": "Zerto-Source-UI"
    },
    "Site2": {
      "Host": "secondary-zvma.example.com",
      "Enabled": true,
      "CredentialTarget": "Zerto-Target-UI"
    },
    "vCenter": {
      "Host": "tertiary-zvma.example.com",
      "Username": "administrator@vsphere.local",
      "CredentialTarget": "vCenter-Creds"
    }
  },
  "Accounts": {
    "Zerto": {
      "CredentialManagerTarget": "Zerto-Source-UI"
    },
    "vCenter": {
      "CredentialManagerTarget": "vCenter-Creds"
    }
  }
}
```

### 2. Store Credentials in Windows Credential Manager

#### Store Zerto ZVMA Credentials:
```powershell
cmdkey /generic:Zerto-Source-UI /user:admin /pass:YourPasswordHere
```

#### Store vCenter Credentials (optional):
```powershell
cmdkey /generic:vCenter-Creds /user:administrator@vsphere.local /pass:YourVCenterPassword
```

#### Verify Stored Credentials:
```powershell
cmdkey /list
```

You should see entries for:
- `Zerto-Source-UI`
- `vCenter-Creds` (if configured)

---

## Usage

### Option 1: Run with wrapper script (recommended)
```powershell
.\Run-NonInteractive.ps1
```

### Option 2: Run main script directly
```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\ZertoComplianceNew.ps1" `
    -AuthConfigFile ".\auth.config.json" `
    -NonInteractive `
    -SimpleNames
```

---

## What Gets Skipped in Non-Interactive Mode

When using `-NonInteractive`, the script will NOT prompt for:
- ❌ ZVMA Host/IP (must be in auth.config.json)
- ❌ ZVMA Username/Password (must be in Credential Manager)
- ❌ Site 2/Site 3 hosts (must be in auth.config.json)
- ❌ vCenter Server/Credentials (must be in auth.config.json)
- ❌ Analytics keys or MFA codes

**If required credentials are missing, the script will fail immediately with a clear error message.**

---

## Task Scheduler Setup

To run automatically on a schedule:

1. Open Task Scheduler
2. Create Basic Task
3. Trigger: Daily/Weekly (your preference)
4. Action: Start a Program
   - Program: `powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\Run-NonInteractive.ps1"`
   - Start in: `C:\Path\To\Compliance Tool`
5. Settings:
   - ✅ Run whether user is logged on or not
   - ✅ Run with highest privileges
   - ✅ Configure for: Windows 10

---

## Troubleshooting

### Error: "NonInteractive mode requires ZVMAHost to be configured"
**Solution**: Add ZVMAHost to auth.config.json Hypervisors.Site1.Host

### Error: "NonInteractive mode requires Username in config or Credential Manager"
**Solution**: Run `cmdkey /generic:Zerto-Source-UI /user:admin /pass:YourPassword`

### Error: "Failed to authenticate"
**Solution**: Verify credentials stored in Credential Manager are correct:
```powershell
cmdkey /list:Zerto-Source-UI
# Delete and re-add if needed:
cmdkey /delete:Zerto-Source-UI
cmdkey /generic:Zerto-Source-UI /user:admin /pass:CorrectPasswordHere
```

### Script runs but skips vCenter
**Solution**: If you want vCenter integration in non-interactive mode, add it to auth.config.json:
```json
"vCenter": {
  "Host": "vcenter.example.com",
  "Username": "administrator@vsphere.local",
  "CredentialTarget": "vCenter-Creds"
}
```

---

## Security Notes

- Credentials stored in Windows Credential Manager are encrypted per-user using DPAPI
- Only the user account that stored the credentials can retrieve them
- Task Scheduler tasks must run as the same user who stored the credentials
- For production environments, consider using a dedicated service account
- auth.config.json does NOT store passwords - only references to Credential Manager targets

---

## Testing

Test your non-interactive setup:

```powershell
# Dry run to verify config
.\Run-NonInteractive.ps1 -Verbose

# Check the output
Get-ChildItem ".\ZertoCompliance_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

Expected result: Script completes without any prompts, creates full compliance report.
