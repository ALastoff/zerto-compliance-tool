# Zerto Compliance Tool

A lightweight, enterprise-ready audit tool for Zerto environments. Generates actionable compliance reports with executive summaries, score cards, and evidence.

## Features
- Executive HTML report with clear score cards
- VM coverage and DR testing analytics
- Optional cyber resilience checks (LTR locking)
- Non-interactive mode using stored creds and `auth.config.json`
- Scheduled task creation (Daily/Weekly/Monthly)
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

## Scheduling
Use the "Schedule Task" button in the UI to create an automated audit at 2:00 AM. Runs the `Run-ComplianceAudit.ps1` with your parameters.

## TLS Certificates
Prefer secure TLS. Import customer CA certs per `IMPORT-CERTIFICATE.md`. Leave the lab checkbox enabled for testing, but disable in production.

## Upgrade
See `UPGRADE.md` for a safe upgrade process.

## Contributing
- Open issues and pull requests on GitHub
- Keep sensitive info out of commits
- Follow PS and C# style guides; avoid hard-coded paths

## License
Contact HPE/Zerto for licensing terms.
