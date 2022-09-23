# Create a service account for Yugabyte
# Create a key for the service account
# Add each partner emails to project
# For each env - create a portal VM
terraform {
  required_providers {
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}


provider "google" {
  project     = var.gcp-project-id
  region      = var.gcp-region
}
provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
  # server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"

}

locals {
  participants-email-list = flatten(values(var.participants))
  attendees-email-list = concat(local.participants-email-list, var.instructors)
  org_count = length(keys(var.participants))
  org_list = keys(var.participants)

  expiry_title = "expired_after_soon"
  expiry_desc = "Expiring at ${var.expiry}"
  expiry_expression  = "request.time < timestamp(\"${var.expiry}\")"

}


resource "google_service_account" "yugabyte-sa" {
  account_id   = "${var.prefix}-yugabyte-sa"
  display_name = "${var.prefix} Service Account"
}

resource "google_project_iam_member" "yugaware-sa-owner-binding" {
  project = var.gcp-project-id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.yugabyte-sa.email}"
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

data "google_dns_managed_zone" "workshop-dns-zone" {
  name = var.dns_zone
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
    title = local.expiry_title
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


resource "google_compute_firewall" "allow-access-from-iap" {
  name    = "${var.prefix}-workshop-iap"
  network = var.gcp_network

  allow {
    protocol = "tcp"
    ports    = ["22","3389"]
  }

  target_tags = ["yugaware","cluster-server"]
  source_ranges = ["35.235.240.0/20"]
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

resource "google_dns_record_set" "yugaware-dns" {
  for_each =  var.participants
  name = "yugaware-${each.key}.${var.domain}."
  type = "A"
  ttl  = 300
  managed_zone = var.dns_zone
  rrdatas = [ google_compute_instance.yugaware[each.key].network_interface.0.access_config.0.nat_ip]
}


resource "google_compute_instance_iam_binding" "instance-iam-binding-login" {
  for_each = var.participants
  instance_name =  google_compute_instance.yugaware[each.key].name
  zone = var.primary-zone
  role = "roles/compute.osLogin"
  members = formatlist("user:%s", concat(each.value, var.instructors))
  condition {
    title = local.expiry_title
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
    title = local.expiry_title
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
    title = local.expiry_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}


resource "google_compute_instance" "instructor-yugaware" {

  name         = "${var.prefix}-instructor-yugaware"
  machine_type = var.yugaware-machine-type
  zone         = var.primary-zone

  tags = ["yugaware", "instructor"]

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

  metadata = merge({ org = "instructor"}, var.tags)

  metadata_startup_script = "echo hi > /test.txt"

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.yugabyte-sa.email
    scopes = ["cloud-platform"]
  }
}
resource "google_dns_record_set" "instructor-yugaware-dns" {

  name = "yugaware-instructor.${var.domain}."
  type = "A"
  ttl  = 300
  managed_zone = var.dns_zone
  rrdatas = [ google_compute_instance.instructor-yugaware.network_interface.0.access_config.0.nat_ip]
}




resource "google_compute_instance_iam_binding" "instructor-instance-iam-binding-login" {

  instance_name =  google_compute_instance.instructor-yugaware.name
  zone = var.primary-zone
  role = "roles/compute.osLogin"
  members = formatlist("user:%s", var.instructors)
  condition {
    title = local.expiry_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}


resource "google_compute_instance_iam_binding" "instructor-instance-iam-binding-setmd" {
  instance_name = google_compute_instance.instructor-yugaware.name
  zone = var.primary-zone
  role = google_project_iam_custom_role.attendees-project-role.id
  members = formatlist("user:%s",var.instructors)
  condition {
    title = local.expiry_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }

}

resource "google_storage_bucket" "instructor-backup-bucket" {
  name = "${var.prefix}-instructor-backup"
  location = var.gcs-region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_binding" "instructors-backup-bucket-access" {
  bucket = google_storage_bucket.instructor-backup-bucket.name
  role = "roles/storage.admin"
  members = concat(formatlist( "user:%s", var.instructors), ["serviceAccount:${google_service_account.yugabyte-sa.email}"])

  condition {
    title = local.expiry_title
    description = local.expiry_desc
    expression = local.expiry_expression
  }
}


resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  account_key_pem = "${tls_private_key.private_key.private_key_pem}"
  email_address   = var.cert_email
}

resource "acme_certificate" "certificate" {
  account_key_pem           = "${acme_registration.reg.account_key_pem}"
  common_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]

  dns_challenge {
    provider = "gcloud"
    config = {
      GCE_PROJECT = var.gcp-project-id
    }
  }
}
resource "local_file" "certificate-key" {
    content     = acme_certificate.certificate.private_key_pem
    filename = "${path.cwd}/${var.prefix}-certificate-private-key.pem"
}
resource "local_file" "certificate" {
    content     = "${acme_certificate.certificate.certificate_pem}"
    filename = "${path.cwd}/${var.prefix}-certificate.pem"
}

resource "local_file" "full-certificate" {
    content     = "${acme_certificate.certificate.certificate_pem}${acme_certificate.certificate.issuer_pem}"
    filename = "${path.cwd}/${var.prefix}-full-certificate.pem"
}

resource "local_file" "issuer-certificate" {
    content     = "${acme_certificate.certificate.issuer_pem}"
    filename = "${path.cwd}/${var.prefix}-issuer-certificate.pem"
}


resource "google_dns_record_set" "workshop-homepage" {
  name = "${var.domain}."
  type = "CNAME"
  ttl  = 300
  managed_zone = var.dns_zone
  rrdatas = [ "c.storage.googleapis.com."]
}


resource "google_storage_bucket" "workshop-homepage" {
  name = var.domain
  location = var.gcs-region
  force_destroy = true
  uniform_bucket_level_access = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  cors {
    origin          = ["http://${var.domain}"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket_access_control" "public_rule" {
  bucket = google_storage_bucket.workshop-homepage.name
  role   = "READER"
  entity = "allAuthenticatedUsers"
}

locals{
  instructions = <<EOT
Instruction:
============
- Instructors can connect to any VM
- Participants can only connect to their own VM
- Firewall ports have been opened for accessing all known services
- VM for YugabyteDB Anywhere is already created
- Bucket for Backup / Restor is already created
- Service account is already created and its JSON key will be provided by instructors
- License file (.rli) will be provided by instructors
- Download and install the 'gcloud' command line on your workstation (recommended) or use cloud shell on google console.
- Install gcloud Command: https://cloud.google.com/sdk/docs/install
- Yugaware installation instructions are at : https://docs.yugabyte.com/preview/yugabyte-platform/install-yugabyte-platform/prepare-environment/gcp/

Network: default
Subnet Map:
ap-southeast1-a = default
ap-southeast1-b = default
ap-southeast1-c = default

Files:
======
- Service Account Key: ${basename(local_file.yugabyte-sa-key.filename)}
- DNS Certificate:
    Private Key: ${basename(local_file.certificate-key.filename)}
    Certificate (Full): ${basename(local_file.full-certificate.filename)}
    Certificate : ${basename(local_file.certificate.filename)}
    Issuer Certificate : ${basename(local_file.issuer-certificate.filename)}
Instructors:
============
%{ for email in var.instructors }- ${email}
%{ endfor}

VM: ${google_compute_instance.instructor-yugaware.name}
Bucket: ${google_storage_bucket.instructor-backup-bucket.name}
SSH Command: gcloud compute ssh ${google_compute_instance.instructor-yugaware.name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap
FQDN: yugaware.instructor.${var.domain}
Portal: http://yugaware-instructor.${var.domain}/
Replicated: http://yugaware-instructor.${var.domain}:8800

Participant & Their VMs:
========================

%{ for org, emails in var.participants }
  Organization: ${org}
  VM: ${google_compute_instance.yugaware[org].name}
  Bucket: ${google_storage_bucket.backup-bucket[org].name}
  Email: ${join(",", emails)}
  SSH Command: gcloud compute ssh ${google_compute_instance.yugaware[org].name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap
  FQDN: yugaware.instructor.${var.domain}
  Portal: http://yugaware-${org}.${var.domain}/
  Replicated: http://yugaware-${org}.${var.domain}:8800/

%{ endfor}


All Attendees Email: ${join(", ", local.attendees-email-list)}
EOT
}

resource "local_file" "workshop-homepage" {
    content     = "<html><head><title>Yugabyte Workshop ${var.prefix}</title><body><pre>${local.instructions}</pre></html>"
    filename = "${path.cwd}/index.html"
}


resource "google_storage_bucket_object" "workshop-homepage" {
  name   = "index.html"
  source = local_file.workshop-homepage.filename
  bucket = google_storage_bucket.workshop-homepage.name
}
