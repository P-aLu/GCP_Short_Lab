DEPLOYMENT_UID = [random-uid]

## 1 - Initial Access

You have stolen a GCP service account key for `training-start@$DEPLOYMENT_UID-deployments-palu.iam.gserviceaccount.com`.

With this key you can:
- **Enumerate buckets** in the `$DEPLOYMENT_UID-deployments-palu` project (`storage.buckets.list`)
- **Get** and **list objects** inside any bucket you discover
- **Enumerate compute instances, Cloud SQL, networks, and firewall rules** (custom `labEnvReader` role — list/describe on SQL, list-only on compute instances)
- Note: `gcloud compute instances describe` is blocked — instance metadata is not readable from this SA

Start by mapping the environment:
```bash
# List all compute instances (name, IP, zone — no metadata)
gcloud compute instances list --project=$DEPLOYMENT_UID-deployments-palu

# List all Cloud SQL instances
gcloud sql instances list --project=$DEPLOYMENT_UID-deployments-palu

# List buckets
gcloud storage buckets list --project=$DEPLOYMENT_UID-deployments-palu
```

## 2 - Bucket Enumeration → tfstate Discovery

The deployment bucket `[random-uid]-deployments` contains many `deployment-[date].log` and `deployment-[date].txt` noise files, but also one `$DEPLOYMENT_UID-deployment.tfstate` file.

That tfstate contains:
- GCP `[random-uid]-deployments-sql-compute` compute instance with an **SSH private key** embedded
- Firewall rule: Cloud SQL `[random-uid]-deployments-sql` only accepts connections from the compute instance's static IP
- SQL credentials for `labuser` on `[random-uid]-deployments-sql`
- A `Web APIs` table entry: user, password, and URL for a Cloud Function in another project (see Stage 6)
