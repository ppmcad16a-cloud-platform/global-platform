# ---------------------------------------------------------------
# disaster-recovery secrets.
#
# age private key (decrypts backups): stored ONCE by hand in GCP Secret
# Manager and copied to Azure Key Vault + AWS SSM, so a backup can be
# restored even if GCP is completely gone. Only the restore drill (and a
# human restoring by hand) ever reads it. The backup job knows only the
# PUBLIC key: it can write backups, never read them.
#
# AWS: NOT under /mern/ - the clusters' External Secrets may read
# everything under /mern/, and no cluster should ever get this key.
# ---------------------------------------------------------------
data "google_secret_manager_secret_version" "age_key" {
  secret = "mern-backup-age-key"
}

resource "azurerm_key_vault_secret" "age_key" {
  name         = "mern-backup-age-key"
  value        = data.google_secret_manager_secret_version.age_key.secret_data
  key_vault_id = data.azurerm_key_vault.mern.id
}

resource "aws_ssm_parameter" "age_key" {
  name        = "/mern-dr/backup-age-key"
  type        = "SecureString"
  value       = data.google_secret_manager_secret_version.age_key.secret_data
  description = "age private key for MERN backups (source: GCP Secret Manager)"
}

# ---------------------------------------------------------------
# restore-drill: may read/write ONLY the scratch database
# mern_restore_drill - never the shop's real data.
# ---------------------------------------------------------------
resource "random_password" "mongo_restore_drill" {
  length  = 32
  special = false
}

resource "mongodbatlas_database_user" "restore_drill" {
  project_id         = var.atlas_project_id
  auth_database_name = "admin"
  username           = "restore-drill"
  password           = random_password.mongo_restore_drill.result

  roles {
    role_name     = "readWrite"
    database_name = "mern_restore_drill"
  }

  scopes {
    name = var.atlas_cluster_name
    type = "CLUSTER"
  }
}

resource "google_secret_manager_secret" "restore_drill_uri" {
  secret_id = "mern-mongo-restore-drill-uri"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "restore_drill_uri" {
  secret      = google_secret_manager_secret.restore_drill_uri.id
  secret_data = "mongodb+srv://restore-drill:${random_password.mongo_restore_drill.result}@${var.mongo_host}/mern_restore_drill?retryWrites=true&w=majority"
}
