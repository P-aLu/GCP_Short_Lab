# Cost Controls

All labs are designed to minimise cost. This document gives per-service estimates and rules for keeping bills low.

---

## Estimated cost while running

| Component | Lab | Service | Tier | Est. cost/day |
|-----------|-----|---------|------|--------------|
| Compute instance | 01-A | Cloud Compute | e2-micro | ~$0.05 (free in US regions) |
| Cloud SQL | 01-A | Cloud SQL MySQL | db-f1-micro | ~$0.24 |
| Static IP (idle) | 01-A | VPC | Regional | ~$0.01 |
| Cloud Function | 01-B | Cloud Functions Gen 2 | 256 MB, 0 min instances | ~$0.00 (free tier) |
| Cloud Run (backing CF) | 01-B | Cloud Run | — | ~$0.00 (scales to zero) |
| KMS key | 02 | Cloud KMS | Symmetric | ~$0.06/month → ~$0.002/day |
| Secret Manager | 02 | Secret Manager | 1 version | ~$0.06/month → ~$0.002/day |
| BigQuery storage | 02 | BigQuery | < 10 GB | ~$0.00 (free tier) |
| GCS buckets | all | Cloud Storage | Standard | ~$0.01 |
| Credentials bucket | 03 | Cloud Storage | Standard | ~$0.00 (< 1 KB object) |
| Secret Manager (flag) | 03 | Secret Manager | 1 version | ~$0.002/day (shared free tier with lab-02) |
| IAM Deny Policy | 03 | IAM (org only) | — | ~$0.00 (no per-resource charge) |

**Total (all three projects running): ~$0.30–$0.35/day** (or ~$0.25–$0.30/day in US regions where e2-micro is free)

> These are estimates for `europe-west1`. Actual costs depend on region, egress, and API call volume. Check the GCP billing console for real numbers.
> The 2-hour auto-destroy timer in `deploy-chain.sh apply` limits exposure to ~$0.07 per session if you walk away.

---

## Per-service rules

### Compute Engine

- Use `e2-micro` as the default. It is always-free in US regions (`us-central1`, `us-east1`, `us-west1`) and significantly cheaper than `e2-small` elsewhere. Only go larger when the lab explicitly requires it.
- Boot disk: `pd-standard` (standard persistent), 20 GB.
- Always attach a static external IP so it can be reserved and released cleanly.
- **Destroy after each session** — `deploy-chain.sh apply` spawns a 2-hour auto-destroy timer; rely on it as a safety net, not a substitute for explicit teardown.

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

- [ ] Run `./scripts/deploy-chain.sh destroy` (or the auto-destroy timer will do it within 2 hours)
- [ ] Confirm `terraform show` returns empty state for each lab
- [ ] Check GCP Billing console > Cost table — look for any `compute.googleapis.com` or `sqladmin.googleapis.com` charges after destroy
- [ ] KMS key rings will appear in the project but accrue no cost while unused — this is expected
