locals {
  project = "apj-partner-enablement"
  prefix = "vst-sep2022"
  participants = {
    eitc = ["art.desotto@gmail.com"]
    epldt = ["ac2011coronel@gmail.com","ezlarrazabal@epldt.com"]
    exist = ["lluistro@exist.com"]
    gsiorg = ["dvd.dtnglng10@gmail.com","gorospequintin@gmail.com"]
    lynxlogic = ["arthur.palabrica@lynxlogic.ph","christine.dolores@lynxlogic.ph","kamotechque@gmail.com"]
    ptsiphil = ["joshuaaniceto@gmail.com","marc.a@ptsiphil.com"]
    solventoph = ["ramioneclintlazaga@gmail.com"]
    ssiph = ["alvinarmas.aa@gmail.com","arthlingat@gmail.com"]
    stratpoint = ["reginald.cuevillas@stratpoint.com"]
  }
  instructors = [
    "czaide@msi-ecs.com.ph",
    "dbalbastro@msi-ecs.com.ph"
  ]
  duration = 1
  expiry = "2022-09-22T16:00:00Z"
}

module "workshop" {
  source = "../tf"
  gcp-project-id = local.project
  participants = local.participants
  instructors = local.instructors
  prefix = local.prefix
  expiry = local.expiry
}

output "info" {
  value = module.workshop.info
}

output "instructions" {
  value = module.workshop.instructions
}
