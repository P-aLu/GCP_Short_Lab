output "deployment_uid" {
  description = "Unique deployment ID — prefix for all lab resources"
  value       = local.uid
}

output "deployment_bucket" {
  description = "GCS bucket name — give this to the learner alongside the SA key"
  value       = google_storage_bucket.deployments.name
}

output "training_sa_email" {
  description = "Service account email to hand to the learner as their starting credential"
  value       = google_service_account.training_start.email
}

output "sa_key_create_command" {
  description = "gcloud command to generate the learner's starting SA key"
  value       = "gcloud iam service-accounts keys create sa-key.json --iam-account=${google_service_account.training_start.email} --project=${var.project_id}"
}

output "compute_instance_name" {
  description = "Compute instance name (Stage 3 target)"
  value       = google_compute_instance.sql_compute.name
}

output "compute_external_ip" {
  description = "Static external IP of the compute instance"
  value       = google_compute_address.sql_compute.address
}

output "sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "sql_public_ip" {
  description = "Cloud SQL public IP (Stage 4 target — only reachable from the compute instance)"
  value       = google_sql_database_instance.main.public_ip_address
}

# These two outputs feed directly into Project B variables.
output "cf_api_user" {
  description = "Cloud Function API username — use as input for Project B"
  value       = "cf-api-${local.uid}"
}

output "cf_api_password" {
  description = "Cloud Function API password — use as input for Project B"
  value       = random_password.cf_api.result
  sensitive   = true
}
