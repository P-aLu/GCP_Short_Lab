# Lab Tracker

> **Status key**
> | Symbol | Meaning |
> |--------|---------|
> | `[ ]` | Not started |
> | `[~]` | In progress / under construction |
> | `[x]` | Done — only the repo owner may set this |

---

## Labs

| # | Folder | Title | Type | Status | Notes |
|---|--------|-------|------|--------|-------|
| 01-A | `lab-01-gsc-privesc` | GCP Privilege Escalation via Stolen SA Key — Project A | Security / CTF | `[~]` | Terraform complete; awaiting end-to-end test |
| 01-B | `lab-01-gsc-privesc-b` | GCP Privilege Escalation via Stolen SA Key — Project B (Cloud Function) | Security / CTF | `[~]` | Terraform complete; bridge to lab-02 |
| 02 | `lab-02-kms-privesc` | KMS Privilege Escalation via Metadata Token | Security / CTF | `[~]` | Terraform complete; awaiting end-to-end test |
| 03 | `lab-03-admin-takeover` | Admin Project Takeover via IAM Abuse | Security / CTF | `[~]` | Terraform complete; awaiting end-to-end test |

---

## Kill Chain — lab-01-gsc-privesc

The intended attack path for this lab:

1. `[~]` **Stage 0 — Deployment** — Terraform provisions Project A (SA, GCS bucket, compute, Cloud SQL) and Project B (Cloud Function)
2. `[ ]` **Stage 1 — Initial Access** — Learner receives stolen SA key; enumerates project buckets (`storage.buckets.list`) to discover `[uid]-deployments`, then lists objects inside it
3. `[ ]` **Stage 2 — tfstate Exfil** — Learner finds `$DEPLOYMENT_UID-deployment.tfstate` in the bucket containing SSH private key and resource topology
4. `[ ]` **Stage 3 — Lateral Movement** — Learner uses SSH key to access compute instance `[uid]-deployments-sql-compute`
5. `[ ]` **Stage 4 — DB Access** — Learner pivots from the compute instance to Cloud SQL instance `[uid]-deployments-sql` (only reachable from that compute instance)
6. `[ ]` **Stage 5 — Credential Harvest** — Learner reads `Web APIs` table: user, password, and URL for the Cloud Function in Project B
7. `[ ]` **Stage 6 — Final Flag** — Learner invokes the Cloud Function with harvested credentials and receives the flag

---

## Kill Chain — lab-02-kms-privesc

The intended attack path for this lab (continues from lab-01 Stage 6):

1. `[~]` **Stage 0 — Deployment** — Terraform provisions the webapp project (custom role, KMS key, Secret Manager, BigQuery)
2. `[ ]` **Stage 1 — RCE** — Learner exploits `?cmd=` on the lab-01 Cloud Function to execute shell commands
3. `[ ]` **Stage 2 — Metadata Token Steal** — Learner curls the GCP metadata server from within the function to get the runtime SA token
4. `[ ]` **Stage 3 — Project Pivot** — Token gives access to `[uid]-webapp-palu` project; learner lists IAM and discovers custom role `kms_reader`
5. `[ ]` **Stage 4 — KMS Decrypt** — Learner finds encrypted secret `[uid]-webapp_config` in Secret Manager; decrypts it with KMS key `[uid]-webapp-kms`
6. `[ ]` **Stage 5 — SA Key Harvest** — Decrypted secret contains a private key for `webapp_owner@[uid]-webapp-palu.iam.gserviceaccount.com`
7. `[ ]` **Stage 6 — BigQuery Access** — `webapp_owner` SA has reader rights; learner queries BigQuery and finds `secret-bigquery` table with a GCP auth credential
8. `[ ]` **Stage 7 — Final Pivot** — Credential lists multiple projects; learner identifies `[uid]-admin-palu` (lab-03 entry point)

---

---

## Kill Chain — lab-03-admin-takeover

The intended attack path for this lab (continues from lab-02 Stage 7):

1. `[~]` **Stage 0 — Deployment** — Terraform provisions the admin project (`[uid]-admin-palu`): credentials bucket, 10 SA keys (1 valid), admin-owner SA, IAM Deny Policies, flag secret. Secret Manager API disabled post-deploy.
2. `[ ]` **Stage 1 — Bucket IAM Abuse** — Learner has `storage.buckets.setIamPolicy` via `projects_scanner` but cannot read objects. Learner grants themselves `objectViewer`, reads `service-accounts.json` containing 10 SA keys.
3. `[ ]` **Stage 2 — Token Generation** — Learner activates each credential; only `token-generator` can list SAs and generate tokens. Learner generates an access token for `admin-owner` SA.
4. `[ ]` **Stage 3 — IAM Binding** — As `admin-owner` (project owner), learner cannot enable APIs (IAM Deny Policy blocks `serviceusage.services.enable`). Learner uses `setIamPolicy` to grant personal Gmail account `roles/owner`.
5. `[ ]` **Stage 4 — Enable Secret Manager API** — Learner logs into GCP Console with Gmail account and enables `secretmanager.googleapis.com`.
6. `[ ]` **Stage 5 — Final Flag** — Learner uses `admin-owner` SA token to read secret `[uid]-admin-flag`. Personal Gmail owner account is denied by a second IAM Deny Policy (`flag-secret-guard`). Only `admin-owner` SA token succeeds.

---

## Planned Labs (not started)

| # | Proposed Title | Type | Notes |
|---|---------------|------|-------|
| 04 | TBD | — | — |
