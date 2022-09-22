variable "prefix" {
  type = string
  description = "Prefix on resources created"
}
variable "tags"{
  type = map(any)
  default ={}
  description = "Tags for resources created"
}

variable "gcp-project-id" {
  type = string
  description = "Project on GCP"
}
variable "gcp-region" {
  type = string
  default = "asia-southeast1"
  description = "GCP region"
}
variable "gcs-region" {
  type = string
  default = "ASIA"
  description = "Google Cloud Storage Location Region"
}
variable "gcp_network" {
  type = string
  default = "default"
  description = "Netowrk for running VMs"
}
variable "primary-zone" {
  type = string
  default = "asia-southeast1-a"
  description = "Primary zone"
}

variable "yugaware-machine-type" {
  type = string
  description = "Yugaware Machine Type"
  default = "c2-standard-4"
}

variable "participants" {
  type =  map(list(string))
  description = "Org -> Participant EMail List Map"
}
variable "instructors" {
  type = list(string)
  description = "Email address of instructors/facilitators"
}
# variable "hosted-zone-id"{
#   type = string
#   de
# }
variable duration {
  type = number
  default = 3
  description = "Number of days to keep access"
}
