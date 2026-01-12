# Hypervisor/Zerto Site Configuration Guide

## Overview

The Zerto Compliance Collector now supports managing multiple hypervisor/ZVMA sites through the `auth.config.json` file. This allows you to:

- Pre-configure up to 3 Zerto ZVMA sites (primary, secondary, and optional tertiary)
- Avoid re-entering hypervisor IPs/FQDNs every time you run the script
- Enable/disable sites without modifying the script

## Configuration Structure

### auth.config.json Hypervisors Section

```json
"Hypervisors": {
  "Description": "Hypervisor/ZVMA Site Configurations",
  "Site1": {
    "Name": "Primary Site",
    "Host": "primary-zvma.example.com",
    "Port": 443,
    "Description": "Primary Zerto ZVMA",
    "Enabled": true,
    "Credentials": "SourceZertoUI"
  },
  "Site2": {
    "Name": "Secondary Site",
    "Host": "secondary-zvma.example.com",
    "Port": 443,
    "Description": "Secondary Zerto ZVMA (Peer/Target)",
    "Enabled": false,
    "Credentials": "TargetZertoUI"
  },
  "Site3": {
    "Name": "Tertiary Site",
    "Host": "",
    "Port": 443,
    "Description": "Optional Third Zerto ZVMA",
    "Enabled": false,
    "Credentials": "TertiaryZertoUI"
  }
}
```

## Configuration Fields

| Field | Description | Required |
|-------|-------------|----------|
| `Name` | Human-readable site name | Yes |
| `Host` | IP address or FQDN of the Zerto ZVMA | Yes (if enabled) |
| `Port` | HTTPS port (default: 443) | No |
| `Description` | Site description | No |
| `Enabled` | Whether this site is active | Yes |
| `Credentials` | Reference to credential account (SourceZertoUI, TargetZertoUI, TertiaryZertoUI) | Yes (if enabled) |

## Setup Instructions

### Step 1: Edit auth.config.json

Update the hypervisor section with your environment details:

```json
"Hypervisors": {
  "Site1": {
    "Name": "Production Site",
    "Host": "zerto-prod.company.com",
    "Enabled": true,
    "Credentials": "SourceZertoUI"
  },
  "Site2": {
    "Name": "DR Site",
    "Host": "zerto-dr.company.com",
    "Enabled": true,
    "Credentials": "TargetZertoUI"
  },
  "Site3": {
    "Host": "",
    "Enabled": false
  }
}
```

### Step 2: Store Credentials (One-Time)

Use the `Setup-Credentials.ps1` script to securely store credentials for each site:

```powershell
# Store credentials for each account referenced
.\Setup-Credentials.ps1
```

Credentials are stored in Windows Credential Manager under these targets:
- `Zerto-Source-UI` (Site 1 / Primary)
- `Zerto-Target-UI` (Site 2 / Secondary)
- `Zerto-Tertiary-UI` (Site 3 / Optional)

### Step 3: Run the Script

Now you can run the script without entering hypervisor IPs:

```powershell
# Script will load Site 1 and Site 2 from config
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json -SimpleNames -TotalVmCount 9

# Or prompt for Site 3 configuration interactively if not pre-configured
# The script will ask: "Configure a tertiary (3rd) Zerto site? (y/n)"
```

## Interactive Prompting

If any sites are not configured in `auth.config.json`, the script will prompt you interactively:

```
Enter Primary Site ZVMA IP/FQDN (Site 1): primary-zvma.example.com
Enter ZVMA Admin Username: admin
Enter ZVMA Admin Password: **************
Enter Secondary Site ZVMA IP/FQDN (Site 2, leave blank to skip): secondary-zvma.example.com
Configure a tertiary (3rd) Zerto site? (y/n): y
Enter Tertiary Site ZVMA IP/FQDN (Site 3): 192.168.233.20
```

## Example Configurations

### Single Site (Primary Only)

```json
"Hypervisors": {
  "Site1": {
    "Host": "primary-zvma.example.com",
    "Enabled": true,
    "Credentials": "SourceZertoUI"
  },
  "Site2": {
    "Host": "",
    "Enabled": false
  },
  "Site3": {
    "Host": "",
    "Enabled": false
  }
}
```

### Three-Site Deployment

```json
"Hypervisors": {
  "Site1": {
    "Name": "HQ (Production)",
    "Host": "zerto-hq.company.com",
    "Enabled": true,
    "Credentials": "SourceZertoUI"
  },
  "Site2": {
    "Name": "Regional DC",
    "Host": "zerto-regional.company.com",
    "Enabled": true,
    "Credentials": "TargetZertoUI"
  },
  "Site3": {
    "Name": "Backup Site",
    "Host": "zerto-backup.company.com",
    "Enabled": true,
    "Credentials": "TertiaryZertoUI"
  }
}
```

### Multi-Site with Site 2 Disabled

```json
"Hypervisors": {
  "Site1": {
    "Host": "zerto-prod.company.com",
    "Enabled": true,
    "Credentials": "SourceZertoUI"
  },
  "Site2": {
    "Host": "zerto-dr.company.com",
    "Enabled": false,
    "Credentials": "TargetZertoUI"
  },
  "Site3": {
    "Host": "",
    "Enabled": false
  }
}
```

## Best Practices

1. **Pre-configure your environment**: Update `auth.config.json` with your site information once, then the script never needs manual input for sites.

2. **Use meaningful names**: Give each site a descriptive name for clarity:
   ```json
   "Name": "Primary Production Site"
   "Name": "Secondary DR Site"
   "Name": "Tertiary Backup Site"
   ```

3. **Secure credentials**: Always use `Setup-Credentials.ps1` to store passwords in Windows Credential Manager (encrypted with DPAPI).

4. **Disable unused sites**: Set `Enabled: false` for sites you don't need:
   ```json
   "Site3": {
     "Host": "",
     "Enabled": false
   }
   ```

5. **Update regularly**: If your site IPs/FQDNs change, update `auth.config.json` and store new credentials if needed.

## Credential Mapping

The script maps sites to credential accounts:

| Site | Credential Account | Credential Manager Target |
|------|-------------------|---------------------------|
| Site 1 (Primary) | SourceZertoUI | `Zerto-Source-UI` |
| Site 2 (Secondary) | TargetZertoUI | `Zerto-Target-UI` |
| Site 3 (Tertiary) | TertiaryZertoUI | `Zerto-Tertiary-UI` |

Store credentials for each account using:
```powershell
.\Setup-Credentials.ps1
```

## Troubleshooting

### Issue: Site not being loaded from config

**Solution**: Verify the site is enabled in `auth.config.json`:
```json
"Site1": {
  "Host": "primary-zvma.example.com",
  "Enabled": true  # Must be true
}
```

### Issue: Credentials not found

**Solution**: Store credentials using the setup script:
```powershell
.\Setup-Credentials.ps1
```

Then verify they exist:
```powershell
cmdkey /list
```

### Issue: Still getting prompted for sites

**Solution**: Ensure `auth.config.json` is loaded with `-AuthConfigFile` parameter:
```powershell
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json ...
```

## Command-Line Overrides

You can override config settings with command-line parameters:

```powershell
# Override Site 1 with command-line parameter
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json -ZVMAHost "alternate-host.com" ...

# Override Site 2
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json -Site2Host "alternate-dr.com" ...

# Override Site 3
.\ZertoComplianceNew.ps1 -AuthConfigFile auth.config.json -Site3Host "alternate-backup.com" -EnableSite3 ...
```

## Summary

The hypervisor configuration feature allows you to:

✅ Pre-configure sites in `auth.config.json`  
✅ Store credentials securely in Windows Credential Manager  
✅ Run the script without re-entering site information  
✅ Enable/disable sites without code changes  
✅ Support up to 3 Zerto sites (primary, secondary, optional tertiary)  
✅ Override settings with command-line parameters when needed  

This eliminates repetitive manual input and makes the compliance collector easier to schedule and automate.
