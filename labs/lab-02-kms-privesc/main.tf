# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  uid = random_id.deployment.hex

  # Resource names follow the scenario description exactly so learners can
  # cross-reference the README during the exercise.
  kms_keyring_name   = "${local.uid}-webapp"
  kms_key_name       = "${local.uid}-webapp-kms"
  secret_name        = "${local.uid}-webapp_config"
  bq_dataset_id      = "${local.uid}_data"
  bq_staging_bucket  = "${local.uid}-bq-staging"

  labels = {
    env   = "lab"
    lab   = "lab-02-kms-privesc"
    owner = var.owner
  }
}

# ── Random values ─────────────────────────────────────────────────────────────
resource "random_id" "deployment" {
  byte_length = 4
}

# ── Required APIs ─────────────────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── Custom role: kms_reader ───────────────────────────────────────────────────
# Grants just enough permissions to discover the encrypted secret and decrypt
# it with the KMS key — the intended path for Stage 3 and 4 of the kill chain.
resource "google_project_iam_custom_role" "kms_reader" {
  project     = var.project_id
  role_id     = "kms_reader"
  title       = "KMS Reader"
  description = "List and read Secret Manager secrets; list and use KMS keys to decrypt; read IAM policy."
  permissions = [
    "resourcemanager.projects.getIamPolicy",
    "iam.roles.get",
    "iam.roles.list",
    "secretmanager.secrets.list",
    "secretmanager.secrets.get",
    "secretmanager.versions.list",
    "secretmanager.versions.access",
    "cloudkms.keyRings.list",
    "cloudkms.cryptoKeys.list",
    "cloudkms.cryptoKeyVersions.list",
    "cloudkms.cryptoKeyVersions.useToDecrypt",
  ]
  depends_on = [google_project_service.apis]
}

# Grant kms_reader to the Cloud Function runtime SA from Project B.
# This is what the learner discovers after stealing the metadata token.
resource "google_project_iam_member" "cf_kms_reader" {
  project = var.project_id
  role    = google_project_iam_custom_role.kms_reader.id
  member  = "serviceAccount:${var.cf_runtime_sa_email}"
}

# ── webapp_owner service account ──────────────────────────────────────────────
# The SA whose key is hidden inside the KMS-encrypted secret.
resource "google_service_account" "webapp_owner" {
  account_id   = "webapp-owner"
  display_name = "Lab 02 — webapp_owner (Stage 5 pivot)"
  project      = var.project_id
  depends_on   = [google_project_service.apis]
}

resource "google_service_account_key" "webapp_owner" {
  service_account_id = google_service_account.webapp_owner.name
}

# webapp_owner can read and query BigQuery tables in this project.
resource "google_project_iam_member" "webapp_owner_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.webapp_owner.email}"
}

resource "google_project_iam_member" "webapp_owner_bq_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.webapp_owner.email}"
}

# ── KMS key ring and key ──────────────────────────────────────────────────────
# Note: KMS key rings cannot be deleted from GCP. Terraform destroy removes
# them from state only. A fresh apply will always use a new UID.
resource "google_kms_key_ring" "lab" {
  name       = local.kms_keyring_name
  location   = var.region
  project    = var.project_id
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "webapp" {
  name            = local.kms_key_name
  key_ring        = google_kms_key_ring.lab.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = null

  lifecycle {
    prevent_destroy = false
  }
}

# ── Encrypt webapp_owner SA key with KMS ──────────────────────────────────────
# google_service_account_key.private_key is already base64(SA_key_JSON).
# google_kms_secret_ciphertext.plaintext interprets its input as base64, so it
# encrypts the underlying SA key JSON bytes. On decrypt the learner gets the
# raw SA key JSON directly usable as a credentials file.
resource "google_kms_secret_ciphertext" "webapp_owner_key" {
  crypto_key = google_kms_crypto_key.webapp.id
  plaintext  = google_service_account_key.webapp_owner.private_key
}

# ── Secret Manager ────────────────────────────────────────────────────────────
resource "google_secret_manager_secret" "webapp_config" {
  project   = var.project_id
  secret_id = local.secret_name
  labels    = local.labels

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "webapp_config" {
  secret      = google_secret_manager_secret.webapp_config.id
  secret_data = google_kms_secret_ciphertext.webapp_owner_key.ciphertext
}

# ── projects_scanner service account ─────────────────────────────────────────
# The SA whose full key JSON is stored as a row in the secret BigQuery table.
# Lab-03 will grant this SA access to the admin project, making it useful for
# the final pivot (Stage 7 → lab-03 entry).
resource "google_service_account" "projects_scanner" {
  account_id   = "projects-scanner"
  display_name = "Lab 02 — projects_scanner (lab-03 pivot point)"
  project      = var.project_id
  depends_on   = [google_project_service.apis]
}

resource "google_service_account_key" "projects_scanner" {
  service_account_id = google_service_account.projects_scanner.name
}

resource "google_project_iam_member" "projects_scanner_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.projects_scanner.email}"
}

# ── BigQuery dataset and tables ───────────────────────────────────────────────
resource "google_bigquery_dataset" "lab" {
  dataset_id  = local.bq_dataset_id
  location    = var.region
  project     = var.project_id
  labels      = local.labels
  description = "webapp deployment analytics"

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_table" "metrics" {
  dataset_id          = google_bigquery_dataset.lab.dataset_id
  table_id            = "metrics"
  project             = var.project_id
  deletion_protection = false
  labels              = local.labels

  schema = jsonencode([
    { name = "ts",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "value", type = "FLOAT64",   mode = "REQUIRED" },
    { name = "label", type = "STRING",    mode = "REQUIRED" },
  ])
}

resource "google_bigquery_table" "events" {
  dataset_id          = google_bigquery_dataset.lab.dataset_id
  table_id            = "events"
  project             = var.project_id
  deletion_protection = false
  labels              = local.labels

  schema = jsonencode([
    { name = "ts",         type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "event_type", type = "STRING",    mode = "REQUIRED" },
    { name = "message",    type = "STRING",    mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "secret_bigquery" {
  dataset_id          = google_bigquery_dataset.lab.dataset_id
  table_id            = "secret_bigquery"
  project             = var.project_id
  deletion_protection = false
  labels              = local.labels

  schema = jsonencode([
    { name = "secret_key", type = "STRING", mode = "REQUIRED",
      description = "GCP service account key JSON" },
  ])
}

# ── GCS staging bucket for BigQuery load jobs ─────────────────────────────────
resource "google_storage_bucket" "bq_staging" {
  name                        = local.bq_staging_bucket
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = local.labels

  lifecycle {
    prevent_destroy = false
  }
}

# Noise data: metrics
resource "google_storage_bucket_object" "metrics_data" {
  name   = "metrics.json"
  bucket = google_storage_bucket.bq_staging.name
  content = join("\n", [
    jsonencode({ ts = "2024-01-08T09:00:00Z", value = 42.7, label = "cpu_usage" }),
    jsonencode({ ts = "2024-01-08T09:05:00Z", value = 38.2, label = "cpu_usage" }),
    jsonencode({ ts = "2024-01-08T09:10:00Z", value = 55.1, label = "memory_usage" }),
    jsonencode({ ts = "2024-01-08T09:15:00Z", value = 12.4, label = "disk_io" }),
    jsonencode({ ts = "2024-01-08T09:20:00Z", value = 61.0, label = "memory_usage" }),
    jsonencode({ ts = "2024-01-08T09:25:00Z", value = 29.8, label = "cpu_usage" }),
  ])
}

# Noise data: events
resource "google_storage_bucket_object" "events_data" {
  name   = "events.json"
  bucket = google_storage_bucket.bq_staging.name
  content = join("\n", [
    jsonencode({ ts = "2024-01-08T09:00:00Z", event_type = "deploy",  message = "Deployment pipeline started" }),
    jsonencode({ ts = "2024-01-08T09:02:14Z", event_type = "build",   message = "Docker image build complete" }),
    jsonencode({ ts = "2024-01-08T09:04:37Z", event_type = "push",    message = "Image pushed to Artifact Registry" }),
    jsonencode({ ts = "2024-01-08T09:06:51Z", event_type = "deploy",  message = "Cloud Function deployed" }),
    jsonencode({ ts = "2024-01-08T09:07:03Z", event_type = "healthcheck", message = "Health check passed" }),
  ])
}

# Secret data: projects_scanner SA key (the Stage 7 credential).
# The SA key JSON is stored as a single string field; the learner must parse
# it and use it to discover the admin project.
locals {
  scanner_key_json = base64decode(google_service_account_key.projects_scanner.private_key)
}

resource "google_storage_bucket_object" "secret_bq_data" {
  name   = "secret_bigquery.json"
  bucket = google_storage_bucket.bq_staging.name
  content = jsonencode({ secret_key = local.scanner_key_json })
}

# ── BigQuery load jobs ────────────────────────────────────────────────────────
resource "google_bigquery_job" "load_metrics" {
  job_id   = "${local.uid}-load-metrics"
  location = var.region
  project  = var.project_id
  labels   = local.labels

  load {
    source_uris   = ["gs://${google_storage_bucket.bq_staging.name}/metrics.json"]
    source_format = "NEWLINE_DELIMITED_JSON"
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.lab.dataset_id
      table_id   = google_bigquery_table.metrics.table_id
    }
    write_disposition = "WRITE_TRUNCATE"
  }

  depends_on = [google_storage_bucket_object.metrics_data]
}

resource "google_bigquery_job" "load_events" {
  job_id   = "${local.uid}-load-events"
  location = var.region
  project  = var.project_id
  labels   = local.labels

  load {
    source_uris   = ["gs://${google_storage_bucket.bq_staging.name}/events.json"]
    source_format = "NEWLINE_DELIMITED_JSON"
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.lab.dataset_id
      table_id   = google_bigquery_table.events.table_id
    }
    write_disposition = "WRITE_TRUNCATE"
  }

  depends_on = [google_storage_bucket_object.events_data]
}

resource "google_bigquery_job" "load_secret" {
  job_id   = "${local.uid}-load-secret"
  location = var.region
  project  = var.project_id
  labels   = local.labels

  load {
    source_uris   = ["gs://${google_storage_bucket.bq_staging.name}/secret_bigquery.json"]
    source_format = "NEWLINE_DELIMITED_JSON"
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.lab.dataset_id
      table_id   = google_bigquery_table.secret_bigquery.table_id
    }
    write_disposition = "WRITE_TRUNCATE"
  }

  depends_on = [google_storage_bucket_object.secret_bq_data]
}
