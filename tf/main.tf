# Create a service account for Yugabyte
# Create a key for the service account
# Add each partner emails to project
# For each env - create a portal VM

provider "google" {
  project     = var.gcp-project-id
  region      = var.gcp-region
}

locals {
  participants-email-list = flatten(values(var.participants))
  attendees-email-list = concat(local.participants-email-list, var.instructors)
  org_count = length(keys(var.participants))
  org_list = keys(var.participants)

  expiry_time = timeadd(timestamp(), "${24*(var.duration + 1)}h")
  expiry_time_str = formatdate("YYYY-MM-DD'T'HH:mm:ssZ",local.expiry_time)
  expity_title = "expired_after_${var.duration}_day"
  expiry_desc = "Expiring at ${local.expiry_time_str}"
  expiry_expression  = "request.time < timestamp(\"${local.expiry_time_str}\")"

}


resource "google_service_account" "yugabyte-sa" {
  account_id   = "${var.prefix}-yugabyte-sa"
  display_name = "${var.prefix} Service Account"
}
resource "google_service_account_key" "yugabyte-sa-key" {
  service_account_id = google_service_account.yugabyte-sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "local_file" "yugabyte-sa-key" {
    content     = base64decode(google_service_account_key.yugabyte-sa-key.private_key)
    filename = "${path.cwd}/${var.prefix}-yugabyte-sa-key.secret.json"
}

data "google_compute_image" "vm_image" {
  project  = "ubuntu-os-cloud"
  family = "ubuntu-2004-lts"
}


resource "google_project_iam_custom_role" "attendees-project-role" {
  role_id     = replace("${var.prefix}_attendee_project_roles", "-","_")
  title       = "${var.prefix} - Attendees Project Role"
  description = "${var.prefix} - Project level role for attendees"
  permissions = ["compute.instances.setMetadata"]
}

resource "google_project_iam_member" "participant-iam-account" {
  for_each = toset(local.participants-email-list)
  project = var.gcp-project-id
  role    = "roles/viewer"
  member  = "user:${each.key}"
}

resource "google_project_iam_member" "instructor-iam-account" {
  for_each = toset(var.instructors)
  project = var.gcp-project-id
  role    = "roles/editor"
  member  = "user:${each.key}"
}


resource "google_service_account_iam_binding" "allow-use-sa" {
  service_account_id = google_service_account.yugabyte-sa.name
  role = "roles/iam.serviceAccountUser"
  members = formatlist("user:%s", local.attendees-email-list)
  condition {
    title = local.expity_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}

resource "google_compute_instance" "yugaware" {
  for_each = var.participants
  name         = "${var.prefix}-${each.key}-yugaware"
  machine_type = var.yugaware-machine-type
  zone         = var.primary-zone

  tags = ["yugaware", each.key]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.vm_image.self_link
      size = 100
    }
  }

  // Local SSD disk
  scratch_disk {
    interface = "SCSI"
  }

  network_interface {
    network = var.gcp_network

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = merge({ org = each.key}, var.tags)

  metadata_startup_script = "echo hi > /test.txt"

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.yugabyte-sa.email
    scopes = ["cloud-platform"]
  }
}



resource "google_compute_instance_iam_binding" "instance-iam-binding-login" {
  for_each = var.participants
  instance_name =  google_compute_instance.yugaware[each.key].name
  zone = var.primary-zone
  role = "roles/compute.osLogin"
  members = formatlist("user:%s", concat(each.value, var.instructors))
  condition {
    title = local.expity_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}


resource "google_compute_instance_iam_binding" "instance-iam-binding-setmd" {
  for_each = var.participants
  instance_name = google_compute_instance.yugaware[each.key].name
  zone = var.primary-zone
  role = google_project_iam_custom_role.attendees-project-role.id
  members = formatlist("user:%s", concat(each.value, var.instructors))
  condition {
    title = local.expity_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }

}

resource "google_storage_bucket" "backup-bucket" {
  for_each = var.participants
  name = "${var.prefix}-${each.key}-backup"
  location = var.gcs-region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_binding" "backup-bucket-access" {
  for_each = var.participants

  bucket = google_storage_bucket.backup-bucket[each.key].name
  role = "roles/storage.admin"
  members = concat(formatlist("user:%s", concat(each.value, var.instructors)), ["serviceAccount:${google_service_account.yugabyte-sa.email}"])

  condition {
    title = local.expity_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}


resource "google_compute_firewall" "allow-access" {
  name    = "${var.prefix}-workshop"
  network = var.gcp_network

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22","80", "443","3000","5000","5433","8080","8443","8800", "6379","7000", "7100","9100","9000","9042","30000-32767","54422"]
  }

  target_tags = ["yugaware","cluster-server"]
  source_ranges = ["0.0.0.0/0"]
}

