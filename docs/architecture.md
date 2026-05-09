# Architecture

This document describes how the repository is structured, how labs relate to modules, and the design decisions behind each.

---

## Repository structure

```
.
├── labs/          # One Terraform root per lab — independently deployable
├── modules/       # Reusable Terraform modules (extracted as labs share code)
├── docs/          # Design and reference documentation
├── scripts/       # lab.sh and all-labs.sh wrappers
└── terraform.tfvars.example
```

Labs are the primary unit of work. Each lab in `labs/lab-XX-*/` is a **self-contained Terraform root** that can be deployed and destroyed independently via `lab.sh`.

Modules under `modules/` are extracted only when two or more labs share a meaningful block of infrastructure. No module exists for a single lab's use.

---

## Lab anatomy

Every lab directory contains at minimum:

| File | Purpose |
|------|---------|
| `main.tf` | All resources, organised into labelled sections |
| `variables.tf` | Declared inputs (no defaults for required values) |
| `outputs.tf` | Useful values surfaced after `apply` |
| `backend.tf` | GCS remote-state backend (bucket injected by `lab.sh`) |
| `providers.tf` | Provider versions and configuration |
| `README.md` | Scenario description and kill chain for learners |
| `templates/` | Any `templatefile()` assets (startup scripts, etc.) |

---

## Lab 01 — GCP Privilege Escalation (`lab-01-gsc-privesc`)

### Project A resources

```
Project A  (var.project_id)
│
├── google_service_account.training_start     — learner's starting credential
│
├── (pre-existing) [uid]-deployments-palu     — shared bucket (state + lab files)
│   ├── noise: deployment-YYYY-MM-DD.log/txt  — 16 red-herring files
│   └── [uid]-deployment.tfstate              — planted state (SSH key + SQL creds)
│
├── google_compute_network.lab                — isolated VPC
├── google_compute_subnetwork.lab             — 10.10.0.0/24
├── google_compute_firewall.allow_ssh         — TCP/22 open to 0.0.0.0/0
│
├── google_compute_address.sql_compute        — static external IP
├── google_compute_instance.sql_compute       — [uid]-deployments-sql-compute
│   └── startup script: creates `Web APIs` table in Cloud SQL
│
└── google_sql_database_instance.main         — [uid]-deployments-sql (MYSQL_8_0)
    ├── google_sql_database.deployments       — schema: "deployments"
    └── google_sql_user.lab_user              — labuser (password in planted tfstate)
```

### Kill chain mapping to resources

| Stage | Resource(s) involved |
|-------|---------------------|
| 0 — Deploy | All of the above |
| 1 — Initial Access | `training_start` SA + `[uid]-deployments-palu` bucket IAM |
| 2 — tfstate Exfil | `planted_tfstate` object in GCS bucket |
| 3 — Lateral Movement | `sql_compute` instance + `tls_private_key.ssh` (from tfstate) |
| 4 — DB Access | `sql_database_instance.main` (authorised network = compute static IP) |
| 5 — Credential Harvest | `Web APIs` table row (inserted by startup script) |
| 6 — Final Flag | Cloud Function in Project B (`lab-01-gsc-privesc-b`) |

### Key design decisions

- **Static IP for compute** — avoids a chicken-and-egg cycle between `google_sql_database_instance` authorized networks and `google_compute_instance`. The static address is created first and referenced by both.
- **Planted tfstate as jsonencode local** — keeps sensitive values (private key, SQL password) as Terraform-managed strings, avoiding a separate template file that could drift.
- **db-f1-micro Cloud SQL** — cheapest available tier; adequate for a single-row table and a handful of connections during a lab session.
- **`require_ssl = false` on Cloud SQL** — simplifies the learner's `mysql` command at Stage 4; the authorized-network restriction provides the access control for this lab.
- **Startup script via `templatefile()`** — all SQL credentials are injected at plan time; no shell-level variable substitution needed.

---

## Lab 01-B — Cloud Function bridge (`lab-01-gsc-privesc-b`)

### Project B resources

```
Project B  (separate var.project_id)
│
├── google_service_account.cf_runtime         — function runtime SA (lab-02 pivot point)
│
├── google_storage_bucket.cf_source           — [uid]-cf-source (function zip upload)
│
└── google_cloudfunctions2_function.flag_api  — [uid]-flag-api (Gen 2, Python 3.11)
    ├── env: CF_API_USER / CF_API_PASSWORD     — credentials from Project A outputs
    ├── env: FLAG                              — stage 6 completion string
    ├── GET /?user=U&password=P               — returns flag (stage 6)
    └── GET /?...&cmd=<shell>                 — RCE endpoint (lab-02 entry point)
```

### Key design decisions

- **Separate project** — the Cloud Function lives in a different GCP project from Project A. The learner discovers the URL from the `Web APIs` table; there is no other link between the projects visible from Project A's credentials.
- **Application-level auth, not GCP auth** — the function is deployed with `allUsers` invoker so learners can reach it with a plain `curl`. The Python code validates `CF_API_USER`/`CF_API_PASSWORD` from the query string or JSON body.
- **Intentional RCE** — `?cmd=` calls `subprocess.run(..., shell=True)` with no sanitisation. This is deliberate: it is the attack surface for lab-02's metadata token steal.
- **Runtime SA as pivot** — `cf_runtime` SA email is an output. Lab-02's Terraform grants this SA the `kms_reader` custom role on the webapp project, making the metadata token useful when stolen.
- **Source zip keyed on MD5** — `google_storage_bucket_object.function_source` uses the archive MD5 in its name, so re-deploying after a code change always uploads a new object and triggers a function rebuild.

### Deployment order

Handled automatically by `deploy-chain.sh`. The dependency graph is:

```
lab-01-gsc-privesc (apply)
  └─ outputs: deployment_uid, cf_api_user, cf_api_password
       │
       ▼
lab-01-gsc-privesc-b (apply) — project: [uid]-webapp-palu
  └─ outputs: function_url, cf_runtime_sa_email
       │
       ├─▶ lab-01-gsc-privesc (re-apply) — seeds function_url into Web APIs table
       │
       └─▶ lab-02-kms-privesc (apply) — project: [uid]-webapp-palu
```

All cross-lab values are passed as `-var` flags by `deploy-chain.sh` — no per-lab `terraform.tfvars` editing is required.

---

## Lab 02 — KMS Privilege Escalation (`lab-02-kms-privesc`)

### Webapp project resources

```
Project C  (var.project_id = $DEPLOYMENT_UID-webapp-palu)
│
├── google_project_iam_custom_role.kms_reader        — list secrets, list+use KMS, get IAM policy
│   └── google_project_iam_member.cf_kms_reader      — granted to CF runtime SA from lab-01-b
│
├── google_service_account.webapp_owner              — Stage 5 target SA
│   ├── google_service_account_key.webapp_owner      — key encrypted + stored in Secret Manager
│   ├── roles/bigquery.dataViewer (project)
│   └── roles/bigquery.jobUser (project)
│
├── google_kms_key_ring.lab                          — [uid]-webapp
│   └── google_kms_crypto_key.webapp                 — [uid]-webapp-kms (ENCRYPT_DECRYPT)
│
├── google_kms_secret_ciphertext.webapp_owner_key    — KMS-encrypted webapp_owner SA key
│
├── google_secret_manager_secret.webapp_config       — [uid]-webapp_config
│   └── version: KMS ciphertext of webapp_owner SA key
│
├── google_service_account.projects_scanner          — Stage 7 credential (lab-03 pivot)
│   ├── google_service_account_key.projects_scanner  — key stored in BigQuery
│   └── roles/browser (project)
│
├── google_bigquery_dataset.lab                      — [uid]_data
│   ├── google_bigquery_table.metrics                — noise: metrics rows
│   ├── google_bigquery_table.events                 — noise: deployment events
│   └── google_bigquery_table.secret_bigquery        — hidden: projects_scanner SA key JSON
│
└── google_storage_bucket.bq_staging                 — [uid]-bq-staging (NDJSON data for load jobs)
```

### Kill chain mapping

| Stage | Resource(s) involved |
|-------|---------------------|
| 0 — Deploy | All of the above |
| 1 — RCE | lab-01-b Cloud Function `?cmd=` (no new resource) |
| 2 — Metadata Token | GCP metadata server inside CF runtime environment |
| 3 — Project Pivot | `cf_kms_reader` IAM binding + `kms_reader` custom role |
| 4 — KMS Decrypt | `webapp_config` secret + `webapp-kms` key |
| 5 — SA Key Harvest | `webapp_owner_key` ciphertext → decrypted SA key JSON |
| 6 — BigQuery Access | `webapp_owner` SA → `secret_bigquery` table |
| 7 — Final Pivot | `secret_key` row → `projects_scanner` SA → admin project (lab-03) |

### Key design decisions

- **KMS-encrypted secret, not plaintext** — the `webapp_config` secret stores the KMS ciphertext of the `webapp_owner` SA key. The learner needs both `secretmanager.versions.access` AND `cloudkms.cryptoKeyVersions.useToDecrypt` (both in `kms_reader`) to extract the SA key — two-step discovery rather than one.
- **SA key JSON in BigQuery as a STRING** — the `secret_bigquery` table has a single `secret_key` STRING column. This mirrors real-world incidents where credentials are accidentally written to data pipelines. The learner must recognise it, copy it, and use it as a credentials file.
- **NDJSON load via GCS staging** — inserting a PEM private key (multi-line, special chars) via a SQL INSERT would require complex escaping. A GCS load job handles it cleanly and is also realistic.
- **`projects_scanner` starts with only `roles/browser`** — lab-03 grants it access to the admin project. This defers the cross-project IAM binding until the admin project exists.

### Deployment order

Handled by `deploy-chain.sh` as step 4. Inputs (`project_id`, `deployment_uid`, `cf_runtime_sa_email`) are passed automatically. The `projects_scanner_sa_email` output is wired into lab-03.

---

## Lab 03 — Admin Project Takeover (`lab-03-admin-takeover`)

### Admin project resources

```
Project C  (var.project_id = $DEPLOYMENT_UID-admin-palu)
│
├── google_project_iam_custom_role.bucket_policy_manager  — list + setIAMPolicy on GCS (no object read)
│   └── google_project_iam_member.scanner_bucket_policy   — granted to projects_scanner SA from lab-02
│
├── google_service_account.admin_owner                    — Stage 2 target SA
│   └── roles/owner (project)
│
├── google_iam_deny_policy.block_api_enable               — denies admin-owner from serviceusage.services.enable
├── google_iam_deny_policy.flag_secret_guard              — denies all except admin-owner from SM versions.access
│
├── google_service_account.token_generator                — valid credential in the bucket (position 5 of 10)
│   ├── google_service_account_key.token_generator        — key stored in credentials bucket
│   ├── roles/iam.serviceAccountTokenCreator on admin-owner SA
│   └── custom role sa_lister on project
│
├── google_service_account.decoy[00..08]                  — 9 decoy SAs with real keys but no permissions
│   └── google_service_account_key.decoy[00..08]
│
├── google_storage_bucket.admin_creds                     — [uid]-admin-credentials
│   └── service-accounts.json                             — 10 SA keys (1 valid at position 5)
│
└── google_secret_manager_secret.flag                     — [uid]-admin-flag (API disabled post-deploy)
    └── version: flag string
```

### Kill chain mapping

| Stage | Resource(s) involved |
|-------|---------------------|
| 0 — Deploy | All of the above; `gcloud services disable secretmanager` run post-apply |
| 1 — Bucket IAM Abuse | `bucket_policy_manager` role → student grants self `objectViewer` → reads `service-accounts.json` |
| 2 — Token Generation | `token_generator` SA key → `iam.serviceAccounts.list` → `generateAccessToken` on `admin_owner` |
| 3 — IAM Binding | `admin_owner` token → `setIamPolicy` → grants student Gmail `roles/owner` |
| 4 — Enable SM API | Student logs into Console with Gmail account → enables `secretmanager.googleapis.com` |
| 5 — Final Flag | `admin_owner` token + SM API enabled → `secretmanager.versions.access` → flag |

### Key design decisions

- **IAM Deny Policies (google-beta)** — two deny policies enforce the two hard constraints: (1) `admin-owner` cannot enable APIs programmatically despite holding `roles/owner`; (2) no identity other than `admin-owner` SA can read the flag secret, even if granted `roles/owner` via `setIamPolicy`. Deny overrides Allow in GCP IAM evaluation.
- **`depends_on` ordering for destroy** — `flag_secret_guard` deny policy `depends_on` the secret version. Terraform destroy reverses this: deny policy is removed first, then the secret version is accessible for deletion.
- **`lifecycle { ignore_changes = [secret_data] }` on secret version** — after `flag_secret_guard` is applied, even the Terraform operator is denied `versions.access`. This prevents `terraform plan` from erroring on refresh. The secret data is set once at creation and never re-read by Terraform.
- **Secret Manager API disabled post-deploy** — `deploy-chain.sh` calls `gcloud services disable secretmanager.googleapis.com` after applying. This creates the Stage 3→4 puzzle: students must discover they can use `setIamPolicy` to grant personal access, then use the GCP Console to re-enable the API.
- **10 real SA keys, 9 decoys** — all keys authenticate successfully; decoy SAs have no permissions. Students must try each credential against `iam.serviceAccounts.list` to find the usable one. This mirrors real-world credential dumps.

### Deployment order

Handled by `deploy-chain.sh` as step 5. Inputs: `project_id` (admin project), `deployment_uid`, `projects_scanner_sa_email` (from lab-02 step 4 output).

Full dependency graph:

```
lab-01-gsc-privesc (apply)
  └─ outputs: deployment_uid, cf_api_user, cf_api_password
       │
       ▼
lab-01-gsc-privesc-b (apply) — project: [uid]-webapp-palu
  └─ outputs: function_url, cf_runtime_sa_email
       │
       ├─▶ lab-01-gsc-privesc (re-apply) — seeds function_url into Web APIs table
       │
       └─▶ lab-02-kms-privesc (apply) — project: [uid]-webapp-palu
             └─ output: projects_scanner_sa_email
                  │
                  ▼
             lab-03-admin-takeover (apply) — project: [uid]-admin-palu
               └─ post-apply: gcloud services disable secretmanager
```

---

## Module extraction plan

No modules exist yet. Extract a module when a second lab needs the same block. Candidates:

| Module | Extract when |
|--------|-------------|
| `modules/network/` | A second lab needs a custom VPC + subnet + firewall |
| `modules/iam/lab-sa/` | Multiple labs need the same SA + minimal-role pattern |
| `modules/gcs-lab-bucket/` | Multiple labs need a bucket with force_destroy + label defaults |
