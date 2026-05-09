# One-shot project bootstrap for the GCP lab chain.
#
# Generates a deployment UID, creates three GCP projects, links billing,
# enables all required APIs, creates the Terraform state bucket, and writes
# a ready-to-use terraform.tfvars so deploy-chain.ps1 can run immediately.
#
# Usage:
#   .\scripts\setup.ps1 -BillingAccount XXXXXX-XXXXXX-XXXXXX [options]
#
# Options:
#   -BillingAccount  (required) GCP billing account ID
#                    Find yours: gcloud billing accounts list
#   -Owner           Value for the 'owner' resource label
#                    (default: prefix of the active gcloud account)
#   -Region          GCP region  (default: europe-west1)
#   -Zone            GCP zone    (default: europe-west1-b)
#   -OrgId           Create projects under this GCP organization
#   -FolderId        Create projects under this GCP folder
#                    (If neither is given, projects are created at the
#                     account level — fine for personal GCP accounts)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BillingAccount,

    [string]$Owner   = "",
    [string]$Region  = "europe-west1",
    [string]$Zone    = "europe-west1-b",
    [string]$OrgId   = "",
    [string]$FolderId = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$TfVars    = Join-Path $RepoRoot "terraform.tfvars"

# -- Default owner --------------------------------------------------------------
if (-not $Owner) {
    $account = (gcloud config get-value account 2>$null).Trim()
    if ($account) {
        $Owner = ($account -split "@")[0] -replace '\.', '-'
    }
    if (-not $Owner) { $Owner = "lab-owner" }
}

# -- Generate UID ---------------------------------------------------------------
# 4 random bytes → 8 lowercase hex chars. GCP project IDs must start with a
# letter, so we force the first char to "a".
$rngBytes = [byte[]]::new(4)
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rngBytes)
$UidHex = "a" + (($rngBytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(1)

$StateBucket = "${UidHex}-deployments-palu"
$ProjectA    = "${UidHex}-deployments-palu"
$ProjectB    = "${UidHex}-webapp-palu"
$ProjectC    = "${UidHex}-admin-palu"

Write-Host "════════════════════════════════════════════════════════════════════"
Write-Host "  GCP Lab Setup"
Write-Host ""
Write-Host "  Deployment UID : $UidHex"
Write-Host "  Project A      : $ProjectA"
Write-Host "  Project B      : $ProjectB"
Write-Host "  Project C      : $ProjectC"
Write-Host "  State bucket   : gs://$StateBucket"
Write-Host "  Billing        : $BillingAccount"
Write-Host "  Region / Zone  : $Region / $Zone"
Write-Host "  Owner label    : $Owner"
Write-Host "════════════════════════════════════════════════════════════════════"
Write-Host ""

# -- Guard: don't silently overwrite an existing terraform.tfvars --------------
if (Test-Path $TfVars) {
    Write-Host "WARNING: terraform.tfvars already exists."
    $confirm = Read-Host "         Overwrite? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Aborted."
        exit 0
    }
    Write-Host ""
}

# -- Helpers -------------------------------------------------------------------
function Banner([string]$msg) {
    Write-Host "-- $msg --------------------------------------------------"
}

function Create-Project([string]$id, [string]$name) {
    $projectExists = $false
    try {
        $null = gcloud projects describe $id 2>&1
        $projectExists = ($LASTEXITCODE -eq 0)
    } catch { $projectExists = $false }

    if ($projectExists) {
        Write-Host "  [skip] $id already exists."
        return
    }
    Write-Host "  Creating $id..."
    $gcloudArgs = @($id, "--name=$name")
    if ($FolderId)  { $gcloudArgs += "--folder=$FolderId" }
    elseif ($OrgId) { $gcloudArgs += "--organization=$OrgId" }
    Write-Host "gcloud projects create ${@gcloudArgs}"
    gcloud projects create @gcloudArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to create project $id" }
}

function Link-Billing([string]$id) {
    Write-Host "  Linking billing to $id..."
    gcloud billing projects link $id --billing-account=$BillingAccount --quiet
    if ($LASTEXITCODE -ne 0) { throw "Failed to link billing to $id" }
}

function Enable-Apis([string]$id, [string[]]$apis) {
    Write-Host "  ${id}: enabling $($apis.Count) APIs..."
    gcloud services enable @apis --project=$id --quiet
    if ($LASTEXITCODE -ne 0) { throw "Failed to enable APIs on $id" }
}

# -- Step 1: Create projects ---------------------------------------------------
Banner "1/4  Create GCP projects"
Create-Project $ProjectA "Lab Deployments $UidHex"
Create-Project $ProjectB "Lab Webapp $UidHex"
Create-Project $ProjectC "Lab Admin $UidHex"
Write-Host ""

# -- Step 2: Link billing ------------------------------------------------------
Banner "2/4  Link billing"
Link-Billing $ProjectA
Link-Billing $ProjectB
Link-Billing $ProjectC
Write-Host ""

# -- Step 3: Enable APIs -------------------------------------------------------
Banner "3/4  Enable required APIs"

Enable-Apis $ProjectA @(
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "sqladmin.googleapis.com"
)

Enable-Apis $ProjectB @(
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
    "bigquery.googleapis.com"
)

Enable-Apis $ProjectC @(
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com"
)
Write-Host ""

# -- Step 4: Create Terraform state bucket ------------------------------------
Banner "4/4  Create Terraform state bucket"
$bucketExists = $false
try {
    $null = gcloud storage buckets describe "gs://$StateBucket" 2>&1
    $bucketExists = ($LASTEXITCODE -eq 0)
} catch { $bucketExists = $false }

if ($bucketExists) {
    Write-Host "  [skip] gs://$StateBucket already exists."
} else {
    Write-Host "  Creating gs://$StateBucket in $ProjectA..."
    gcloud storage buckets create "gs://$StateBucket" `
        --project=$ProjectA `
        --location=$Region `
        --uniform-bucket-level-access
    if ($LASTEXITCODE -ne 0) { throw "Failed to create state bucket" }
}
Write-Host ""

# -- Write terraform.tfvars ----------------------------------------------------
Banner "Writing terraform.tfvars"

@"
# Generated by scripts/setup.ps1 — do not commit this file.

# -- GCP projects --------------------------------------------------------------
project_id        = "$ProjectA"
webapp_project_id = "$ProjectB"
admin_project_id  = "$ProjectC"

# -- Shared settings -----------------------------------------------------------
region       = "$Region"
zone         = "$Zone"
state_bucket = "$StateBucket"
owner        = "$Owner"

# -- Pre-set deployment UID ----------------------------------------------------
# Generated by setup.ps1 and used by lab-01 instead of random_id.deployment,
# ensuring project names match the UID chosen above.
deployment_uid = "$UidHex"
"@ | Set-Content -Path $TfVars -Encoding UTF8

Write-Host "  Written: terraform.tfvars"
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════════"
Write-Host "  Setup complete. Deploy the full lab chain with:"
Write-Host ""
Write-Host "    .\scripts\deploy-chain.ps1 apply"
Write-Host ""
Write-Host "  Tear everything down with:"
Write-Host ""
Write-Host "    .\scripts\deploy-chain.ps1 destroy"
Write-Host "════════════════════════════════════════════════════════════════════"
