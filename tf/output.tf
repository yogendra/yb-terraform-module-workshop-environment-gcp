output "attendees-email-list"{
  value = local.attendees-email-list
}
output "info" {

  value = tomap({
    for org, emails in var.participants :
      org => {
        vm = google_compute_instance.yugaware[org].name,
        emails = emails,
        ssh = "gcloud compute ssh ${google_compute_instance.yugaware[org].name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap "
      }
  })
}

output "instructions" {

  value = <<EOT
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

Instructors:
============
%{ for email in var.instructors }- ${email}
%{ endfor}

Participant & Their VMs:
========================

%{ for org, emails in var.participants }
  Organization: ${org}
  VM: ${google_compute_instance.yugaware[org].name}
  Bucket: ${google_storage_bucket.backup-bucket[org].name}
  Email: ${join(",", emails)}
  SSH Command: gcloud compute ssh ${google_compute_instance.yugaware[org].name} --project ${var.gcp-project-id} --zone ${var.primary-zone} --tunnel-through-iap
%{ endfor}


All Attendees Email: ${join(", ", local.attendees-email-list)}
EOT

}
