# Import orphaned lab-03 resources into Terraform state.
# Run this once when a prior apply left resources in GCP outside Terraform state.
#
# Usage (from repo root):
#   .\scripts\import-lab03.ps1 -Uid a32552b0 -ScannerSa projects-scanner@<uid>-webapp-palu.iam.gserviceaccount.com

param(
    [Parameter(Mandatory = $true)]
    [string]$Uid,

    [Parameter(Mandatory = $true)]
    [string]$ScannerSa
)

$ErrorActionPreference = "Stop"

$AdminProject = "$Uid-admin-palu"
$LabDir       = Join-Path $PSScriptRoot "..\labs\lab-03-admin-takeover"

$CommonVars = @(
    "-var", "project_id=$AdminProject",
    "-var", "deployment_uid=$Uid",
    "-var", "projects_scanner_sa_email=$ScannerSa"
)

function TF-Import([string]$address, [string]$id) {
    Write-Host "  importing $address ..."
    terraform import @CommonVars $address $id
}

Push-Location $LabDir

Write-Host "==> Importing lab-03 orphaned resources into $AdminProject"

TF-Import "google_project_iam_custom_role.bucket_policy_manager" `
          "projects/$AdminProject/roles/bucket_policy_manager"

TF-Import "google_project_iam_custom_role.sa_lister" `
          "projects/$AdminProject/roles/sa_lister"

TF-Import "google_service_account.admin_owner" `
          "projects/$AdminProject/serviceAccounts/admin-owner@$AdminProject.iam.gserviceaccount.com"

TF-Import "google_service_account.token_generator" `
          "projects/$AdminProject/serviceAccounts/token-generator@$AdminProject.iam.gserviceaccount.com"

foreach ($i in 0..8) {
    $id = "{0:D2}" -f $i
    TF-Import "google_service_account.decoy[`"$id`"]" `
              "projects/$AdminProject/serviceAccounts/sa-decoy-$id@$AdminProject.iam.gserviceaccount.com"
}

TF-Import "google_storage_bucket.admin_creds" "$Uid-admin-credentials"

Write-Host ""
Write-Host "==> Import complete. Now fix the owner label value and run terraform apply."

Pop-Location
