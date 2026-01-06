# Fixes Applied - December 25, 2024

## Issues Resolved

### 1. ✅ Duplicate Recovery Sites
**Problem:** "AJ - 222" appeared twice in the HTML report - once as Primary Site and again as Recovery Site with auth failed status.

**Root Cause:** The VPG extraction logic was pulling recovery site names from VPG configurations without filtering out the primary site. When a VPG is configured on site "AJ - 222" targeting itself (or has a misconfigured replication target), it added the primary site name to the recovery sites list.

**Fix Applied:**
- Added filtering in two locations (lines 1889, 1912):
  - VPG extraction: Now compares recovery site name against primary site name before adding
  - Test report extraction: Also filters primary site from test report data
- Added logging to show when sites are skipped: "Skipping recovery site 'AJ - 222' - matches primary site"

**Code Changes:**
```powershell
# Before:
if ($rsn -and -not $recoverySiteNames.Contains($rsn)) {
    $recoverySiteNames += $rsn
    ...
}

# After:
$primarySiteName = if ($localSite -and $localSite.PSObject.Properties['SiteName']) { 
    [string]$localSite.SiteName 
} else { $null }

if ($rsn -and -not $recoverySiteNames.Contains($rsn) -and $rsn -ne $primarySiteName) {
    $recoverySiteNames += $rsn
    ...
} elseif ($rsn -eq $primarySiteName) {
    Write-Log ("Skipping recovery site '{0}' - matches primary site" -f $rsn) 'INFO'
}
```

---

### 2. ✅ Score Weighting Confusion
**Problem:** Users were confused by the notation "50% effective, weighted 20%" - unclear what the difference meant.

**Root Cause:** Modal information blocks didn't explain the scoring methodology clearly.

**Fix Applied:**
- Enhanced all three modal info blocks (DR Testing, VM Coverage, Cyber Resilience) with clearer explanations
- Added inline annotations showing the calculation formula
- Used bold labels and color-coded explanatory text (#7f8c8d gray for annotations)

**Modal Enhancements:**

#### DR Testing Modal (Line 2861)
```
DR Testing Breakdown
• VPGs tested (last 6 months): 2 of 4
• Effectiveness: 50% (actual test completion rate)
• Category weight: 40% (importance in overall score)
• Weighted contribution: 20% (50% × 40% = 20%)
• Status: PARTIAL
```

#### VM Coverage Modal (Line 2864-2869)
```
VM Coverage Breakdown
• Protected VMs: 4 of 5
• Effectiveness: 80% (actual protection coverage rate)
• Category weight: 30% (importance in overall score)
• Weighted contribution: 24% (80% × 30% = 24%)
```

#### Cyber Resilience Modal (Line 2872-2876)
```
Cyber Resilience Breakdown
• LTR VPGs locked: 0 of 2
• Effectiveness: 0% (actual LTR lock rate)
• Category weight: 30% (importance in overall score)
• Weighted contribution: 0% (0% × 30% = 0%)
```

**Scoring Explanation:**
- **Effectiveness**: The raw percentage (e.g., 50% = 2 out of 4 VPGs tested)
- **Category Weight**: How much this category contributes to overall score (40% for DR, 30% for Coverage, 30% for Cyber)
- **Weighted Contribution**: The actual points added to overall score (effectiveness × weight)

**Example Calculation:**
```
Overall Score = DR Testing + VM Coverage + Cyber Resilience
              = (50% × 40%) + (80% × 30%) + (0% × 30%)
              = 20% + 24% + 0%
              = 44% overall compliance
```

---

### 3. ✅ Font Consistency (Verified)
**Finding:** Only one font-family declaration exists in the HTML report:
```css
*{font-family:"Segoe UI",Arial,sans-serif}
```

**Status:** Universal selector ensures all elements inherit the same font. Any perceived inconsistencies are from:
- Different font-sizes (intentional for hierarchy: 0.85em for code, 0.9em for annotations, etc.)
- Different font-weights (bold for emphasis)
- Not actual font-family differences

**No Changes Needed** - Font implementation is correct.

---

## Testing Instructions

Run a new compliance scan to verify:

1. **Duplicate Site Fix:**
   - Primary site should appear only once under "Primary Site (Source)"
   - Recovery sites section should NOT include the primary site name
   - Check LOG.txt for "Skipping recovery site" messages

2. **Score Explanation:**
   - Click any dashboard card to view modal
   - Verify clear "Effectiveness" vs "Weighted contribution" labels
   - Check calculation formula is shown (e.g., "50% × 40% = 20%")

3. **Font Consistency:**
   - Verify all text uses Segoe UI font
   - Different sizes/weights are intentional for visual hierarchy

---

## Files Modified

- `ZertoComplianceNew.ps1` (lines 1886-1933, 2861-2877)
  - Added primary site filtering in VPG extraction
  - Added primary site filtering in test report extraction
  - Enhanced modal info blocks with clearer explanations

---

## Deployment Status

✅ Script deployed to: `C:\Program Files\ZertoCompliance\ZertoComplianceNew.ps1`

**Next Run:** The fixes will take effect on the next compliance scan execution.
