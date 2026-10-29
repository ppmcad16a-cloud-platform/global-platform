# ---------------------------------------------------------------
# jenkins.<domain> - the door GitHub Actions uses to start
# deployments. Two locks:
#   1. Cloudflare Access (at Cloudflare's edge, before anything reaches
#      GKE): only our GitHub service token, or an admin who logs in with
#      an emailed one-time PIN.
#   2. Jenkins itself: the deploy job starts only with the secret
#      trigger token.
# ---------------------------------------------------------------

# DNS only while GKE runs (Jenkins lives in GKE).
resource "cloudflare_dns_record" "jenkins" {
  count   = contains(keys(local.ingress_ips), "gcp") ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "jenkins.${var.domain}"
  type    = "A"
  content = local.ingress_ips["gcp"]
  proxied = true
  ttl     = 1
  comment = "Jenkins in GKE - behind Cloudflare Access (terraform)"
}

# A "machine password" for GitHub Actions (valid 1 year).
resource "cloudflare_zero_trust_access_service_token" "github_ci" {
  account_id = var.cloudflare_account_id
  name       = "github-actions-deploy-trigger"
  duration   = "8760h"
}

resource "cloudflare_zero_trust_access_policy" "jenkins_ci" {
  account_id = var.cloudflare_account_id
  name       = "Jenkins - GitHub Actions (service token)"
  decision   = "non_identity" # a machine, not a person
  include = [{
    service_token = { token_id = cloudflare_zero_trust_access_service_token.github_ci.id }
  }]
}

resource "cloudflare_zero_trust_access_policy" "jenkins_admins" {
  account_id       = var.cloudflare_account_id
  name             = "Jenkins - admins (email one-time PIN)"
  decision         = "allow"
  session_duration = "8h"
  include          = [for e in var.admin_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "jenkins" {
  account_id           = var.cloudflare_account_id
  name                 = "Jenkins"
  domain               = "jenkins.${var.domain}"
  type                 = "self_hosted"
  session_duration     = "8h"
  app_launcher_visible = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.jenkins_ci.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.jenkins_admins.id, precedence = 2 },
  ]
}

# ---------------------------------------------------------------
# The secrets, kept in GCP Secret Manager (the vault next to Jenkins):
#   jenkins-trigger-token              -> Jenkins (External Secrets) + GitHub CI
#   ci-cloudflare-access-client-id/-secret -> GitHub CI only
# ---------------------------------------------------------------
resource "random_password" "jenkins_trigger" {
  length  = 40
  special = false
}

locals {
  ci_secrets = {
    "jenkins-trigger-token"              = random_password.jenkins_trigger.result
    "ci-cloudflare-access-client-id"     = cloudflare_zero_trust_access_service_token.github_ci.client_id
    "ci-cloudflare-access-client-secret" = cloudflare_zero_trust_access_service_token.github_ci.client_secret
  }
}

resource "google_secret_manager_secret" "ci" {
  for_each  = nonsensitive(toset(keys(local.ci_secrets)))
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ci" {
  for_each    = nonsensitive(toset(keys(local.ci_secrets)))
  secret      = google_secret_manager_secret.ci[each.key].id
  secret_data = local.ci_secrets[each.key]
}

# GitHub's CI robot (created in gcp-platform foundation, ci-push.tf) may read
# exactly these three secrets - nothing else in the vault.
resource "google_secret_manager_secret_iam_member" "ci_read" {
  for_each  = google_secret_manager_secret.ci
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:gha-push@${var.gcp_project_id}.iam.gserviceaccount.com"
}
