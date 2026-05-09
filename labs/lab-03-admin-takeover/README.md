DEPLOYMENT_UID = [random-uid]

## 3 - Admin Project Takeover

You land in `$DEPLOYMENT_UID-admin-palu` with the `projects_scanner` SA credentials found in the BigQuery table from lab-02.

This SA can list GCS buckets in the project and — more importantly — set their IAM policy. It cannot read objects. By exploiting the `setIamPolicy` permission, you can grant yourself object read access on the `$DEPLOYMENT_UID-admin-credentials` bucket.

Inside the bucket is a `service-accounts.json` file containing 10 service account credential exports. Nine of them authenticate successfully but have no useful permissions. One — `token-generator` — can list service accounts in the project and generate access tokens for them.

Activating each credential and attempting to list SAs reveals the valid one. From there you enumerate the project's service accounts and find `admin-owner@$DEPLOYMENT_UID-admin-palu`. Using the Token Creator binding, you generate an access token for it.

`admin-owner` holds `roles/resourcemanager.projectIamAdmin` on the project. This lets it call `setIamPolicy` — but it does **not** include `serviceusage.services.enable`, so `admin-owner` cannot enable the Secret Manager API programmatically. The Secret Manager API is disabled at the start of the exercise.

The intended path is to add an external identity (e.g. a personal Gmail account) to the project with `roles/owner`, then log into the GCP Console with that account to enable Secret Manager API through the UI.

> **Known bypass (non-org deployments):** Because `setIamPolicy` is unrestricted, a student could grant `roles/owner` directly to `admin-owner` itself, giving it `serviceusage.services.enable` and skipping the Console step. In deployments backed by a GCP Organization, this is prevented by passing `--org` to the deploy script, which enables a `flag_secret_guard` IAM Deny Policy ensuring only the original `admin-owner` token can read the flag regardless of how APIs were enabled.

Once the API is active, the flag is stored in secret `$DEPLOYMENT_UID-admin-flag`.

**With `--org`:** A `flag_secret_guard` IAM Deny Policy blocks all principals from `secretmanager.versions.access` except `admin-owner` SA — including the Gmail account granted project owner. The access token obtained for `admin-owner` is the only identity that can retrieve the flag.

**Without `--org`:** The flag is readable by any project owner (including the Gmail account). The kill chain still teaches IAM abuse, credential hunting, and token generation — Stage 5 enforcement is simply unguarded.
