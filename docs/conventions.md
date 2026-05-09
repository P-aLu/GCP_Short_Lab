# Conventions

Naming, labelling, and Terraform style rules for this repository. Apply these consistently so the codebase stays predictable and diff-friendly.

---

## Naming

### GCP resource names

| Resource type | Pattern | Example |
|---------------|---------|---------|
| GCS bucket | `[uid]-<purpose>` | `a1b2c3d4-deployments` |
| Compute instance | `[uid]-<purpose>` | `a1b2c3d4-deployments-sql-compute` |
| Cloud SQL instance | `[uid]-<purpose>` | `a1b2c3d4-deployments-sql` |
| Cloud Function | `[uid]-<purpose>` | `a1b2c3d4-flag-api` |
| KMS key ring | `[uid]-<scope>` | `a1b2c3d4-webapp` |
| KMS crypto key | `[uid]-<scope>-kms` | `a1b2c3d4-webapp-kms` |
| Secret Manager secret | `[uid]-<purpose>` | `a1b2c3d4-webapp_config` |
| Service account `account_id` | `<role-slug>` (no uid) | `training-start`, `webapp-owner` |
| BigQuery dataset | `[uid]_<purpose>` (underscores — BQ disallows hyphens) | `a1b2c3d4_data` |
| VPC network | `[uid]-lab-network` | `a1b2c3d4-lab-network` |
| Subnet | `[uid]-lab-subnet` | `a1b2c3d4-lab-subnet` |
| Firewall rule | `[uid]-<what>` | `a1b2c3d4-allow-ssh` |
| Static IP address | `<instance-name>-ip` | `a1b2c3d4-deployments-sql-compute-ip` |

`[uid]` is always `random_id.deployment.hex` — a 4-byte (8 hex char) random prefix generated per deployment, making every apply globally unique.

### Terraform identifiers

- Use `snake_case` for all resource, variable, local, and output names.
- Use hyphens in GCP resource names (labels, IDs), underscores in Terraform identifiers.
- Match the Terraform resource name to the GCP resource purpose, not its type.
  - Good: `resource "google_compute_instance" "sql_compute"`
  - Avoid: `resource "google_compute_instance" "instance_1"`

---

## Labels

Every resource that supports labels must carry at minimum:

```hcl
labels = {
  env   = "lab"
  lab   = "lab-01-gsc-privesc"   # the lab folder name
  owner = var.owner
}
```

Define labels in a `locals` block at the top of `main.tf` and reference them everywhere:

```hcl
locals {
  labels = {
    env   = "lab"
    lab   = "lab-01-gsc-privesc"
    owner = var.owner
  }
}
```

BigQuery uses `user_labels` instead of `labels` in some resource blocks — use the correct attribute name for each resource type.

---

## Terraform style

### File layout

Each lab root contains exactly these files (plus `templates/` if needed):

```
main.tf        variables.tf   outputs.tf
backend.tf     providers.tf   README.md
```

Do not split resources across multiple `.tf` files within a lab root. Keep everything in `main.tf`, separated by labelled comment sections:

```hcl
# ── Locals ────────────────────────────────────────────────────────────────────
# ── Random values ─────────────────────────────────────────────────────────────
# ── Required APIs ─────────────────────────────────────────────────────────────
# ── <Resource group> ──────────────────────────────────────────────────────────
```

### Variables

- Required inputs have no default.
- Optional inputs (overrides and cross-lab wiring) have a documented default.
- Mark sensitive inputs with `sensitive = true`.
- Use `description` on every variable and output.

### Locals

Put all computed names, the labels map, and any derived values in a `locals` block at the top of `main.tf`. No string interpolation scattered through resource blocks.

### Lifecycle

All lab resources must include:

```hcl
lifecycle {
  prevent_destroy = false
}
```

This ensures `terraform destroy` is never blocked during a lab tear-down.

### Backend

State is stored locally in each lab directory (`terraform.tfstate`). The file is git-ignored � never commit it.

### Provider versions

Pin providers with `~>` (pessimistic constraint) at the minor version:

```hcl
google  = { source = "hashicorp/google",  version = "~> 5.0" }
random  = { source = "hashicorp/random",  version = "~> 3.6" }
tls     = { source = "hashicorp/tls",     version = "~> 4.0" }
archive = { source = "hashicorp/archive", version = "~> 2.4" }
```

### Comments

Only add a comment when the *why* is non-obvious — a hidden constraint, a deliberate vulnerability, or a workaround. Do not comment what the code already states.
