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

  value = local.instructions

}
