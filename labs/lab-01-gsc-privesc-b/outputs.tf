output "function_url" {
  description = "Cloud Function HTTPS URL — set this as cf_function_url in lab-01-gsc-privesc terraform.tfvars"
  value       = google_cloudfunctions2_function.flag_api.service_config[0].uri
}

output "function_name" {
  description = "Cloud Function resource name"
  value       = google_cloudfunctions2_function.flag_api.name
}

output "cf_runtime_sa_email" {
  description = "Cloud Function runtime SA — grant this email the kms_reader custom role in lab-02's webapp project"
  value       = google_service_account.cf_runtime.email
}

output "test_command" {
  description = "curl command to verify the function is reachable (replace USER and PASS with Project A outputs)"
  value       = "curl -s '${google_cloudfunctions2_function.flag_api.service_config[0].uri}?user=${var.cf_api_user}&password=<CF_API_PASSWORD>'"
}
