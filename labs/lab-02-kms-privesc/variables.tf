variable "project_id" {
  description = "GCP project ID for the webapp project (this is the $DEPLOYMENT_UID-webapp-palu project)"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west1"
}

variable "state_bucket" {
  description = "GCS bucket name used for Terraform remote state"
  type        = string
}

variable "owner" {
  description = "Owner label value applied to all resources"
  type        = string
}

# ── Cross-lab inputs ──────────────────────────────────────────────────────────
variable "cf_runtime_sa_email" {
  description = "Cloud Function runtime SA email from lab-01-gsc-privesc-b output cf_runtime_sa_email. This SA is granted kms_reader on this project."
  type        = string
}
