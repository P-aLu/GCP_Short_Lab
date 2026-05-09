# Deploy or destroy the full lab chain in the correct order, passing cross-lab
# outputs automatically as -var flags so no manual tfvars editing is needed.
#
# Usage:
#   .\scripts\deploy-chain.ps1 apply          - provision all labs
#   .\scripts\deploy-chain.ps1 apply -Org     - provision with IAM Deny Policies (requires GCP Org)
#   .\scripts\deploy-chain.ps1 destroy        - tear down all labs in reverse order
#   .\scripts\deploy-chain.ps1 destroy -Org   - destroy when deployed with -Org

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("apply","destroy")]
    [string]$Action,

    [switch]$Org
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$TfVars    = Join-Path $RepoRoot "terraform.tfvars"
$LabsDir   = Join-Path $RepoRoot "labs"

# -- Validate terraform.tfvars -------------------------------------------------
if (-not (Test-Path $TfVars)) {
    Write-Error "terraform.tfvars not found.`nCopy terraform.tfvars.example and fill in project_id, webapp_project_id, admin_project_id, region, zone, and owner."
}

# -- Read shared config from root tfvars ---------------------------------------
function Read-TfVar([string]$key) {
    $line = Select-String -Path $TfVars -Pattern "^${key}\s*=" | Select-Object -First 1
    if (-not $line) { return "" }
    if ($line.Line -match '=\s*"(.*)"') { return $Matches[1] }
    return ""
}

$ProjectA      = Read-TfVar "project_id"
$WebappProject = Read-TfVar "webapp_project_id"
$AdminProject  = Read-TfVar "admin_project_id"
$PresetUid     = Read-TfVar "deployment_uid"

if (-not $ProjectA)      { Write-Error "project_id not set in terraform.tfvars" }
if (-not $WebappProject) { Write-Error "webapp_project_id not set in terraform.tfvars" }
if (-not $AdminProject)  { Write-Error "admin_project_id not set in terraform.tfvars" }

# -- Helpers -------------------------------------------------------------------
function Banner([string]$msg) {
    Write-Host ""
    Write-Host "-- $msg --------------------------------------------------"
}

function TF-Init([string]$lab) {
    $labDir = Join-Path $LabsDir $lab
    Push-Location $labDir
    terraform init `
        -input=false -upgrade=false | Out-Null
    Pop-Location
}

function TF-Output([string]$lab, [string]$key) {
    TF-Init $lab
    $labDir = Join-Path $LabsDir $lab
    Push-Location $labDir
    $val = ""
    try {
        $val = terraform output -raw $key 2>&1
        if ($LASTEXITCODE -ne 0) { $val = "" }
    } catch { $val = "" }
    Pop-Location
    return $val
}

$TimerPidFile = Join-Path $RepoRoot ".autodestroy.pid"
$TimerLogFile = Join-Path $RepoRoot ".autodestroy.log"

# -- APPLY ---------------------------------------------------------------------
if ($Action -eq "apply") {

    Write-Host "==> deploy-chain: apply"
    Write-Host "    Deployments project  (A) : $ProjectA"
    Write-Host "    Webapp project       (B) : $WebappProject"
    Write-Host "    Admin project        (C) : $AdminProject"
    Write-Host ""

    # -- Step 1: deployments project ------------------------------------------
    Banner "1/5  lab-01-gsc-privesc - deployments project"
    Push-Location (Join-Path $LabsDir "lab-01-gsc-privesc")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform validate
    if ($PresetUid) {
        terraform apply -var-file="$TfVars" -var "deployment_uid=$PresetUid" -auto-approve
    } else {
        terraform apply -var-file="$TfVars" -auto-approve
    }
    $Uid            = terraform output -raw deployment_uid
    $CfApiUser      = terraform output -raw cf_api_user
    $CfApiPassword  = terraform output -raw cf_api_password
    $SaKeyCmd       = terraform output -raw sa_key_create_command
    Pop-Location
    Write-Host "    deployment_uid = $Uid"

    # -- Step 2: Cloud Function (webapp project) -------------------------------
    Banner "2/5  lab-01-gsc-privesc-b - Cloud Function"
    Push-Location (Join-Path $LabsDir "lab-01-gsc-privesc-b")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform validate
    terraform apply `
        -var-file="$TfVars" `
        -var "project_id=$WebappProject" `
        -var "deployment_uid=$Uid" `
        -var "cf_api_user=$CfApiUser" `
        -var "cf_api_password=$CfApiPassword" `
        -auto-approve
    $FunctionUrl   = terraform output -raw function_url
    $CfRuntimeSa   = terraform output -raw cf_runtime_sa_email
    Pop-Location
    Write-Host "    function_url     = $FunctionUrl"
    Write-Host "    cf_runtime_sa    = $CfRuntimeSa"

    # -- Step 3: seed Cloud Function URL back into the deployments project -----
    Banner "3/5  lab-01-gsc-privesc - seed function URL into Web APIs table"
    Push-Location (Join-Path $LabsDir "lab-01-gsc-privesc")
    terraform apply `
        -var-file="$TfVars" `
        -var "cf_function_url=$FunctionUrl" `
        -auto-approve
    Pop-Location

    # -- Step 4: webapp project resources (KMS, Secret Manager, BigQuery) ------
    Banner "4/5  lab-02-kms-privesc - KMS / Secret Manager / BigQuery"
    Push-Location (Join-Path $LabsDir "lab-02-kms-privesc")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform validate
    terraform apply `
        -var-file="$TfVars" `
        -var "project_id=$WebappProject" `
        -var "deployment_uid=$Uid" `
        -var "cf_runtime_sa_email=$CfRuntimeSa" `
        -auto-approve
    $ScannerSa = terraform output -raw projects_scanner_sa_email
    Pop-Location
    Write-Host "    projects_scanner_sa  = $ScannerSa"

    # -- Step 5: admin project -------------------------------------------------
    Banner "5/5  lab-03-admin-takeover - admin project"
    Push-Location (Join-Path $LabsDir "lab-03-admin-takeover")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform validate
    $Lab03Vars = @(
        "-var-file=$TfVars",
        "-var", "project_id=$AdminProject",
        "-var", "deployment_uid=$Uid",
        "-var", "projects_scanner_sa_email=$ScannerSa"
    )
    if ($Org) { $Lab03Vars += @("-var", "enable_deny_policies=true") }
    terraform apply @Lab03Vars -auto-approve
    Pop-Location

    # Post-apply: disable Secret Manager API && Service Usage API (Stage 4 puzzle)
    Write-Host ""
    Write-Host "    Disabling secretmanager.googleapis.com && serviceusage.googleapis.com in admin project (Stage 4 puzzle)..."
    try {
        gcloud services disable secretmanager.googleapis.com `
            --project=$AdminProject --quiet 2>&1 | Out-Null
        gcloud services disable cloudapis.googleapis.com `
            --project=$AdminProject --quiet 2>&1 | Out-Null
        gcloud services disable serviceusage.googleapis.com `
            --project=$AdminProject --quiet 2>&1 | Out-Null
    } catch { } # non-fatal

    # -- Auto-destroy timer ----------------------------------------------------
    # Cancel any previous timer.
    if (Test-Path $TimerPidFile) {
        $oldPid = Get-Content $TimerPidFile -Raw
        try { Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue } catch {}
        Remove-Item $TimerPidFile -Force
    }

    # Spawn a detached PowerShell process that destroys the chain after 2 hours.
    $destroyCmd = "Start-Sleep 7200; Set-Location '$RepoRoot'; & '$ScriptDir\deploy-chain.ps1' destroy"
    $timerProcess = Start-Process pwsh `
        -ArgumentList "-NonInteractive", "-Command", $destroyCmd `
        -RedirectStandardOutput $TimerLogFile `
        -RedirectStandardError  $TimerLogFile `
        -WindowStyle Hidden `
        -PassThru
    $timerProcess.Id | Set-Content $TimerPidFile

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "  Chain deployed successfully."
    Write-Host ""
    Write-Host "  Deployment UID : $Uid"
    Write-Host "  Projects       : $ProjectA | $WebappProject | $AdminProject"
    Write-Host "  Function URL   : $FunctionUrl"
    Write-Host ""
    Write-Host "  Generate the learner's starting SA key:"
    Write-Host "  $SaKeyCmd"
    Write-Host ""
    Write-Host "  Auto-destroy scheduled in 2 hours (PID $($timerProcess.Id))"
    Write-Host "     To cancel : Stop-Process $($timerProcess.Id); Remove-Item $TimerPidFile"
    Write-Host "     To destroy now : .\scripts\deploy-chain.ps1 destroy"
    Write-Host "     Timer log : $TimerLogFile"
    Write-Host "===================================================================="

# -- DESTROY -------------------------------------------------------------------
} elseif ($Action -eq "destroy") {

    Write-Host "==> deploy-chain: destroy (reverse order)"

    # Cancel the auto-destroy timer if it is still running.
    if (Test-Path $TimerPidFile) {
        $oldPid = Get-Content $TimerPidFile -Raw
        $proc   = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "    Cancelling auto-destroy timer (PID $oldPid)..."
            Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $TimerPidFile -Force
    }
    Write-Host ""

    # Collect outputs from existing state BEFORE any destroy call.
    Write-Host "    Reading state outputs..."
    $Uid           = TF-Output "lab-01-gsc-privesc"   "deployment_uid"
    $CfApiPassword = TF-Output "lab-01-gsc-privesc"   "cf_api_password"
    $CfRuntimeSa   = TF-Output "lab-01-gsc-privesc-b" "cf_runtime_sa_email"
    $ScannerSa     = TF-Output "lab-02-kms-privesc"   "projects_scanner_sa_email"

    # Pre-compute fallback values to avoid single-quote parse errors in -var strings
    $ScannerSaVar  = if ($ScannerSa)     { $ScannerSa }     else { 'placeholder@placeholder.iam.gserviceaccount.com' }
    $CfRuntimeSaVar = if ($CfRuntimeSa)  { $CfRuntimeSa }   else { 'placeholder@x.iam.gserviceaccount.com' }
    $CfApiPassVar  = if ($CfApiPassword) { $CfApiPassword }  else { 'placeholder' }

    if (-not $Uid) {
        Write-Error "Cannot read deployment_uid from lab-01-gsc-privesc state.`nHas the chain been deployed? Check: cd labs/lab-01-gsc-privesc && terraform output"
    }

    Write-Host "    deployment_uid = $Uid"
    Write-Host ""

    # -- Step 1: destroy admin project resources -------------------------------
    Banner "1/4  lab-03-admin-takeover"
    Push-Location (Join-Path $LabsDir "lab-03-admin-takeover")
    terraform init `
        -input=false -upgrade=false | Out-Null
    $Lab03Vars = @(
        "-var-file=$TfVars",
        "-var", "project_id=$AdminProject",
        "-var", "deployment_uid=$Uid",
        "-var", "projects_scanner_sa_email=$ScannerSaVar"
    )
    if ($Org) { $Lab03Vars += @("-var", "enable_deny_policies=true") }
    terraform destroy @Lab03Vars -auto-approve
    Pop-Location

    # -- Step 2: destroy webapp project resources ------------------------------
    Banner "2/4  lab-02-kms-privesc"
    Push-Location (Join-Path $LabsDir "lab-02-kms-privesc")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform destroy `
        -var-file="$TfVars" `
        -var "project_id=$WebappProject" `
        -var "deployment_uid=$Uid" `
        -var "cf_runtime_sa_email=$CfRuntimeSaVar" `
        -auto-approve
    Pop-Location

    # -- Step 3: destroy Cloud Function ---------------------------------------
    Banner "3/4  lab-01-gsc-privesc-b"
    Push-Location (Join-Path $LabsDir "lab-01-gsc-privesc-b")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform destroy `
        -var-file="$TfVars" `
        -var "project_id=$WebappProject" `
        -var "deployment_uid=$Uid" `
        -var "cf_api_user=placeholder" `
        -var "cf_api_password=$CfApiPassVar" `
        -auto-approve
    Pop-Location

    # -- Step 4: destroy deployments project ----------------------------------
    Banner "4/4  lab-01-gsc-privesc"
    Push-Location (Join-Path $LabsDir "lab-01-gsc-privesc")
    terraform init `
        -input=false -upgrade=false | Out-Null
    terraform destroy -var-file="$TfVars" -auto-approve
    Pop-Location

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "  Chain destroyed."
    Write-Host "  Note: KMS key rings remain in GCP (cannot be deleted) at no cost."
    Write-Host "===================================================================="
}