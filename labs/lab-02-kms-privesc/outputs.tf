output "deployment_uid" {
  description = "Unique deployment ID — prefix for all lab-02 resources"
  value       = local.uid
}

output "kms_keyring" {
  description = "KMS key ring name (region-scoped)"
  value       = google_kms_key_ring.lab.name
}

output "kms_key" {
  description = "KMS crypto key name — used by the learner to decrypt the secret"
  value       = google_kms_crypto_key.webapp.name
}

output "secret_name" {
  description = "Secret Manager secret ID containing the KMS-encrypted webapp_owner SA key"
  value       = google_secret_manager_secret.webapp_config.secret_id
}

output "bq_dataset" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.lab.dataset_id
}

output "webapp_owner_sa_email" {
  description = "webapp_owner SA email — activated by the learner after decrypting the secret"
  value       = google_service_account.webapp_owner.email
}

output "projects_scanner_sa_email" {
  description = "projects_scanner SA email — the identity behind the BigQuery credential. Grant this SA access to the admin project in lab-03."
  value       = google_service_account.projects_scanner.email
}

output "decrypt_hint" {
  description = "gcloud command to decrypt the webapp_config secret (run from within the Cloud Function via ?cmd= or after exfilling the KMS token)"
  value       = "gcloud secrets versions access latest --secret=${local.secret_name} --project=${var.project_id} | base64 -d > ct.bin && gcloud kms decrypt --location=${var.region} --keyring=${local.kms_keyring_name} --key=${local.kms_key_name} --ciphertext-file=ct.bin --plaintext-file=sa-key.json --project=${var.project_id}"
}
