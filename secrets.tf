resource "random_password" "jwt" {
  length  = 64 # must be >= 32 for identity-service; IDENTICAL in all clouds
  special = false
}

resource "random_password" "seed_admin" {
  length  = 24
  special = false
}

locals {
  # Same secret NAMES in every cloud, so Kubernetes manifests are identical.
  secret_names = toset([
    "mern-mongo-uri",
    "mern-jwt-secret",
    "mern-seed-admin-password",
    "mern-origin-tls-crt",
    "mern-origin-tls-key",
  ])

  # The VALUES differ per cloud only for the database URI (own user per cloud).
  secret_values = {
    for c in local.clouds : c => {
      "mern-mongo-uri"           = local.mongo_uri[c]
      "mern-jwt-secret"          = random_password.jwt.result
      "mern-seed-admin-password" = random_password.seed_admin.result
      "mern-origin-tls-crt"      = cloudflare_origin_ca_certificate.origin.certificate
      "mern-origin-tls-key"      = tls_private_key.origin.private_key_pem
    }
  }
}

# ---------- AWS: SSM Parameter Store (SecureString = encrypted, free tier)
resource "aws_ssm_parameter" "mern" {
  for_each    = local.secret_names
  name        = "/mern/${each.key}"
  type        = "SecureString"
  value       = local.secret_values["aws"][each.key]
  description = "Managed by global-platform Terraform"
}

# ---------- GCP: Secret Manager
resource "google_secret_manager_secret" "mern" {
  for_each  = local.secret_names
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "mern" {
  for_each    = local.secret_names
  secret      = google_secret_manager_secret.mern[each.key].id
  secret_data = local.secret_values["gcp"][each.key]
}

# The backup job runs in GKE (Jenkins), so only GCP gets the read-only URI.
resource "google_secret_manager_secret" "mongo_backup_uri" {
  secret_id = "mern-mongo-backup-uri"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "mongo_backup_uri" {
  secret      = google_secret_manager_secret.mongo_backup_uri.id
  secret_data = local.mongo_backup_uri
}

# ---------- Azure: Key Vault (created in Phase 4 foundation)
data "azurerm_key_vault" "mern" {
  name                = data.terraform_remote_state.azure_foundation.outputs.key_vault_name
  resource_group_name = "rg-prod-foundation"
}

resource "azurerm_key_vault_secret" "mern" {
  for_each     = local.secret_names
  name         = each.key
  value        = local.secret_values["azure"][each.key]
  key_vault_id = data.azurerm_key_vault.mern.id
}
