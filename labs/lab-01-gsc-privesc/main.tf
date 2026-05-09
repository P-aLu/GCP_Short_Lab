# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  uid          = var.deployment_uid != "" ? var.deployment_uid : random_id.deployment.hex
  bucket_name  = "${local.uid}-deployments"
  compute_name = "${local.uid}-deployments-sql-compute"
  sql_name     = "${local.uid}-deployments-sql"
  network_name = "${local.uid}-lab-network"
  subnet_name  = "${local.uid}-lab-subnet"
  db_name      = "deployments"
  sa_name      = "training-start"
  ssh_user     = "cicd"

  labels = {
    env   = "lab"
    lab   = "lab-01-gsc-privesc"
    owner = var.owner
  }

  # Noise log dates written to the deployment bucket to hide the tfstate among
  # plausible-looking CI/CD artefacts.
  noise_dates = [
    "2024-01-08", "2024-01-22", "2024-02-05", "2024-02-19",
    "2024-03-04", "2024-03-18", "2024-04-01", "2024-04-15",
  ]
}

# ── Random values ─────────────────────────────────────────────────────────────
resource "random_id" "deployment" {
  byte_length = 4
}

resource "random_password" "sql_root" {
  length  = 24
  special = false
}

resource "random_password" "sql_user" {
  length  = 24
  special = false
}

resource "random_password" "cf_api" {
  length  = 32
  special = false
}

# ── SSH key pair ──────────────────────────────────────────────────────────────
# Private key is intentionally embedded in the planted tfstate (see below) —
# that exposure is the learning objective of Stage 2.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ── Required APIs ─────────────────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── Network ───────────────────────────────────────────────────────────────────
resource "google_compute_network" "lab" {
  name                    = local.network_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "lab" {
  name          = local.subnet_name
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.lab.id
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.uid}-allow-ssh"
  network = google_compute_network.lab.name
  labels  = local.labels

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lab-01-ssh"]
}

# Static external IP ensures the SQL authorized-network is stable across
# instance restarts and avoids a chicken-and-egg dependency.
resource "google_compute_address" "sql_compute" {
  name       = "${local.compute_name}-ip"
  region     = var.region
  depends_on = [google_project_service.apis]
}

# ── Service account (learner entry point) ────────────────────────────────────
resource "google_service_account" "training_start" {
  account_id   = local.sa_name
  display_name = "Lab 01 — Training Start (learner entry point)"
  project      = var.project_id
  depends_on   = [google_project_service.apis]
}

# ── GCS deployment bucket ─────────────────────────────────────────────────────
resource "google_storage_bucket" "deployments" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = local.labels

  lifecycle {
    prevent_destroy = false
  }
}

# objectViewer grants storage.objects.{get,list} — exactly the starting foothold.
resource "google_storage_bucket_iam_member" "training_start_viewer" {
  bucket = google_storage_bucket.deployments.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.training_start.email}"
}

# legacyBucketReader is needed for gsutil ls / gcloud storage ls to work.
resource "google_storage_bucket_iam_member" "training_start_lister" {
  bucket = google_storage_bucket.deployments.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.training_start.email}"
}

# ── Noise files ───────────────────────────────────────────────────────────────
resource "google_storage_bucket_object" "noise_logs" {
  for_each = toset(local.noise_dates)

  name   = "deployment-${each.key}.log"
  bucket = google_storage_bucket.deployments.name
  content = <<-EOT
    [${each.key} 09:12:34] INFO  Deployment pipeline started — ref: main
    [${each.key} 09:12:35] INFO  Initializing Terraform workspace
    [${each.key} 09:12:48] INFO  Terraform init complete
    [${each.key} 09:13:01] INFO  Running terraform validate... OK
    [${each.key} 09:13:22] INFO  Plan: 0 to add, 2 to change, 0 to destroy
    [${each.key} 09:13:23] INFO  Applying changes...
    [${each.key} 09:14:57] INFO  Apply complete! Resources: 2 changed, 0 added, 0 destroyed
    [${each.key} 09:14:58] INFO  Uploading state artefacts to GCS
    [${each.key} 09:14:59] INFO  Deployment complete
  EOT
}

resource "google_storage_bucket_object" "noise_txts" {
  for_each = toset(local.noise_dates)

  name   = "deployment-${each.key}.txt"
  bucket = google_storage_bucket.deployments.name
  content = <<-EOT
    Deployment Summary
    ==================
    Date      : ${each.key}
    Status    : SUCCESS
    Changed   : 2 resources
    Duration  : 2m 25s
    Operator  : cicd-deploy@${var.project_id}.iam.gserviceaccount.com
    Ref       : main
  EOT
}

# ── Cloud SQL ─────────────────────────────────────────────────────────────────
resource "google_sql_database_instance" "main" {
  name             = local.sql_name
  database_version = "MYSQL_8_0"
  region           = var.region
  project          = var.project_id
  root_password    = random_password.sql_root.result

  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    user_labels = local.labels

    ip_configuration {
      ipv4_enabled = true
      require_ssl  = false

      # Only the compute instance's static IP can reach the database.
      authorized_networks {
        name  = "lab-compute-only"
        value = google_compute_address.sql_compute.address
      }
    }

    backup_configuration {
      enabled = false
    }
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "deployments" {
  name     = local.db_name
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

resource "google_sql_user" "lab_user" {
  name     = "labuser"
  instance = google_sql_database_instance.main.name
  host     = "%"
  password = random_password.sql_user.result
  project  = var.project_id
}

# ── Compute instance ──────────────────────────────────────────────────────────
resource "google_compute_instance" "sql_compute" {
  name         = local.compute_name
  machine_type = "e2-micro"
  zone         = var.zone
  project      = var.project_id
  labels       = local.labels
  tags         = ["lab-01-ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    access_config {
      nat_ip = google_compute_address.sql_compute.address
    }
  }

  metadata = {
    # Public key placed here by the "deployment pipeline" — private key lives
    # in the tfstate file in the GCS bucket (the Stage 2 finding).
    ssh-keys = "${local.ssh_user}:${tls_private_key.ssh.public_key_openssh}"
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    sql_ip          = google_sql_database_instance.main.public_ip_address
    sql_user        = google_sql_user.lab_user.name
    sql_password    = random_password.sql_user.result
    db_name         = local.db_name
    cf_api_user     = "cf-api-${local.uid}"
    cf_api_password = random_password.cf_api.result
    cf_url          = var.cf_function_url
  })

  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [
    google_sql_user.lab_user,
    google_sql_database.deployments,
    google_project_service.apis,
  ]
}

# ── Planted tfstate ───────────────────────────────────────────────────────────
# Mimics a real Terraform state file carelessly written to the public-readable
# GCS bucket. The learner extracts the SSH private key from tls_private_key and
# the SQL credentials from google_sql_user to advance the kill chain.
locals {
  planted_tfstate = jsonencode({
    version           = 4
    terraform_version = "1.6.6"
    serial            = 47
    lineage           = "d4f8a2b1-3e6c-4a5d-9f0b-2c7e8d1a4b5c"
    outputs           = {}
    resources = [
      {
        mode     = "managed"
        type     = "tls_private_key"
        name     = "ssh"
        provider = "provider[\"registry.terraform.io/hashicorp/tls\"]"
        instances = [{
          schema_version = 1
          attributes = {
            algorithm                     = "RSA"
            ecdsa_curve                   = "P224"
            id                            = tls_private_key.ssh.public_key_fingerprint_md5
            private_key_openssh           = tls_private_key.ssh.private_key_openssh
            private_key_pem               = tls_private_key.ssh.private_key_pem
            public_key_fingerprint_md5    = tls_private_key.ssh.public_key_fingerprint_md5
            public_key_fingerprint_sha256 = tls_private_key.ssh.public_key_fingerprint_sha256
            public_key_openssh            = tls_private_key.ssh.public_key_openssh
            public_key_pem                = tls_private_key.ssh.public_key_pem
            rsa_bits                      = 4096
          }
        }]
      },
      {
        mode     = "managed"
        type     = "google_compute_address"
        name     = "sql_compute"
        provider = "provider[\"registry.terraform.io/hashicorp/google\"]"
        instances = [{
          schema_version = 0
          attributes = {
            address      = google_compute_address.sql_compute.address
            address_type = "EXTERNAL"
            id           = google_compute_address.sql_compute.id
            name         = google_compute_address.sql_compute.name
            network_tier = "PREMIUM"
            region       = var.region
            self_link    = google_compute_address.sql_compute.self_link
          }
        }]
      },
      {
        mode     = "managed"
        type     = "google_compute_instance"
        name     = "sql_compute"
        provider = "provider[\"registry.terraform.io/hashicorp/google\"]"
        instances = [{
          schema_version = 6
          attributes = {
            id           = google_compute_instance.sql_compute.id
            name         = local.compute_name
            machine_type = "e2-micro"
            zone         = var.zone
            labels       = local.labels
            tags         = ["lab-01-ssh"]
            metadata = {
              ssh-keys = "${local.ssh_user}:${tls_private_key.ssh.public_key_openssh}"
            }
            network_interface = [{
              name       = "nic0"
              network    = google_compute_network.lab.self_link
              subnetwork = google_compute_subnetwork.lab.self_link
              network_ip = google_compute_instance.sql_compute.network_interface[0].network_ip
              access_config = [{
                nat_ip       = google_compute_address.sql_compute.address
                network_tier = "PREMIUM"
              }]
            }]
            self_link = google_compute_instance.sql_compute.self_link
          }
        }]
      },
      {
        mode     = "managed"
        type     = "google_sql_database_instance"
        name     = "main"
        provider = "provider[\"registry.terraform.io/hashicorp/google\"]"
        instances = [{
          schema_version = 1
          attributes = {
            id                = local.sql_name
            name              = local.sql_name
            database_version  = "MYSQL_8_0"
            region            = var.region
            connection_name   = "${var.project_id}:${var.region}:${local.sql_name}"
            public_ip_address = google_sql_database_instance.main.public_ip_address
            ip_address = [{
              ip_address     = google_sql_database_instance.main.public_ip_address
              time_to_retire = ""
              type           = "PRIMARY"
            }]
          }
        }]
      },
      {
        mode     = "managed"
        type     = "google_sql_user"
        name     = "lab_user"
        provider = "provider[\"registry.terraform.io/hashicorp/google\"]"
        instances = [{
          schema_version = 1
          attributes = {
            host     = "%"
            id       = "labuser//${local.sql_name}"
            instance = local.sql_name
            name     = "labuser"
            password = random_password.sql_user.result
            project  = var.project_id
          }
        }]
      }
    ]
  })
}

resource "google_storage_bucket_object" "planted_tfstate" {
  name    = "${local.uid}-deployment.tfstate"
  bucket  = google_storage_bucket.deployments.name
  content = local.planted_tfstate

  depends_on = [
    google_compute_instance.sql_compute,
    google_sql_database_instance.main,
  ]
}
