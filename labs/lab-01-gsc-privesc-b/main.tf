# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  uid           = var.deployment_uid
  function_name = "${local.uid}-flag-api"
  source_bucket = "${local.uid}-cf-source"

  labels = {
    env   = "lab"
    lab   = "lab-01-gsc-privesc-b"
    owner = var.owner
  }
}

# ── Required APIs ─────────────────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── Cloud Function runtime service account ────────────────────────────────────
# The metadata token available inside the function belongs to this SA.
# Lab-02 grants this SA the kms_reader custom role on the webapp project.
resource "google_service_account" "cf_runtime" {
  account_id   = "cf-runtime"
  display_name = "Lab 01-B — Cloud Function runtime SA (lab-02 pivot point)"
  project      = var.project_id
  depends_on   = [google_project_service.apis]
}

# ── GCS bucket for Cloud Function source ──────────────────────────────────────
resource "google_storage_bucket" "cf_source" {
  name                        = local.source_bucket
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = local.labels

  lifecycle {
    prevent_destroy = false
  }
}

# ── Package and upload the function source ────────────────────────────────────
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/.terraform/function-source.zip"
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.cf_source.name
  source = data.archive_file.function_source.output_path
}

# ── Cloud Function (Gen 2) ────────────────────────────────────────────────────
resource "google_cloudfunctions2_function" "flag_api" {
  name     = local.function_name
  location = var.region
  project  = var.project_id
  labels   = local.labels

  build_config {
    runtime     = "python311"
    entry_point = "handler"
    source {
      storage_source {
        bucket = google_storage_bucket.cf_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    min_instance_count    = 0
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.cf_runtime.email

    environment_variables = {
      CF_API_USER     = var.cf_api_user
      CF_API_PASSWORD = var.cf_api_password
      FLAG            = var.flag
    }
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_project_service.apis]
}

# ── Allow unauthenticated invocation ─────────────────────────────────────────
# The function handles its own credential check in Python; GCP-level auth is
# left open so learners can reach it with a plain HTTP client.
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.flag_api.project
  location       = google_cloudfunctions2_function.flag_api.location
  cloud_function = google_cloudfunctions2_function.flag_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker" {
  project  = google_cloudfunctions2_function.flag_api.project
  location = google_cloudfunctions2_function.flag_api.location
  service  = google_cloudfunctions2_function.flag_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
