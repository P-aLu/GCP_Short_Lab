DEPLOYMENT_UID = [random-uid]

## 2 - KMS Privesc

The Cloudfunction is easy to compromise because it is a `?cmd={YOUR_CMD}` endpoint (and when you reach / without `cmd`, it helps you).

You can then steal the Meatdata access token that gives you access to `$DEPLOYMENT_UID-webapp-palu` project.

In this project you have the privileges to get IAM Policy and list roles. You see that a custom role `kms_reader` is set to you.

This role let you list secrets and KMS. Within secrets you can get a `$DEPLOYMENT_UID-webapp_config` secret, which is encrypted.

If you decrypt it with the key `$DEPLOYMENT_UID-webapp-kms` key, the you find a new private key for the user `webapp_owner@$DEPLOYMENT_UID-webapp-palu.serviceaccount.google.com`.

This account has `reader` rights over the project and can access big queries.

Among other (Random generation), there is a `secret-bigquery` with a `secret_key` within. First (and only) row is a GCP auth (project_id, private_key_id, private_key...) that can list several projects. Among projects, there is the third (and last) project `$DEPLOYMENT_UID-admin-palu` (check ## 3)
