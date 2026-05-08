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
├── google_storage_bucket.deployments         — [uid]-deployments
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
| 1 — Initial Access | `training_start` SA + `deployments` bucket IAM |
| 2 — tfstate Exfil | `planted_tfstate` object in GCS bucket |
| 3 — Lateral Movement | `sql_compute` instance + `tls_private_key.ssh` (from tfstate) |
| 4 — DB Access | `sql_database_instance.main` (authorised network = compute static IP) |
| 5 — Credential Harvest | `Web APIs` table row (inserted by startup script) |
| 6 — Final Flag | Cloud Function in Project B (Project B not yet built) |

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

```
1. labs/lab-01-gsc-privesc   (apply)  → outputs: cf_api_user, cf_api_password
2. labs/lab-01-gsc-privesc-b (apply)  → inputs: cf_api_user, cf_api_password
                                        outputs: function_url, cf_runtime_sa_email
3. Set cf_function_url = <function_url> in terraform.tfvars
4. labs/lab-01-gsc-privesc   (apply)  → re-apply to seed correct URL into Web APIs table
5. labs/lab-02-kms-privesc   (apply)  → inputs: cf_runtime_sa_email (grants kms_reader)
```

---

## Module extraction plan

No modules exist yet. Extract a module when a second lab needs the same block. Candidates:

| Module | Extract when |
|--------|-------------|
| `modules/network/` | A second lab needs a custom VPC + subnet + firewall |
| `modules/iam/lab-sa/` | Multiple labs need the same SA + minimal-role pattern |
| `modules/gcs-lab-bucket/` | Multiple labs need a bucket with force_destroy + label defaults |
