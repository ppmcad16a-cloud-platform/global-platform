variable "gcp_project_id" {
  type    = string
  default = "project-899ced78-a554-40c2-96c"
}

variable "azure_subscription_id" {
  type    = string
  default = "9c0602c2-72a4-4432-a192-7abf998e2b60"
}

variable "atlas_project_id" {
  type    = string
  default = "6a00a473024c5dde70c31097"
}

variable "atlas_cluster_name" {
  type    = string
  default = "CapstoneProject"
}

variable "mongo_host" {
  description = "Atlas SRV host name (from the cluster's connection string)"
  type        = string
  default     = "capstoneproject.fnonccf.mongodb.net"
}

variable "db_name" {
  type    = string
  default = "mern_ecommerce"
}

variable "domain" {
  type    = string
  default = "rishavmukhopadhyay.store"
}

variable "cloudflare_zone_id" {
  type    = string
  default = "011ab0392ceae0c4b429b5e65bda72e5"
}
