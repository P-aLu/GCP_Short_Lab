variable "project_id" {
  description = "GCP project ID for the webapp project ([uid]-webapp-palu) — shared with lab-02-kms-privesc"
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

# ── Credentials injected from Project A outputs ───────────────────────────────
variable "cf_api_user" {
  description = "Cloud Function API username — take from lab-01-gsc-privesc output cf_api_user"
  type        = string
}

variable "cf_api_password" {
  description = "Cloud Function API password — take from lab-01-gsc-privesc output cf_api_password"
  type        = string
  sensitive   = true
}

variable "flag" {
  description = "Flag string returned to the learner upon successful authentication (Stage 6 completion)"
  type        = string
  default     = "FLAG{1ab01_tfst4t3_l4t3r4l_m0v3m3nt_pwn3d}"
}
