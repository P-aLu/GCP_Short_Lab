# Delete all three GCP projects created by setup.ps1.
# Run this AFTER `deploy-chain.ps1 destroy` has cleared Terraform resources.
#
# Usage:
#   .\scripts\destroy-projects.ps1 [-Force]
#
# Options:
#   -Force   Skip the confirmation prompt (useful in CI)

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$TfVars    = Join-Path $RepoRoot "terraform.tfvars"

# -- Validate terraform.tfvars exists ------------------------------------------
if (-not (Test-Path $TfVars)) {
    Write-Error "terraform.tfvars not found — nothing to delete.`nRun setup.ps1 first, or the projects may already be gone."
}

# -- Read project IDs from tfvars ----------------------------------------------
function Read-TfVar([string]$key) {
    $line = Select-String -Path $TfVars -Pattern "^${key}\s*=" | Select-Object -First 1
    if (-not $line) { return "" }
    if ($line.Line -match '=\s*"(.*)"') { return $Matches[1] }
    return ""
}

$ProjectA = Read-TfVar "project_id"
$ProjectB = Read-TfVar "webapp_project_id"
$ProjectC = Read-TfVar "admin_project_id"

if (-not $ProjectA) { Write-Error "project_id not set in terraform.tfvars" }
if (-not $ProjectB) { Write-Error "webapp_project_id not set in terraform.tfvars" }
if (-not $ProjectC) { Write-Error "admin_project_id not set in terraform.tfvars" }

Write-Host "===================================================================="
Write-Host "  Destroy GCP Projects"
Write-Host ""
Write-Host "  Project A (deployments) : $ProjectA"
Write-Host "  Project B (webapp)      : $ProjectB"
Write-Host "  Project C (admin)       : $ProjectC"
Write-Host ""
Write-Host "  Projects enter GCP's 30-day soft-delete window and can be"
Write-Host "  recovered from the GCP Console if needed within that period."
Write-Host ""
Write-Host "  Run deploy-chain.ps1 destroy first if you haven't already."
Write-Host "===================================================================="
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to confirm project deletion"
    if ($confirm -ne "yes") {
        Write-Host "Aborted."
        exit 0
    }
    Write-Host ""
}

# -- Helpers -------------------------------------------------------------------
function Banner([string]$msg) {
    Write-Host "-- $msg --------------------------------------------------"
}

function Delete-Project([string]$id) {
    $exists = $false
    try {
        $null = gcloud projects describe $id 2>&1
        $exists = ($LASTEXITCODE -eq 0)
    } catch { $exists = $false }

    if ($exists) {
        Write-Host "  Deleting $id..."
        gcloud projects delete $id --quiet
        if ($LASTEXITCODE -ne 0) { throw "Failed to delete project $id" }
    } else {
        Write-Host "  [skip] $id not found (already deleted or never created)."
    }
}

# -- Cancel auto-destroy timer if still running --------------------------------
$TimerPidFile = Join-Path $RepoRoot ".autodestroy.pid"
if (Test-Path $TimerPidFile) {
    $oldPid = Get-Content $TimerPidFile -Raw
    $proc   = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  Cancelling auto-destroy timer (PID $oldPid)..."
        Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $TimerPidFile -Force
}

# -- Delete projects (admin -> webapp -> deployments) --------------------------
Banner "Deleting GCP projects"
Delete-Project $ProjectC
Delete-Project $ProjectB
Delete-Project $ProjectA
Write-Host ""

# -- Clean up local artifacts --------------------------------------------------
Banner "Cleaning up local state"

Write-Host "  Removing terraform.tfvars..."
Remove-Item $TfVars -Force

Get-ChildItem -Path (Join-Path $RepoRoot "labs") -Directory | ForEach-Object {
    $tfDir = Join-Path $_.FullName ".terraform"
    if (Test-Path $tfDir) {
        Write-Host "  Removing $tfDir"
        Remove-Item $tfDir -Recurse -Force
    }
}

Write-Host ""
Write-Host "===================================================================="
Write-Host "  Done. Projects are in GCP's 30-day soft-delete window."
Write-Host ""
Write-Host "  To start a fresh lab environment:"
Write-Host "    .\scripts\setup.ps1 -BillingAccount XXXXXX-XXXXXX-XXXXXX"
Write-Host "===================================================================="
