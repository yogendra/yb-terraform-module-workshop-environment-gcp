terraform {
  required_providers {
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
    google = {
      source = "hashicorp/google"
      version = "4.37.0"
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

  http_cert_key_filename = "${var.prefix}-http-cert-key.pem"
  http_cert_filename = "${var.prefix}-http-cert.pem"
  http_cert_full_filename = "${var.prefix}-http-cert-full.pem"
  http_cert_issuer_filename = "${var.prefix}-http-cert-issuer.pem"
  cloud_sa_key_filename = "${var.prefix}-yugabyte-sa-key.secret.json"
  license_filename = "${var.prefix}-license.rli"

  workshop_instruction_bucket = "${var.prefix}-workshop-instruction"
  workshop_home = "https://storage.cloud.google.com/${local.workshop_instruction_bucket}"
  workshop_homepage = "${local.workshop_home}/index.html"
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

data "google_compute_image" "vm_image" {
  project  = "ubuntu-os-cloud"
  family = "ubuntu-2004-lts"
}

data "google_dns_managed_zone" "workshop-dns-zone" {
  name = var.dns-zone
}

data "google_compute_regions" "available" {
}
data "google_compute_network" "network" {
  name = var.gcp-network
}

data "google_compute_subnetwork" "regional-subnet" {
  for_each = toset(data.google_compute_network.network.subnetworks_self_links)
  self_link = each.key
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
  network = var.gcp-network

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
  network = var.gcp-network

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
    network = var.gcp-network

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
  managed_zone = var.dns-zone
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
    network = var.gcp-network

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
  managed_zone = var.dns-zone
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
  email_address   = var.cert-email
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


resource "google_storage_bucket" "workshop-site" {
  name = local.workshop_instruction_bucket
  location = var.gcs-region
  force_destroy = true
  uniform_bucket_level_access = true


  # website {
  #   main_page_suffix = "index.html"
  #   not_found_page   = "404.html"
  # }
  # cors {
  #   origin          = ["*"]
  #   method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
  #   response_header = ["*"]
  #   max_age_seconds = 3600
  # }
}


resource "google_storage_bucket_object" "license-file" {
  name   = local.license_filename
  content_type = "application/octet-stream"
  source = var.license-file
  bucket = google_storage_bucket.workshop-site.name
}

resource "google_storage_bucket_object" "sa-key" {
  name   = local.cloud_sa_key_filename
  content_type = "application/octet-stream"
  content = base64decode(google_service_account_key.yugabyte-sa-key.private_key)
  bucket = google_storage_bucket.workshop-site.name
}


resource "google_storage_bucket_object" "http-cert" {
  name   = local.http_cert_filename
  content_type = "application/octet-stream"
  content = acme_certificate.certificate.certificate_pem
  bucket = google_storage_bucket.workshop-site.name
}
resource "google_storage_bucket_object" "http-cert-full" {
  name   = local.http_cert_full_filename
  content_type = "application/octet-stream"
  content     = "${acme_certificate.certificate.certificate_pem}${acme_certificate.certificate.issuer_pem}"
  bucket = google_storage_bucket.workshop-site.name
}


resource "google_storage_bucket_object" "http-cert-key" {
  name   = local.http_cert_key_filename
  content_type = "application/octet-stream"
  content     = acme_certificate.certificate.private_key_pem
  bucket = google_storage_bucket.workshop-site.name
}

resource "google_storage_bucket_object" "http-cert-issuer" {
  name   = local.http_cert_issuer_filename
  content_type = "application/octet-stream"
  content     = acme_certificate.certificate.issuer_pem
  bucket = google_storage_bucket.workshop-site.name
}



locals{
  instructions_html = <<EOT
  <!document html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta http-equiv="X-UA-Compatible" content="IE=edge">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${var.prefix} - Workshop Instruction</title>
      <style>
      td, td *, th, th * {
          vertical-align: top;
      }
      td ul{
        list-style-type: none;
      }
      th.in-body {
        text-align:right;
      }
      table {
        border-collapse: collapse;
        width: 100%;
      }

      th, td {
        text-align: left;
        padding: 8px;
      }

      tr:nth-child(even) {background-color: #f2f2f2;}
      tr tr:nth-child(even) { background-color: #00000000; }


      </style>
      <!-- Latest compiled and minified CSS -->
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">

      <!-- Optional theme -->
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/css/bootstrap-theme.min.css" integrity="sha384-rHyoN1iRsVXV4nD0JutlnGaslCJuC7uwjduW9SVrLvRYooPp2bWYgmgJQIXwl/Sp" crossorigin="anonymous">

      <!-- Latest compiled and minified JavaScript -->
      <script src="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
      <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js"></script>
      <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
      <!-- WARNING: Respond.js doesn't work if you view the page via file:// -->
      <!--[if lt IE 9]>
        <script src="https://cdn.jsdelivr.net/npm/html5shiv@3.7.3/dist/html5shiv.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/respond.js@1.4.2/dest/respond.min.js"></script>
      <![endif]-->
    </head>
    <body>

      <h1>${var.prefix} - Workshop Instruction</h1>

      <h2>Basic Setup</h2>
      <ul>
        <li>Instructors can connect to any VM</li>
        <li>Participants can only connect to their own VM</li>
        <li>Firewall ports have been opened for accessing all known services</li>
        <li>VM for YugabyteDB Anywhere is already created</li>
        <li>Bucket for Backup / Restore is already created</li>
        <li>Service account is already created and its JSON key will be provided by instructors</li>
        <li>License file (.rli) will be provided by instructors</li>
        <li>Download and install the 'gcloud' command line on your workstation (recommended) or use cloud shell on google console.</li>
        <li><a href="https://cloud.google.com/sdk/docs/install">Install gcloud Command</a></li>
        <li><a href="https://docs.yugabyte.com/preview/yugabyte-platform/install-yugabyte-platform/prepare-environment/gcp/">Yugaware installation instructions</a></li>
      </ul>

      <h2>Files</h2>

      <ul>
        <li>
          <a href="${local.workshop_home}/${local.license_filename}">License File</a>
        </li>
        <li>
          <details>
            <summary>
              <a href="${local.workshop_home}/${local.cloud_sa_key_filename}">Service Account Key</a>
            </summary>
            <pre>${base64decode(google_service_account_key.yugabyte-sa-key.private_key)}</pre>
          </details>
        </li>
        <li>
          HTTPS Certificate
          <ul>
            <li>
              <details>
                <summary>
                  <a href="${local.workshop_home}/${local.http_cert_key_filename}">Private Key</a>
                </summary>
                <pre>${acme_certificate.certificate.private_key_pem}</pre>
              </details>
            </li>
            <li>
              <details>
                <summary>
                  <a href="${local.workshop_home}/${local.http_cert_full_filename}">Certificate (Full)</a>
                </summary>
                <pre>${acme_certificate.certificate.certificate_pem}${acme_certificate.certificate.issuer_pem}</pre>
              </details>
            </li>
            <li>
              <details>
                <summary>
                  <a href="${local.workshop_home}/${local.http_cert_filename}">Certificate </a>
                </summary>
                <pre>${acme_certificate.certificate.certificate_pem}</pre>
              </details>
            </li>
            <li>
              <details>
                <summary>
                  <a href="${local.workshop_home}/${local.http_cert_issuer_filename}">Issuer Certificate </a>
                </summary>
                <pre>${acme_certificate.certificate.issuer_pem}</pre>
              </details>
            </li>
          </ul>
        </li>
      </ul>

      <h2>Machines/Compute</h2>

      <table class="stripped">
        <tr>
          <th>Group</th>
          <th>Member</th>
          <th>Information</th>
        <tr>
        <tr>
          <td>Instructors</td>
          <td>
            <ul>
            %{ for email in var.instructors }
              <li>${email}</li>
            %{ endfor}
            </ul>
          </td>
          <td>
            <table>
              <tr><th class="in-body">VM</th><td>${google_compute_instance.instructor-yugaware.name}</td> </tr>
              <tr><th class="in-body">Bucket</th><td>${google_storage_bucket.instructor-backup-bucket.name}</td>
              <tr><th class="in-body">SSH Command</th><td><pre>gcloud compute ssh ${google_compute_instance.instructor-yugaware.name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap</pre></td></tr>
              <tr><th class="in-body">FQDN</th><td>yugaware.instructor.${var.domain}</td></tr>
              <tr><th class="in-body">Portal</th><td><a href="http://yugaware-instructor.${var.domain}">http://yugaware-instructor.${var.domain}</a></td></tr>
              <tr><th class="in-body">Replicated</th><td><a href="http://yugaware-instructor.${var.domain}:8800">http://yugaware-instructor.${var.domain}:8800</a></td></tr>
            </table>
          </td>
        </tr>
        %{ for org, emails in var.participants }
        <tr>
          <td>${org}</td>
          <td>
            <ul>
            %{ for email in emails }
              <li>${email}</li>
            %{ endfor}
            </ul>
          </td>
          <td>
            <table>
              <tbody>
                <tr><th class="in-body">VM</th><td>${google_compute_instance.yugaware[org].name}</td> </tr>
                <tr><th class="in-body">Bucket</th><td>${google_storage_bucket.backup-bucket[org].name}</td>
                <tr><th class="in-body">SSH Command</th><td><pre>gcloud compute ssh ${google_compute_instance.yugaware[org].name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap</pre></td></tr>
                <tr><th class="in-body">FQDN</th><td>yugaware-${org}.${var.domain}</td></tr>
                <tr><th class="in-body">Portal</th><td><a href="http://yugaware-${org}.${var.domain}">http://yugaware-${org}.${var.domain}</a></td></tr>
                <tr><th class="in-body">Replicated</th><td><a href="http://yugaware-${org}.${var.domain}:8800">http://yugaware-${org}.${var.domain}:8800</a></td></tr>
              </tbody>
            </table>
          </td>
        </tr>
        %{ endfor}
      </table>

      <h2>Cloud Network</h2>
      <ul>
        <li>Network: ${var.gcp-network}</li>
        <li>
        Regionalwise Subnets
          <table>
            <tr>
              <th>Region</th>
              <th>Subnet</th>
            </tr>
            %{ for subnet in data.google_compute_subnetwork.regional-subnet}
            <tr>
              <td>${subnet.region}</td>
              <td>${subnet.name}</td>
            </tr>
            %{ endfor }
          </table>
        </li>
      </ul>


      <h2>All attendees emails</h2>
      <ul>
      %{ for email in local.attendees-email-list}
        <li>${email}</li>
      %{ endfor }
      </ul>
  </body>
</html>
EOT
}

resource "google_storage_bucket_object" "homepage" {
  name   = "index.html"
  content_type = "text/html"
  content = local.instructions_html
  bucket = google_storage_bucket.workshop-site.name
}
