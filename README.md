# Yugabyte Workshop Environment Creation - GCP

This is a terraform module for creating workshop environment. Main intention is to provide environments for hand-on practice for:

1. Deploy Replicated on VM on GCP
2. Configure Google Cloud provider (use service account credential type)
3. Create database (one or more)
4. Configure replication between database
5. Configure backups
6. Create Backup
7. Restore from Backup
8. Run sample application
9. Demonstrate node failure
10. Demonstrate scaling

This module will:

1. Add participants to project
2. Add instructors to project
3. Create Portal VM for each group/org and instructors
4. Grant access permissions to group members to their own group's Portal VM
5. Grant access to instructors to all Portal VMs
6. Create DNS record Portal VMs
7. Create Lets Encrypt certificate to use with the portals
8. Create Backup buckets
9. Create service account with access to compute and backup buckets
10. Create key for service account
11. Create a Landing page for workshop attendees to get License, certs, VM info etc.
12. Setup access expiry for participants

## Pre-requisites

Administrator - Creator of workshop environment

1. Google cloud project
2. Terraform
3. google-cloud-sdk
4. Domain with Hosted Zone on GCP (Get free domain at [freenom](https://freenom.com))
5. Verified domain with google

Instructors - Conductors of workshop

1. Yugabyte Trial License
2. Zoom Session (Required if conducting online)
3. Google account (Emails provided should be of a valid Google account. )
4. (highly recommended) Workstation with working `gcloud`
5. Browser
6. DBeaver or any other Postgres compatible SQL Tool
7. Putty (recommended)
8. Java (17 or higher)

Participants

1. Google account (Emails provided should be of a valid Google account. )
2. (highly recommended) Workstation with working `gcloud`
3. Browser
4. DBeaver or any other Postgres compatible SQL Tool
5. Putty (recommended)
6. Java (17 or higher)

## Quick Start

Create a terraform file with following content

```hcl
module "workshop" {
  source = "github.com/yogendra/yb-terraform-module-workshop-environment-gcp"
  gcp-project-id = "project-id"
  participants = {
    org1 = [ "participant1@org1.com","participant2@org1.com" ]
    org2 = [ "participant3@org2.com","participant4@org2.com", "participant5@org3.com"]
  }
  instructors = [
    "instructor1@org3.com","instructor2@org3.com"
  ]
  prefix = "ws01"
  expiry = "2022-09-23T00:00:00Z"
  domain = "workshops.example.com"
  dns-zone = "hosted-dns-zone-name"
  cert-email = "mymail@myorg.com"
  license-file = "/path/to/license-file.rli"

}

output "instructions" {
  value = module.workshop.instructions-url
}

```

- `participant` - a map of org name (dns naming compatible, lowercase, number and hyphens only) and participant email list. They can access machine only assigned to them.
- `instructor` - list of emails for instructors. They have access to all the Machines for workshop

## Important: Refresh Terraform during Workshop

In case you need to add more participants or make any change, please refresh the state first before making the change and applying.
Mainly the ssh keys get added to machines' metadata for users and you don't want to wipe them out

```bash
# Refresh state
terraform apply -refresh-only -auto-approve
```

This will output set of instructions that you can email to instructors and participants

## TODO

1. Add workshop script to follow
2. Prepare yugaware nodes with required tools (yugabyte binary, nc, curl, wget, etc.)
