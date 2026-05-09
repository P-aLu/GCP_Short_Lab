# Usage: .\scripts\all-labs.ps1 <apply|destroy>
# Env:   $env:SKIP_LABS = "lab-02-foo lab-03-bar"  (space-separated, optional)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("apply","destroy")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$LabsDir   = Join-Path $RepoRoot "labs"
$LabScript = Join-Path $ScriptDir "lab.ps1"

# ── Discover labs ─────────────────────────────────────────────────────────────
$AllLabs = Get-ChildItem -Path $LabsDir -Directory -Filter "lab-*" |
           Sort-Object Name |
           Select-Object -ExpandProperty Name

if ($AllLabs.Count -eq 0) {
    Write-Host "No lab directories found under $LabsDir"
    exit 0
}

# Reverse order for destroy so last lab is torn down first
if ($Action -eq "destroy") {
    [array]::Reverse($AllLabs)
}

# ── Build skip set ────────────────────────────────────────────────────────────
$SkipSet = @{}
$skipEnv = $env:SKIP_LABS
if ($skipEnv) {
    foreach ($s in ($skipEnv -split '\s+')) {
        if ($s) { $SkipSet[$s] = $true }
    }
}

# ── Run ───────────────────────────────────────────────────────────────────────
$Passed  = [System.Collections.Generic.List[string]]::new()
$Failed  = [System.Collections.Generic.List[string]]::new()
$Skipped = [System.Collections.Generic.List[string]]::new()

foreach ($lab in $AllLabs) {
    if ($SkipSet.ContainsKey($lab)) {
        Write-Host "==> SKIP $lab"
        $Skipped.Add($lab)
        continue
    }

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════"
    Write-Host "  $($Action.ToUpper()): $lab"
    Write-Host "════════════════════════════════════════════════════"

    try {
        & $LabScript $Action $lab
        $Passed.Add($lab)
    } catch {
        $Failed.Add($lab)
        Write-Host ""
        Write-Host "ERROR: $lab failed. Stopping."
        Write-Host $_.Exception.Message
        break
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════════════════"
Write-Host "  SUMMARY"
Write-Host "════════════════════════════════════════════════════"
Write-Host "  Passed  : $($Passed.Count)  -> $(if ($Passed.Count)  { $Passed  -join ', ' } else { 'none' })"
Write-Host "  Skipped : $($Skipped.Count) -> $(if ($Skipped.Count) { $Skipped -join ', ' } else { 'none' })"
Write-Host "  Failed  : $($Failed.Count)  -> $(if ($Failed.Count)  { $Failed  -join ', ' } else { 'none' })"
Write-Host "════════════════════════════════════════════════════"

if ($Failed.Count -gt 0) { exit 1 }
