output "deployment_uid" {
  description = "Shared deployment UID"
  value       = local.uid
}

output "admin_owner_sa_email" {
  description = "admin-owner SA email — the high-value target for Stage 2"
  value       = google_service_account.admin_owner.email
}

output "token_generator_sa_email" {
  description = "token-generator SA email — the valid credential hidden in the bucket (instructor reference)"
  value       = google_service_account.token_generator.email
  sensitive   = false
}

output "credentials_bucket" {
  description = "GCS bucket containing the credentials document with 10 SA keys"
  value       = google_storage_bucket.admin_creds.name
}

output "flag_secret_name" {
  description = "Secret Manager secret ID for the final flag"
  value       = google_secret_manager_secret.flag.secret_id
}

output "re_enable_sm_api_command" {
  description = "Command to re-enable Secret Manager API (for use in Stage 4 via GCP Console or with a personal account that has project owner)"
  value       = "gcloud services enable secretmanager.googleapis.com --project=${var.project_id}"
}

output "flag_access_command" {
  description = "Command to retrieve the flag once Secret Manager API is enabled and admin-owner token is active (Stage 5)"
  value       = "gcloud secrets versions access latest --secret=${local.flag_secret_name} --project=${var.project_id}"
}
