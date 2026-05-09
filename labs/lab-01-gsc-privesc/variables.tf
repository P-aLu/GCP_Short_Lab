variable "project_id" {
  description = "GCP project ID for Project A (the vulnerable deployment project)"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for compute resources"
  type        = string
  default     = "europe-west1-b"
}

variable "owner" {
  description = "Owner label value applied to all resources"
  type        = string
}

variable "cf_function_url" {
  description = "URL of the Cloud Function flag endpoint in Project B. Set after Project B is deployed; defaults to a placeholder."
  type        = string
  default     = "https://placeholder.cloudfunctions.net/flag"
}

variable "deployment_uid" {
  description = "Pre-set deployment UID from setup.sh. When non-empty, overrides random_id.deployment so project names are fixed before Terraform runs."
  type        = string
  default     = ""
}
