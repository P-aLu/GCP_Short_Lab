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

---

## Kill Chain — lab-01-gsc-privesc

The intended attack path for this lab:

1. `[~]` **Stage 0 — Deployment** — Terraform provisions Project A (SA, GCS bucket, compute, Cloud SQL) and Project B (Cloud Function)
2. `[ ]` **Stage 1 — Initial Access** — Learner receives stolen SA key; can list/read GCS bucket `[uid]-deployments`
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

## Planned Labs (not started)

| # | Proposed Title | Type | Notes |
|---|---------------|------|-------|
| 03 | Admin project takeover via BigQuery credential | Security / CTF | Entry point: GCP auth from lab-02 Stage 7 |
