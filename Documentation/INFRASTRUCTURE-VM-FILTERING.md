# Infrastructure VM Filtering Documentation

**Version:** 1.0.1  
**Last Updated:** 2025-12-31  
**Status:** Production

---

## Overview

The Zerto Compliance Tool automatically excludes **infrastructure VMs** from protection coverage calculations to provide accurate compliance scores. Infrastructure VMs are system-level virtual machines that either cannot or should not be protected by Zerto.

---

## Current Filtering Logic

### VMs Excluded from Coverage Calculations

#### 1. **vCLS VMs (vSphere Cluster Services)**
- **Pattern**: `^vCLS` or contains `vCLS` as a word
- **Reason**: VMware infrastructure VMs that manage cluster services
- **Examples**: `vCLS-12345`, `vCLS_vm`, `vCLS-Production-Cluster`
- **Confidence**: ✅ **High** - Consistent naming across all vSphere environments

#### 2. **Zerto VRA VMs (Virtual Replication Appliance)**
- **Pattern**: Starts with `Z-VRA-`
- **Reason**: Zerto replication infrastructure, auto-deployed per ESXi host
- **Examples**: `Z-VRA-esxi01`, `Z-VRA-192.168.1.10`
- **Confidence**: ✅ **High** - Zerto uses consistent naming convention

---

## VMs NOT Filtered (Intentionally)

### ZVM (Zerto Virtual Manager)
- **Why not filtered by pattern?** Customer environments may have VMs with "ZVM" in the name that are **not** the actual Zerto Virtual Manager (e.g., `ZVM-Database`, `ZVM-Test-App`)
- **Current approach**: ZVM VM is **NOT filtered** to avoid false positives
- **Implication**: If ZVM shows as "unprotected," this is expected behavior
- **Best practice**: Users should manually exclude the ZVM VM if desired, or accept it as unprotected

### vCenter Server / VCSA
- **Why not filtered?** vCenter VM name is **not standardized** across deployments
  - Could be: `vCenter`, `vcsa`, `VC01`, `VMware-vCenter-Server`, or custom names
- **Risk**: Pattern matching `vCenter` could catch production VMs named `vCenter-DB` or `vCenter-Reports`
- **Current approach**: **NOT filtered**
- **Note**: vCenter can be protected by Zerto (though uncommon)

### NSX Manager / Controller
- **Why not filtered?** Similar to vCenter - naming varies widely
- **Examples**: `NSX-Manager-01`, `nsxmgr`, `NSX-DC1`, or custom names
- **Current approach**: **NOT filtered**

### vSAN Witness VMs
- **Why not filtered?** Naming not consistent (e.g., `vSAN-Witness`, `witness-01`, or hypervisor-specific names)
- **Current approach**: **NOT filtered**

---

## Implementation Details

### Code Location
**File**: `Run-ComplianceAudit.ps1`  
**Function**: `$vmNameIsInfrastructure` scriptblock (lines 2440-2450)

```powershell
$vmNameIsInfrastructure = {
  param($n)
  if (-not $n) { return $false }
  # vCLS (vSphere Cluster Services) - reliable pattern
  if ($n -match '^(?i)vCLS(\b|[-_])' -or $n -match '(?i)\bvCLS\b') { return $true }
  # Zerto VRA (Virtual Replication Appliance) - consistent naming Z-VRA-xxx
  if ($n -match '^(?i)Z-VRA-') { return $true }
  return $false
}
```

### Where Filter is Applied

1. **Protected VM List** (line 2455):
   ```powershell
   $protectedVmNamesEx = $protectedVmNames | Where-Object { -not (& $vmNameIsInfrastructure $_) }
   ```

2. **Unprotected VM List** (line 2456):
   ```powershell
   $unprotectedVmNamesEx = $unprotectedVmNames | Where-Object { -not (& $vmNameIsInfrastructure $_) }
   ```

3. **CSV Evidence Export** (lines 2520-2523):
   ```powershell
   $filteredRows = $allRows | ForEach-Object { [pscustomobject]$_ } | Where-Object { 
     (-not $_.Entity -or -not (& $vmNameIsInfrastructure $_.Entity)) -and 
     (-not $_.Detail -or -not (& $vmNameIsInfrastructure $_.Detail))
   }
   ```

4. **HTML Report VM Lists** (lines 3100-3125):
   - Protected VMs section displays `$protectedVmNamesEx`
   - Unprotected VMs section displays `$unprotectedVmNamesEx`

5. **Scoring Calculation** (lines 2458-2462):
   ```powershell
   $displayProtected = $protectedVmNamesEx.Count
   $displayUnprot   = $unprotectedVmNamesEx.Count
   $displayTotal    = $displayProtected + $displayUnprot
   $coverageEffectiveness = [double]$displayProtected / [double]$displayTotal * 100.0
   ```

---

## Testing & Validation

### Expected Behavior

**Scenario 1: vCLS VMs Present**
- vCenter environment has 3 vCLS VMs: `vCLS-12345`, `vCLS-67890`, `vCLS-abc`
- Tool discovers 10 total VMs (7 production + 3 vCLS)
- **Result**: Report shows "7 VMs in environment" (vCLS excluded)

**Scenario 2: VRA VMs Present**
- Zerto environment has 4 ESXi hosts with VRAs: `Z-VRA-esxi01` through `Z-VRA-esxi04`
- Tool discovers 20 total VMs (16 production + 4 VRAs)
- **Result**: Report shows "16 VMs in environment" (VRAs excluded)

**Scenario 3: ZVM Named "ZVM-Right"**
- ZVM VM is literally named `ZVM-Right`
- **Result**: ZVM-Right appears as "unprotected" (intentional behavior)
- **Rationale**: We cannot distinguish this from a production VM named `ZVM-Database`

**Scenario 4: vCenter Named "vCenter-Production"**
- vCenter VM is named `vCenter-Production`
- **Result**: vCenter-Production appears in VM lists (intentional behavior)
- **Rationale**: Protects against false positives like `vCenter-Backup-Server`

---

## Manual Exclusion Options

If users need to exclude additional VMs (e.g., specific ZVM, vCenter, backup servers), they have two options:

### Option 1: Pre-Filter VM List
Modify the `Get-AllVirtualizationSiteVms` function to exclude specific VM GUIDs/identifiers before returning the list.

### Option 2: Post-Audit Filtering
After audit completes, manually edit the CSV to remove unwanted VMs from evidence, then recalculate scores.

### Option 3: Custom Filter Function (Advanced)
Add custom exclusion logic to `$vmNameIsInfrastructure` scriptblock:
```powershell
# Custom exclusion for specific VM names
if ($n -match '^(?i)(MyZVM|MyVCenter|MyNSX)$') { return $true }
```

---

## Future Enhancements

### Potential Improvements (v2.0+)

1. **API-Based Exclusion**:
   - Query Zerto API for ZVM VM identifier/name
   - Dynamically exclude the actual ZVM VM (not pattern-based)
   - **Effort**: Medium (requires additional API endpoint discovery)

2. **User-Configurable Exclusion List**:
   - Config file: `exclusions.config.json`
   - Users specify exact VM names or patterns to exclude
   - **Effort**: Low (simple file parsing + filter logic)

3. **VM Tagging Integration**:
   - Read vCenter tags (e.g., `zerto:exclude=true`)
   - Exclude VMs based on custom attributes
   - **Effort**: High (requires vCenter API integration)

4. **Machine Learning-Based Classification**:
   - Train model to identify infrastructure VMs by characteristics (CPU, memory, naming patterns)
   - **Effort**: Very High (requires ML training data + model deployment)

---

## Troubleshooting

### Issue: vCLS VMs still appearing in report
**Symptom**: VMs like `vCLS-12345` showing in unprotected list  
**Cause**: Filter regex not matching VM name format  
**Solution**: Check VM name exactly as returned by API; update regex pattern if needed

### Issue: Production VM incorrectly excluded
**Symptom**: VM named `my-vcls-server` (production app) is excluded  
**Cause**: VM name contains `vcls` substring  
**Solution**: Refine regex to match only `vCLS` at word boundaries or start of string

### Issue: ZVM showing as unprotected
**Symptom**: ZVM VM appears in "Unprotected VMs" list  
**Cause**: Intentional design to avoid false positives  
**Solution**: This is expected behavior; ZVM should generally not be protected by Zerto

---

## References

- **VMware vCLS Documentation**: https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.resmgmt.doc/GUID-B5D1E1A6-B3E0-4CF4-9E57-FEA96E4CAA10.html
- **Zerto VRA Architecture**: https://help.zerto.com/bundle/Admin.VC.HTML/page/Virtual_Replication_Appliance.htm
- **PowerShell Regex Guide**: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions

---

## Change Log

### v1.0.1 (2025-12-31)
- Removed ZVM/vCenter/NSX pattern matching to prevent false positives
- Retained only vCLS and Z-VRA-* patterns (high confidence)
- Clarified intentional behavior for ZVM and vCenter exclusion
- Updated CSV filtering to use `$vmNameIsInfrastructure` function

### v1.0.0 (2025-12-26)
- Initial vCLS VM filtering implementation
- Basic regex pattern matching for infrastructure VMs

---

*For questions or feature requests, contact the Zerto Compliance Tool team.*
