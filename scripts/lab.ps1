# Usage: .\scripts\lab.ps1 <apply|destroy|plan|validate> <lab-folder-name>
# Example: .\scripts\lab.ps1 apply lab-01-gsc-privesc

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("apply","destroy","plan","validate")]
    [string]$Action,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Lab
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$TfVars    = Join-Path $RepoRoot "terraform.tfvars"
$LabsDir   = Join-Path $RepoRoot "labs"
$LabDir    = Join-Path $LabsDir $Lab

# ── Validation ────────────────────────────────────────────────────────────────
if (-not (Test-Path $LabDir -PathType Container)) {
    Write-Error "Lab directory not found: $LabDir"
}

if (-not (Test-Path $TfVars)) {
    Write-Error "terraform.tfvars not found at $TfVars`nCopy terraform.tfvars.example and fill in your values."
}


# ── Build -var-file chain ─────────────────────────────────────────────────────
# Root tfvars holds common variables (region, zone, owner).
# A per-lab terraform.tfvars in the lab directory overrides or extends those.
$VarFileArgs = @("-var-file=$TfVars")
$LabTfVars   = Join-Path $LabDir "terraform.tfvars"
if (Test-Path $LabTfVars) {
    $VarFileArgs += "-var-file=$LabTfVars"
    Write-Host "==> Using per-lab tfvars: $LabTfVars"
}

# ── Run ───────────────────────────────────────────────────────────────────────
Write-Host "==> Lab   : $Lab"
Write-Host "==> Action: $Action"
Write-Host ""

Push-Location $LabDir

terraform init `
    -input=false

switch ($Action) {
    "validate" {
        terraform validate
    }
    "plan" {
        terraform validate
        terraform plan @VarFileArgs
    }
    "apply" {
        terraform validate
        terraform plan  @VarFileArgs
        terraform apply @VarFileArgs -auto-approve
    }
    "destroy" {
        terraform destroy @VarFileArgs -auto-approve
    }
}

Pop-Location
