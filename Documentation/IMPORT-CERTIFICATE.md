# Importing Customer SSL Certificates for Zerto Compliance Tool

This guide explains how to import a customer's SSL certificate so the tool can connect securely without using the "Allow insecure SSL" option.

## When to use this
- Your ZVM/ZVMA uses a certificate signed by a private or enterprise CA
- Browser shows a warning or the tool fails TLS validation unless "Allow insecure SSL" is checked

## What certificate do I need?
You need the CA certificate (root or intermediate) that issued the Zerto ZVM/ZVMA server certificate. Export it in `.cer` or `.crt` format (Base-64 encoded).

## Option A: Import via PowerShell (recommended)
```powershell
# Run as Administrator
$certPath = "C:\Path\To\CustomerCA.cer"
# Trusted Root store (for root CAs)
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root
# Intermediate store (for issuing/intermediate CAs)
# Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\CA
```

## Option B: Import via MMC
1. Press Win+R, type `mmc`, press Enter
2. File → Add/Remove Snap-in → Certificates → Computer account → Local computer
3. Expand `Trusted Root Certification Authorities` (or `Intermediate Certification Authorities`)
4. Right-click `Certificates` → All Tasks → Import
5. Browse to your `.cer` file → Next → Finish

## Verify installation
```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "<Customer CA Name>" } | Select Subject, NotAfter
```

## Use the tool securely
- Leave the "Allow insecure SSL" checkbox **unchecked**
- Enter ZVM/ZVMA hostname (not IP) that matches the certificate's CN/SAN
- If you must use IP, add that IP to the certificate SANs and reissue

## Rollback / Removal
```powershell
# Find certificate by subject and remove it
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "<Customer CA Name>" } | Remove-Item
```

## Notes
- Installing into `LocalMachine` store affects all users; use `CurrentUser` store if you prefer per-user trust
- Restart the Zerto Compliance Tool after installing certificates
- Avoid importing end-entity/server certs into Root; always import the issuing CA certificate
