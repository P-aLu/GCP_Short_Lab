DEPLOYMENT_UID = [random-uid]

## 3 - Admin Project Takeover

You land in `$DEPLOYMENT_UID-admin-palu` with the `projects_scanner` SA credentials found in the BigQuery table from lab-02.

This SA can list GCS buckets in the project and — more importantly — set their IAM policy. It cannot read objects. By exploiting the `setIamPolicy` permission, you can grant yourself object read access on the `$DEPLOYMENT_UID-admin-credentials` bucket.

Inside the bucket is a `service-accounts.json` file containing 10 service account credential exports. Nine of them authenticate successfully but have no useful permissions. One — `token-generator` — can list service accounts in the project and generate access tokens for them.

Activating each credential and attempting to list SAs reveals the valid one. From there you enumerate the project's service accounts and find `admin-owner@$DEPLOYMENT_UID-admin-palu`. Using the Token Creator binding, you generate an access token for it.

`admin-owner` holds `roles/owner` on the project but is subject to an IAM Deny Policy that blocks `serviceusage.services.enable`. This means it cannot enable the Secret Manager API programmatically, despite technically being a project owner. The Secret Manager API is disabled at the start of the exercise.

Since `setIamPolicy` is not denied, `admin-owner` can add an external identity (e.g. a personal Gmail account) to the project with `roles/owner`. Logging into the GCP Console with that account allows enabling Secret Manager API through the UI.

Once the API is active, the flag is stored in secret `$DEPLOYMENT_UID-admin-flag`. A second IAM Deny Policy (`flag-secret-guard`) blocks all principals from `secretmanager.versions.access` except `admin-owner` SA — including the Gmail account just granted project owner. The access token obtained earlier for `admin-owner` is the only identity that can retrieve the flag.
