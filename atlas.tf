# One strong random password per cloud. special = false: no characters
# that would have to be escaped inside a connection-string URL.
resource "random_password" "mongo" {
  for_each = local.clouds
  length   = 32
  special  = false
}

# app-aws / app-azure / app-gcp: may ONLY read and write the shop database,
# and only on our one cluster.
resource "mongodbatlas_database_user" "app" {
  for_each           = local.clouds
  project_id         = var.atlas_project_id
  auth_database_name = "admin"
  username           = "app-${each.key}"
  password           = random_password.mongo[each.key].result

  roles {
    role_name     = "readWrite"
    database_name = var.db_name
  }

  scopes {
    name = var.atlas_cluster_name
    type = "CLUSTER"
  }

  labels {
    key   = "managed-by"
    value = "terraform"
  }
}

# backup-ro: may only READ - used by the nightly backup job.
resource "random_password" "mongo_backup" {
  length  = 32
  special = false
}

resource "mongodbatlas_database_user" "backup" {
  project_id         = var.atlas_project_id
  auth_database_name = "admin"
  username           = "backup-ro"
  password           = random_password.mongo_backup.result

  roles {
    role_name     = "read"
    database_name = var.db_name
  }

  scopes {
    name = var.atlas_cluster_name
    type = "CLUSTER"
  }
}

# Network access: ONLY the fixed outgoing IP of each running cluster.
resource "mongodbatlas_project_ip_access_list" "clusters" {
  for_each   = local.egress_ips
  project_id = var.atlas_project_id
  ip_address = each.value
  comment    = "${each.key} cluster egress (terraform)"
}

locals {
  mongo_uri = {
    for c in local.clouds :
    c => "mongodb+srv://app-${c}:${random_password.mongo[c].result}@${var.mongo_host}/${var.db_name}?retryWrites=true&w=majority"
  }
  mongo_backup_uri = "mongodb+srv://backup-ro:${random_password.mongo_backup.result}@${var.mongo_host}/${var.db_name}?readPreference=secondary"
}
