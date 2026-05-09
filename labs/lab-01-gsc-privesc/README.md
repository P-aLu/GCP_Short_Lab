DEPLOYMENT_UID = [random-uid]

## 1 - Initial Access

You have stolen a GCP service account key for `training-start@$DEPLOYMENT_UID-deployments-palu.iam.gserviceaccount.com`.

With this key you can:
- **Enumerate buckets** in the `$DEPLOYMENT_UID-deployments-palu` project (`storage.buckets.list`)
- **Get** and **list objects** inside any bucket you discover

Start by listing buckets to find the deployment bucket:
```bash
gcloud storage buckets list --project=$DEPLOYMENT_UID-deployments-palu
# or
gsutil ls -p $DEPLOYMENT_UID-deployments-palu
```

## 2 - Bucket Enumeration → tfstate Discovery

The deployment bucket `[random-uid]-deployments` contains many `deployment-[date].log` and `deployment-[date].txt` noise files, but also one `$DEPLOYMENT_UID-deployment.tfstate` file.

That tfstate contains:
- GCP `[random-uid]-deployments-sql-compute` compute instance with an **SSH private key** embedded
- Firewall rule: Cloud SQL `[random-uid]-deployments-sql` only accepts connections from the compute instance's static IP
- SQL credentials for `labuser` on `[random-uid]-deployments-sql`
- A `Web APIs` table entry: user, password, and URL for a Cloud Function in another project (see Stage 6)
