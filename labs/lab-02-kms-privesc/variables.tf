variable "project_id" {
  description = "GCP project ID for the webapp project ([uid]-webapp-palu) — same project as lab-01-gsc-privesc-b"
  type        = string
}

variable "deployment_uid" {
  description = "Shared deployment UID — copy from lab-01-gsc-privesc output deployment_uid"
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
