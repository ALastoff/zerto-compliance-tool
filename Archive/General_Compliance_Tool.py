import requests
import getpass
import csv
import warnings
from datetime import datetime, timedelta

# Suppress insecure cert warnings
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

def get_zvma_token(ip, user, password):
    token_url = f"https://{ip}/auth/realms/zerto/protocol/openid-connect/token"
    payload = {'client_id': 'zerto-client', 'grant_type': 'password', 'username': user, 'password': password, 'scope': 'openid'}
    response = requests.post(token_url, data=payload, verify=False)
    response.raise_for_status()
    return response.json().get('access_token')

def get_analytics_token(api_key):
    auth_url = "https://analytics.api.zerto.com/v2/auth/token"
    headers = {"Authorization": f"Bearer {api_key}"}
    response = requests.post(auth_url, headers=headers)
    response.raise_for_status()
    return response.json().get('token')

def run_compliance_collector():
    print("\n" + "="*45)
    print(" ZERTO 10.x TAM COMPLIANCE DASHBOARD ")
    print("="*45)
    
    zvma_ip = input("Enter ZVMA IP: ")
    zvma_user = input("Enter ZVMA Admin Username: ")
    zvma_pass = getpass.getpass("Enter ZVMA Admin Password: ")
    analytics_key = getpass.getpass("Enter Analytics API Key: ")
    use_ltr = input("\nIs this customer using LTR/EJC? (y/n): ").lower().strip() == 'y'

    try:
        # Authentication
        bearer_token = get_zvma_token(zvma_ip, zvma_user, zvma_pass)
        zvma_headers = {"Authorization": f"Bearer {bearer_token}"}
        analytics_token = get_analytics_token(analytics_key)
        a_headers = {"Authorization": f"Bearer {analytics_token}"}

        # Data Containers
        report_rows = []
        score_metrics = {'tests_passed': 0, 'total_vpgs': 0, 'unprotected_vms': 0, 'locked_vpgs': 0, 'ltr_vpgs': 0}

        # --- 1. TEST COMPLIANCE ---
        recovery_data = requests.get(f"https://{zvma_ip}/v1/reports/recovery?type=FailoverTest", headers=zvma_headers, verify=False).json()
        six_months_ago = datetime.now() - timedelta(days=180)
        
        # Track unique VPG tests
        tested_vpgs = set()
        for report in recovery_data:
            test_date = datetime.fromisoformat(report.get('StartTime').replace('Z', ''))
            if report.get('Status') == 'Success' and test_date > six_months_ago:
                tested_vpgs.add(report.get('VpgName'))
            
            report_rows.append({
                'Audit_Domain': 'Availability (DR Testing)',
                'Entity': report.get('VpgName'),
                'Detail': f"RTO: {report.get('RTOInSeconds')}s",
                'Status': report.get('Status'),
                'Timestamp': report.get('StartTime')
            })

        # --- 2. VPG & LTR CHECKS ---
        vpg_data = requests.get(f"https://{zvma_ip}/v1/vpgs", headers=zvma_headers, verify=False).json()
        score_metrics['total_vpgs'] = len(vpg_data)
        score_metrics['tests_passed'] = len(tested_vpgs)

        if use_ltr:
            for vpg in vpg_data:
                ltr = vpg.get('LtrSettings', {})
                if ltr and ltr.get('TargetRepositoryName'):
                    score_metrics['ltr_vpgs'] += 1
                    lock_active = ltr.get('IsRetentionLockEnabled', False)
                    if lock_active: score_metrics['locked_vpgs'] += 1
                    
                    report_rows.append({
                        'Audit_Domain': 'Cyber_Resilience',
                        'Entity': vpg.get('VpgName'),
                        'Detail': f"Repo: {ltr.get('TargetRepositoryName')}",
                        'Status': "SECURE" if lock_active else "RISK (No Lock)",
                        'Timestamp': datetime.now().isoformat()
                    })

        # --- 3. INVENTORY CHECK ---
        vm_data = requests.get("https://analytics.api.zerto.com/v2/monitoring/protected-vms", headers=a_headers).json()
        total_vms = len(vm_data)
        for vm in vm_data:
            if not vm.get('VpgName'):
                score_metrics['unprotected_vms'] += 1
                report_rows.append({
                    'Audit_Domain': 'Inventory_Coverage',
                    'Entity': vm.get('VmName'),
                    'Detail': 'Unprotected VM',
                    'Status': 'AUDIT_RISK',
                    'Timestamp': datetime.now().isoformat()
                })

        # --- SCORE CALCULATION ---
        test_score = (score_metrics['tests_passed'] / score_metrics['total_vpgs']) * 40 if score_metrics['total_vpgs'] > 0 else 40
        coverage_score = ((total_vms - score_metrics['unprotected_vms']) / total_vms) * 30 if total_vms > 0 else 30
        
        # Cyber score (Weighted at 30%)
        if use_ltr and score_metrics['ltr_vpgs'] > 0:
            cyber_score = (score_metrics['locked_vpgs'] / score_metrics['ltr_vpgs']) * 30
        else:
            cyber_score = 30 # Default to 30 if LTR isn't used (don't penalize)
        
        total_score = int(test_score + coverage_score + cyber_score)

        # CSV Export
        filename = f"Zerto_Compliance_{datetime.now().strftime('%Y%m%d')}.csv"
        with open(filename, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['Audit_Domain', 'Entity', 'Detail', 'Status', 'Timestamp'])
            writer.writeheader()
            writer.writerows(report_rows)

        # Print Executive Summary
        print("\n" + "*"*30)
        print(f" OVERALL COMPLIANCE SCORE: {total_score}%")
        print("*"*30)
        print(f" - DR Testing: {score_metrics['tests_passed']}/{score_metrics['total_vpgs']} VPGs tested (last 6mo)")
        print(f" - Coverage:   {total_vms - score_metrics['unprotected_vms']}/{total_vms} VMs protected")
        if use_ltr:
            print(f" - Immutability: {score_metrics['locked_vpgs']}/{score_metrics['ltr_vpgs']} LTR VPGs locked")
        print(f"\nDetailed Evidence Exported to: {filename}\n")

    except Exception as e:
        print(f"\n[!] Error: {e}")

if __name__ == "__main__":
    run_compliance_collector()