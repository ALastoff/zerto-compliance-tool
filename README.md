# Zerto Compliance Tool - Automated DR Testing & VM Protection Audit

**Automated compliance assessment tool for Zerto disaster recovery environments.** Evaluate DR testing frequency, VM protection coverage, and cyber resilience with interactive HTML reports.

## About

The Zerto Compliance Tool helps IT teams automate disaster recovery compliance assessments for VMware vSphere, Hyper-V, and cloud environments protected by Zerto Virtual Replication. Monitor VPG testing frequency, track VM protection gaps, validate cyber resilience configurations, and generate professional audit reports—eliminating manual spreadsheet tracking.

**Ideal For:** VMware administrators, disaster recovery managers, compliance officers, MSPs, IT security teams, SOC 2/ISO 27001/HIPAA audits

**Keywords:** Zerto compliance audit, disaster recovery testing automation, VM protection monitoring, VPG compliance checker, Zerto reporting tool, cyber resilience scoring, business continuity audit, Zerto PowerShell automation, RTO RPO validation, ransomware protection assessment

A lightweight, enterprise-ready audit solution for IT administrators and disaster recovery professionals managing Zerto Virtual Replication. This free, open-source PowerShell tool generates actionable compliance reports with executive summaries, score cards, and audit evidence.

**For detailed instructions, see `DEPLOYMENT_GUIDE.html` or `QUICK_START.md`.**

## Features
- Executive HTML report with clear score cards
- VM coverage and DR testing analytics
- Optional cyber resilience checks (LTR locking)
- Non-interactive mode using stored creds and `auth.config.json`
- Modern UI (WinForms, .NET 8)

## Install
1. Extract the deployment ZIP
2. Run `Setup-Environment.ps1` (Administrator)
3. Run `Install-ZertoComplianceLauncher.ps1` (Administrator)
4. Launch from Start Menu or Desktop shortcut

## Usage
- Enter ZVM/ZVMA hostname, username, and password
- Choose output folder and click Run Audit
- Optional: enable "Allow insecure SSL" for labs (not recommended in production)
- Optional: enable LTR checks (Cyber Resilience)

## Reports
Outputs are written to:
`ComplianceAudit_<host>_<YYYY-MM-DD_HHMMSS>/`

Key files:
- `Report.html` — main report
- `Evidence.csv` — control evidence
- `Summary.txt`, `Manifest.json`, `ControlsMap.txt`, `Log.txt`, `Transcript.txt`
- `RecoveryReports/` — detailed DR JSON reports

## TLS Certificates
Prefer secure TLS. Import customer CA certs per `IMPORT-CERTIFICATE.md`. Leave the lab checkbox enabled for testing, but disable in production.

## Upgrade
See `UPGRADE.md` for a safe upgrade process.

## Contributing
- Open issues and pull requests on GitHub
- Keep sensitive info out of commits
- Follow PS and C# style guides; avoid hard-coded paths
---
## Legal Disclaimer

This script is provided as an example only and is not supported under any Zerto support program or service.

The author and Zerto disclaim all implied warranties, including merchantability and fitness for a particular purpose.
In no event shall Zerto or the author be liable for damages arising from the use or inability to use this script.
Use at your own risk.
