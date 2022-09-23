# Yugabyte Workshop Environment Creation - GCP

This is a terraform module for creating workshop environment. Main intension is to provide environment for hand-on practice for:

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


## Pre-requisites

Administrator - Creator of workshop environment

1. Google cloud project
2. Terraform
3. google-cloud-sdk

Instructors - Conductors of workshop

1. Yugabyte Trial License
2. Zoom Session (Required if conducting online)

Participants

1. (highly recommended) Workstation with working `gcloud`
2. Browser
3. DBeaver or any other Postgres compatible SQL Tool
4. Putty (recommended)
5. Java (17 or higher)

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
}

output "instructions" {
  value = module.workshop.instructions
}

```

`participant` - a map of org name (dns naming compatible, lowercase, number and hyphens only) and participant email list. They can access machine only assigned to them.
`instructor` - list of emails for instructors. They have access to all the Machines for workshop

This will output set of instructions that you can email to instructors and participants

## TODO

1. Add workshop script to follow
2. Prepare yugaware nodes with required tools (yugabyte binary, nc, curl, wget, etc.)
