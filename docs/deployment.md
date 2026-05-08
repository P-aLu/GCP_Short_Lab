# Deployment Guide

This repo supports two deployment modes:

| Mode | When to use |
|------|-------------|
| **Single lab** | You want to practise one scenario without provisioning the rest |
| **Full environment** | You want every lab up at once (instructor setup, full walkthroughs) |

Both modes use the same `terraform.tfvars` file at the repo root and the same GCS remote-state bucket.

---

## Prerequisites

### 1 — Authenticate

```bash
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
```

### 2 — Create the remote-state bucket (once per project)

Each lab stores its Terraform state in a dedicated GCS bucket prefix.
Create a single bucket to hold all lab states:

```bash
gcloud storage buckets create gs://<YOUR_STATE_BUCKET> \
  --project=<PROJECT_ID> \
  --location=<REGION> \
  --uniform-bucket-level-access
```

### 3 — Populate `terraform.tfvars`

Copy the template and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Minimum required variables (defined in `terraform.tfvars.example`):

```hcl
project_id        = "<PROJECT_ID>"
region            = "europe-west1"
state_bucket      = "<YOUR_STATE_BUCKET>"
owner             = "<your-ldap-or-name>"
```

> `terraform.tfvars` is git-ignored. Never commit it.

---

## Mode 1 — Deploy a single lab

Use this when you want to spin up one lab in isolation.

### Deploy

```bash
cd labs/<lab-folder>
terraform init -backend-config="bucket=<YOUR_STATE_BUCKET>"
terraform validate
terraform plan  -var-file=../../terraform.tfvars
terraform apply -var-file=../../terraform.tfvars
```

### Destroy

```bash
cd labs/<lab-folder>
terraform destroy -var-file=../../terraform.tfvars
```

### Helper script (shorthand)

The script `scripts/lab.sh` wraps the above commands:

```bash
# Deploy
./scripts/lab.sh apply lab-01-gsc-privesc

# Tear down
./scripts/lab.sh destroy lab-01-gsc-privesc
```

`lab.sh` automatically passes `../../terraform.tfvars` and the correct
`-backend-config` so you never have to type them manually.

---

## Mode 2 — Deploy all labs at once

Use this to bring up the entire training environment in one command.

### Deploy all

```bash
./scripts/all-labs.sh apply
```

The script iterates every `labs/lab-*/` directory in lexicographic order
and runs `terraform init → validate → apply` for each one sequentially.
A lab that fails stops the run; already-applied labs are **not** rolled back
automatically — re-run with `apply` after fixing the issue to continue.

### Destroy all

```bash
./scripts/all-labs.sh destroy
```

Iterates in **reverse** order (last lab first) to respect any cross-lab
dependencies, running `terraform destroy` in each directory.

### Skipping a lab

```bash
SKIP_LABS="lab-02-foo lab-03-bar" ./scripts/all-labs.sh apply
```

Space-separated lab folder names — those directories are skipped entirely.

---

## State layout in GCS

Each lab writes its state to a separate prefix inside the shared bucket:

```
gs://<YOUR_STATE_BUCKET>/
  lab-01-gsc-privesc/terraform.tfstate
  lab-02-.../terraform.tfstate
  ...
```

This means labs are fully independent: destroying one lab never touches
another lab's state.

---

## Common failure modes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Error: Failed to get existing workspaces` | State bucket doesn't exist or wrong name | Create the bucket or check `state_bucket` in `terraform.tfvars` |
| `Error 403: Permission denied on GCS bucket` | ADC not set or SA lacks `storage.objectAdmin` | Re-run `gcloud auth application-default login` |
| `all-labs.sh` stops mid-run | A lab failed `validate` or `apply` | Fix the failing lab, then re-run `all-labs.sh apply` — already-applied labs will show no changes |
| Quota error on `apply` | GCP project quota too low | Check `gcloud compute project-info describe` and request quota increase or use a different region |

---

## Teardown checklist

Before finishing a session:

- [ ] Run `./scripts/all-labs.sh destroy` (or `lab.sh destroy <name>` for single)
- [ ] Confirm `terraform show` in each lab directory returns empty state
- [ ] Check the GCP console for any orphaned resources (billing > cost table)
