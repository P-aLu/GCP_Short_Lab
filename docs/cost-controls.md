# Cost Controls

All labs are designed to minimise cost. This document gives per-service estimates and rules for keeping bills low.

---

## Estimated cost while running

| Component | Lab | Service | Tier | Est. cost/day |
|-----------|-----|---------|------|--------------|
| Compute instance | 01-A | Cloud Compute | e2-small | ~$0.14 |
| Cloud SQL | 01-A | Cloud SQL MySQL | db-f1-micro | ~$0.24 |
| Static IP (idle) | 01-A | VPC | Regional | ~$0.01 |
| Cloud Function | 01-B | Cloud Functions Gen 2 | 256 MB, 0 min instances | ~$0.00 (free tier) |
| Cloud Run (backing CF) | 01-B | Cloud Run | — | ~$0.00 (scales to zero) |
| KMS key | 02 | Cloud KMS | Symmetric | ~$0.06/month → ~$0.002/day |
| Secret Manager | 02 | Secret Manager | 1 version | ~$0.06/month → ~$0.002/day |
| BigQuery storage | 02 | BigQuery | < 10 GB | ~$0.00 (free tier) |
| GCS buckets | all | Cloud Storage | Standard | ~$0.01 |

**Total (all three projects running): ~$0.40–$0.50/day**

> These are estimates for `europe-west1`. Actual costs depend on region, egress, and API call volume. Check the GCP billing console for real numbers.

---

## Per-service rules

### Compute Engine

- Use `e2-small` as the default. Only use a larger type when the lab explicitly requires it (e.g. a lab about machine types).
- Boot disk: `pd-standard` (standard persistent), 20 GB.
- Always attach a static external IP so it can be reserved and released cleanly.
- **Destroy after each session** — compute instances accrue cost even when idle.

### Cloud SQL

- Use `db-f1-micro` (or `db-g1-small` if f1-micro is unavailable in the region). These are the cheapest shared-CPU tiers.
- Set `backup_configuration { enabled = false }` — automated backups are not needed for ephemeral lab databases.
- Set `deletion_protection = false` so `terraform destroy` can remove the instance without manual intervention.
- **Destroy after each session** — Cloud SQL instances are the largest cost driver in this repo.

### Cloud Functions (Gen 2)

- Set `min_instance_count = 0` so the function scales to zero when not in use.
- Set `max_instance_count = 1` to prevent runaway scaling during a lab.
- Memory: `256M` is sufficient for the Python handlers used here.
- Cloud Functions Gen 2 backs onto Cloud Run — no additional Cloud Run cost beyond what the function incurs.

### Cloud KMS

- Cost is per key version per month ($0.06) plus per cryptographic operation ($0.03 per 10,000).
- Lab usage is negligible — typically 1–2 encrypt/decrypt operations per lab run.
- KMS key rings **cannot be deleted from GCP** (they remain at no cost). Keys are scheduled for deletion on `terraform destroy` but the ring persists.

### Secret Manager

- Cost is per secret version per month ($0.06) plus per API access call ($0.03 per 10,000).
- Lab usage is a few accesses per session — well within the free tier ($0 for first 6 active secret versions per month).

### BigQuery

- Storage: first 10 GB/month is free. Lab tables are kilobytes.
- Queries: first 1 TB/month is free. Lab queries scan a few KB.
- No cost controls needed beyond not creating large datasets.

### GCS buckets

- All buckets use `Standard` storage class. `force_destroy = true` ensures they are emptied and deleted on `terraform destroy`.
- Cost is negligible for the small objects used in these labs.

### Static IP addresses

- A reserved regional IP address that is **not attached to a resource** costs ~$0.01/hour.
- Lab static IPs are always attached to a compute instance during lab sessions. They are released (deleted) with `terraform destroy`.

---

## Cost hygiene checklist

Before ending a lab session:

- [ ] Run `./scripts/all-labs.sh destroy` or `lab.sh destroy` for each lab
- [ ] Confirm `terraform show` returns empty state for each lab
- [ ] Check GCP Billing console > Cost table — look for any `compute.googleapis.com` or `sqladmin.googleapis.com` charges after destroy
- [ ] KMS key rings will appear in the project but accrue no cost while unused — this is expected
