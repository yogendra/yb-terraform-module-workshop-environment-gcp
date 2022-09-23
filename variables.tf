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
variable "gcp-network" {
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

variable expiry {
  type = string
  description = "YYY-MM-DDTHH:mm:ssZ formatted timestamp"
}
variable "dns-zone" {
  type = string
  description = "Hosted DNS Zone for Workshop"
}

variable "domain" {
  type = string
  description = "Root domain for workshop"
}


variable "cert-email" {
  type = string
  description = "Email for generating Lets Encrypt certificate"
}

variable license-file {
  type = string
  description = "License file absolute path"
}
