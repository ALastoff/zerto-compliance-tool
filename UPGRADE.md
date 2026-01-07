# Upgrade Guide

This document explains how to upgrade the Zerto Compliance Tool safely in enterprise environments.

## Versioning
- Semantic versioning: MAJOR.MINOR.PATCH (e.g., 2.1.0)
- Breaking changes increment MAJOR; fixes/features increment MINOR/PATCH

## Pre-Upgrade Checklist
- Confirm .NET 8.0 Desktop Runtime is installed (Setup-Environment.ps1 only needed if missing)
- Close any running instances of the tool
- Review CHANGELOG (if provided) for breaking changes

## Upgrade Steps (Standard)
1. Download the latest deployment package ZIP
2. Extract the ZIP to a temporary folder
3. Run PowerShell as Administrator
4. Execute the installer:
```powershell
powershell -ExecutionPolicy Bypass -File .\Install-ZertoComplianceLauncher.ps1
```
5. Launch the tool from Start Menu or Desktop shortcut

The installer overwrites files in `C:\Program Files\ZertoCompliance\` and preserves shortcuts.

## Configuration Preservation
- The tool does not store credentials in files
- Output folders are created per run under your chosen location, using the pattern:
  `ComplianceAudit_<host>_<YYYY-MM-DD_HHMMSS>`

## Rollback
- Reinstall the previous package using the same steps
- Optionally uninstall current version:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\ZertoCompliance\Uninstall-ZertoComplianceLauncher.ps1"
```

## Troubleshooting
- If launch fails: run `Setup-Environment.ps1`, reboot, then relaunch
- If TLS errors occur: import customer CA cert per `IMPORT-CERTIFICATE.md`
- Check `Log.txt` in the latest `ComplianceAudit_...` output folder
