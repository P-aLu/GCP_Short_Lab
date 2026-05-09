# Deployment Guide

---

## Prerequisites

### 1 — Authenticate

```bash
gcloud auth application-default login
```

Your active account needs:
- `roles/resourcemanager.projectCreator` at the organization or folder level (or in the account root for personal GCP accounts)
- `roles/billing.user` on the billing account
- `roles/storage.admin` to create the state bucket

### 2 — Set up projects and variables

Choose **one** of the two options below. Option A is recommended.

---

#### Option A — Fully automated (recommended)

`scripts/setup.sh` / `scripts/setup.ps1` generates a deployment UID, creates all three GCP projects, links billing, enables required APIs, creates the Terraform state bucket, and writes `terraform.tfvars` — all in one command.

**Bash (Linux / macOS / WSL)**
```bash
./scripts/setup.sh --billing-account=XXXXXX-XXXXXX-XXXXXX
```

**PowerShell (Windows)**
```powershell
.\scripts\setup.ps1 -BillingAccount XXXXXX-XXXXXX-XXXXXX
```

Optional flags / parameters:

| Bash flag | PowerShell parameter | Default |
|-----------|---------------------|---------|
| `--owner=NAME` | `-Owner NAME` | prefix of the active gcloud account |
| `--region=REGION` | `-Region REGION` | `europe-west1` |
| `--zone=ZONE` | `-Zone ZONE` | `europe-west1-b` |
| `--org-id=ID` | `-OrgId ID` | _(none — account-level)_ |
| `--folder-id=ID` | `-FolderId ID` | _(none — account-level)_ |

Find your billing account ID:
```bash
gcloud billing accounts list
```

Once setup completes, `terraform.tfvars` is ready and you can jump straight to the deploy-chain script.

---

#### Option B — Manual project setup

Create the three projects in the GCP console. Projects follow the naming convention `[uid]-<name>-palu`, where `[uid]` is a shared 8-character hex string. Choose a fixed UID upfront so project names are consistent.

| Variable in tfvars | Project role |
|--------------------|-------------|
| `project_id` | `[uid]-deployments-palu` — deployments bucket, compute, Cloud SQL |
| `webapp_project_id` | `[uid]-webapp-palu` — Cloud Function, KMS, Secret Manager, BigQuery |
| `admin_project_id` | `[uid]-admin-palu` — IAM Deny Policies, credentials bucket, flag secret |

Create the Terraform state bucket (separate from the lab scenario bucket):

```bash
gcloud storage buckets create gs://<YOUR_STATE_BUCKET> \
  --location=europe-west1 \
  --uniform-bucket-level-access
```

Copy and fill in `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

```hcl
project_id        = "<DEPLOYMENTS_PROJECT_ID>"   # [uid]-deployments-palu
webapp_project_id = "<WEBAPP_PROJECT_ID>"         # [uid]-webapp-palu
admin_project_id  = "<ADMIN_PROJECT_ID>"          # [uid]-admin-palu
region            = "europe-west1"
zone              = "europe-west1-b"
state_bucket      = "<YOUR_STATE_BUCKET>"
owner             = "<your-name>"
deployment_uid    = "<your-chosen-uid>"           # 8 hex chars
```

---

## Automated deployment — `deploy-chain` (recommended)

`deploy-chain.sh` / `deploy-chain.ps1` runs all five deployment steps in order, capturing outputs and passing them between labs automatically. No manual editing of per-lab tfvars is needed.

### Deploy the full chain

**Bash**
```bash
./scripts/deploy-chain.sh apply
```

**PowerShell**
```powershell
.\scripts\deploy-chain.ps1 apply
```

This runs five steps internally:
1. Apply `lab-01-gsc-privesc` → captures `deployment_uid`, `cf_api_user`, `cf_api_password`
2. Apply `lab-01-gsc-privesc-b` with those values → captures `function_url`, `cf_runtime_sa_email`
3. Re-apply `lab-01-gsc-privesc` with `cf_function_url` → seeds the real URL into the `Web APIs` MySQL table
4. Apply `lab-02-kms-privesc` with `cf_runtime_sa_email` → captures `projects_scanner_sa_email`
5. Apply `lab-03-admin-takeover` with `projects_scanner_sa_email`; disables `secretmanager.googleapis.com` post-apply (Stage 4 puzzle)

On completion the script prints the deployment UID, Cloud Function URL, and the `gcloud` command to generate the learner's starting SA key. An auto-destroy timer fires after 2 hours to prevent runaway costs.

### Destroy the full chain

**Bash**
```bash
./scripts/deploy-chain.sh destroy
```

**PowerShell**
```powershell
.\scripts\deploy-chain.ps1 destroy
```

Destroys in reverse order (lab-03 → lab-02 → lab-01-b → lab-01), reading the UID and cross-lab SA emails from existing state before any destroy runs.

---

## Manual deployment — `lab` (single lab or debugging)

Use `lab.sh` / `lab.ps1` when you need to re-deploy a single lab, run a plan, or debug a specific step.

**Bash**
```bash
./scripts/lab.sh <apply|destroy|plan|validate> <lab-folder>
```

**PowerShell**
```powershell
.\scripts\lab.ps1 <apply|destroy|plan|validate> <lab-folder>
```

The script loads:
1. The root `terraform.tfvars` (common variables)
2. A per-lab `terraform.tfvars` in the lab directory (if it exists — used to override `project_id`, `deployment_uid`, and cross-lab inputs)

### Manual step-by-step chain deployment

If you prefer full control over each step:

**Step 1 — Deploy lab-01-gsc-privesc**

Bash:
```bash
./scripts/lab.sh apply lab-01-gsc-privesc
cd labs/lab-01-gsc-privesc
terraform output deployment_uid       # note this
terraform output cf_api_user
terraform output -raw cf_api_password # sensitive
cd ../..
```
PowerShell:
```powershell
.\scripts\lab.ps1 apply lab-01-gsc-privesc
Set-Location labs\lab-01-gsc-privesc
terraform output deployment_uid
terraform output cf_api_user
terraform output -raw cf_api_password
Set-Location ..\..
```

**Step 2 — Deploy lab-01-gsc-privesc-b**

Bash:
```bash
cp labs/lab-01-gsc-privesc-b/terraform.tfvars.example \
   labs/lab-01-gsc-privesc-b/terraform.tfvars
# Edit: set project_id, deployment_uid, cf_api_user, cf_api_password
./scripts/lab.sh apply lab-01-gsc-privesc-b
cd labs/lab-01-gsc-privesc-b && terraform output function_url && cd ../..
```
PowerShell:
```powershell
Copy-Item labs\lab-01-gsc-privesc-b\terraform.tfvars.example `
          labs\lab-01-gsc-privesc-b\terraform.tfvars
# Edit: set project_id, deployment_uid, cf_api_user, cf_api_password
.\scripts\lab.ps1 apply lab-01-gsc-privesc-b
Set-Location labs\lab-01-gsc-privesc-b; terraform output function_url; Set-Location ..\..
```

**Step 3 — Seed the function URL into lab-01**

Bash:
```bash
# Add cf_function_url = "<url>" to root terraform.tfvars
./scripts/lab.sh apply lab-01-gsc-privesc
```
PowerShell:
```powershell
# Add cf_function_url = "<url>" to root terraform.tfvars
.\scripts\lab.ps1 apply lab-01-gsc-privesc
```

**Step 4 — Deploy lab-02-kms-privesc**

Bash:
```bash
cp labs/lab-02-kms-privesc/terraform.tfvars.example \
   labs/lab-02-kms-privesc/terraform.tfvars
# Edit: set project_id (same webapp project), deployment_uid, cf_runtime_sa_email
./scripts/lab.sh apply lab-02-kms-privesc
cd labs/lab-02-kms-privesc && terraform output projects_scanner_sa_email && cd ../..
```
PowerShell:
```powershell
Copy-Item labs\lab-02-kms-privesc\terraform.tfvars.example `
          labs\lab-02-kms-privesc\terraform.tfvars
# Edit: set project_id (same webapp project), deployment_uid, cf_runtime_sa_email
.\scripts\lab.ps1 apply lab-02-kms-privesc
Set-Location labs\lab-02-kms-privesc; terraform output projects_scanner_sa_email; Set-Location ..\..
```

**Step 5 — Deploy lab-03-admin-takeover**

Bash:
```bash
cp labs/lab-03-admin-takeover/terraform.tfvars.example \
   labs/lab-03-admin-takeover/terraform.tfvars
# Edit: set project_id (admin project), deployment_uid, projects_scanner_sa_email
./scripts/lab.sh apply lab-03-admin-takeover

# Post-apply: disable Secret Manager API (Stage 4 puzzle)
gcloud services disable secretmanager.googleapis.com \
  --project=<ADMIN_PROJECT_ID> --quiet
```
PowerShell:
```powershell
Copy-Item labs\lab-03-admin-takeover\terraform.tfvars.example `
          labs\lab-03-admin-takeover\terraform.tfvars
# Edit: set project_id (admin project), deployment_uid, projects_scanner_sa_email
.\scripts\lab.ps1 apply lab-03-admin-takeover

# Post-apply: disable Secret Manager API (Stage 4 puzzle)
gcloud services disable secretmanager.googleapis.com `
  --project=<ADMIN_PROJECT_ID> --quiet
```

---

## Teardown

### Automated (recommended)

Bash:
```bash
./scripts/deploy-chain.sh destroy
```
PowerShell:
```powershell
.\scripts\deploy-chain.ps1 destroy
```

### Manual (reverse order)

Bash:
```bash
./scripts/lab.sh destroy lab-03-admin-takeover
./scripts/lab.sh destroy lab-02-kms-privesc
./scripts/lab.sh destroy lab-01-gsc-privesc-b
./scripts/lab.sh destroy lab-01-gsc-privesc
```
PowerShell:
```powershell
.\scripts\lab.ps1 destroy lab-03-admin-takeover
.\scripts\lab.ps1 destroy lab-02-kms-privesc
.\scripts\lab.ps1 destroy lab-01-gsc-privesc-b
.\scripts\lab.ps1 destroy lab-01-gsc-privesc
```

> Always destroy in **reverse order** — IAM Deny Policies in lab-03 and cross-project bindings in lab-02 must be removed before their dependency SAs are destroyed.

### Teardown checklist

- [ ] All destroy commands completed without error
- [ ] `terraform show` returns empty state in each lab directory
- [ ] Check GCP billing console for any orphaned resources
- [ ] KMS key rings cannot be deleted from GCP — they remain in the project permanently at no cost. This is expected.
- [ ] If Secret Manager API was disabled in the admin project, re-enable it before destroying: `gcloud services enable secretmanager.googleapis.com --project=<ADMIN_PROJECT_ID>` — otherwise the secret version destroy will fail.

---

## State layout in GCS

```
gs://<STATE_BUCKET>/
  lab-01-gsc-privesc/terraform.tfstate
  lab-01-gsc-privesc-b/terraform.tfstate
  lab-02-kms-privesc/terraform.tfstate
  lab-03-admin-takeover/terraform.tfstate
```

---

## Common failure modes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `webapp_project_id not set` | Missing from `terraform.tfvars` | Add it — see `terraform.tfvars.example` or re-run `setup.sh` |
| `admin_project_id not set` | Missing from `terraform.tfvars` | Add it — see `terraform.tfvars.example` or re-run `setup.sh` |
| `Project already exists` during `setup.sh` | Project ID collision | `setup.sh` skips existing projects; safe to re-run |
| Project names don't match UID after apply | `deployment_uid` not set in tfvars | Add `deployment_uid = "<uid>"` to `terraform.tfvars` matching your project names |
| `deployment_uid not set` | Per-lab tfvars missing `deployment_uid` | Copy from `lab-01-gsc-privesc` output `deployment_uid` |
| `Cannot read deployment_uid from state` on destroy | Chain was never fully applied | Run `apply` first, or destroy labs manually with `lab.sh` |
| `Error 403: Permission denied` | ADC not set or missing roles on a project | Re-run `gcloud auth application-default login`; see [`gcp-auth.md`](gcp-auth.md) |
| Cloud SQL apply takes 10+ min | Normal — Cloud SQL provisioning is slow | Wait; do not interrupt |
| `google_kms_key_ring already exists` | Key ring from a prior deployment persists in GCP (key rings are permanent) | `terraform state rm google_kms_key_ring.lab` in lab-02, then re-apply |
| `Error accessing secret version` during destroy | Secret Manager API was disabled post-apply | Re-enable it first: `gcloud services enable secretmanager.googleapis.com --project=<ADMIN_PROJECT_ID>` |
| `IAM Deny Policy` blocks secret access | By design — `flag_secret_guard` deny policy denies all except `admin-owner` SA | Use `admin-owner` SA token to access the secret, not personal credentials |
| `all-labs.sh` / `all-labs.ps1` stops mid-run | A lab failed | Use `deploy-chain` instead — `all-labs` does not wire cross-lab outputs |
