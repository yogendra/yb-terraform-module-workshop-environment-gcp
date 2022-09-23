# Yugabyte Partner Workshop Environment Creation - GCP

Create a terraform file with following content

```hcl
module "workshop" {
  source = "github.com/yogendra/yb-partner-workshop-gcp"
  gcp-project-id = "project-id"
  participants = [
    org1 = [ "participant1@org1.com","participant2@org1.com" ]
    org2 = [ "participant3@org2.com","participant4@org2.com", "participant5@org3.com"]
  ]
  instructors = [
    "instructor1@org3.com","instructor2@org3.com"
  ]
  prefix = "ws01"
  duration = 1
  expiry = "2022-09-23T00:00:00Z"
}

output "instructions" {
  value = module.workshop.instructions
}

```

`participant` - a map of org name (dns naming compatible, lowercase, number and hyphens only) and participant email list. They can access machine only assigned to them.
`instructor` - list of emails for instructors. They have access to all the Machines for workshop
