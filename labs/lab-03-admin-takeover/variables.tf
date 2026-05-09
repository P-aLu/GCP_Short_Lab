variable "project_id" {
  description = "GCP project ID for the admin project ([uid]-admin-palu)"
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
variable "owner" {
  description = "Owner label value applied to all resources"
  type        = string
}

# ── Cross-lab inputs ───────────────────────────────────────────────────────────
variable "projects_scanner_sa_email" {
  description = "projects_scanner SA email from lab-02-kms-privesc output. This SA is the learner's entry credential for lab-03."
  type        = string
}

variable "flag" {
  description = "Flag string stored in the admin Secret Manager secret (Stage 5 completion)"
  type        = string
  default     = "FLAG{1ab03_1am_d3ny_p0l1cy_byp4ss_pwn3d}"
}
