# ---------------------------------------------------------------
# Observability across the three clouds.
#   - Slack webhook: stored ONCE by hand in GCP Secret Manager
#     (docs/09), copied from there into Azure Key Vault and AWS SSM,
#     so every cluster's Alertmanager can post to Slack.
#   - grafana.<domain>: the central Grafana in GKE - admins only.
#   - obs-azure.<domain>, obs-aws.<domain>: Prometheus + Loki of the
#     other clusters - ONLY with the central Grafana's service token.
#   - Cloudflare itself posts to Slack when a cloud's pool changes
#     health (works even when that whole cloud is gone).
# ---------------------------------------------------------------

# ---------- Slack webhook: one source, three vaults
data "google_secret_manager_secret_version" "slack_webhook" {
  secret = "mern-slack-webhook-url"
}

locals {
  slack_webhook_url = data.google_secret_manager_secret_version.slack_webhook.secret_data
}

resource "azurerm_key_vault_secret" "slack_webhook" {
  name         = "mern-slack-webhook-url"
  value        = local.slack_webhook_url
  key_vault_id = data.azurerm_key_vault.mern.id
}

resource "aws_ssm_parameter" "slack_webhook" {
  name        = "/mern/mern-slack-webhook-url"
  type        = "SecureString"
  value       = local.slack_webhook_url
  description = "Managed by global-platform Terraform (source: GCP Secret Manager)"
}

# ---------- Cloudflare -> Slack when a cloud's pool goes unhealthy / recovers
resource "cloudflare_notification_policy_webhooks" "slack" {
  account_id = var.cloudflare_account_id
  name       = "slack-mern-alerts"
  url        = local.slack_webhook_url
}

resource "cloudflare_notification_policy" "pool_health" {
  account_id  = var.cloudflare_account_id
  name        = "MERN shop - cloud pool health changed"
  description = "The gcp/azure/aws pool of the shop load balancer went unhealthy or recovered"
  alert_type  = "load_balancing_health_alert"
  enabled     = true
  mechanisms = {
    webhooks = [{ id = cloudflare_notification_policy_webhooks.slack.id }]
  }
}

# ---------- Access: who may open Grafana and the backends
resource "cloudflare_zero_trust_access_policy" "admins" {
  account_id       = var.cloudflare_account_id
  name             = "Admins (email one-time PIN)"
  decision         = "allow"
  session_duration = "8h"
  include          = [for e in var.admin_emails : { email = { email = e } }]
}

# The central Grafana's "machine password" for the other clusters' backends.
resource "cloudflare_zero_trust_access_service_token" "grafana" {
  account_id = var.cloudflare_account_id
  name       = "grafana-datasources"
  duration   = "8760h"
}

resource "cloudflare_zero_trust_access_policy" "grafana_datasources" {
  account_id = var.cloudflare_account_id
  name       = "Observability backends - central Grafana (service token)"
  decision   = "non_identity"
  include = [{
    service_token = { token_id = cloudflare_zero_trust_access_service_token.grafana.id }
  }]
}

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id           = var.cloudflare_account_id
  name                 = "Grafana"
  domain               = "grafana.${var.domain}"
  type                 = "self_hosted"
  session_duration     = "8h"
  app_launcher_visible = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.admins.id, precedence = 1 },
  ]
}

resource "cloudflare_zero_trust_access_application" "obs" {
  for_each             = toset(["azure", "aws"])
  account_id           = var.cloudflare_account_id
  name                 = "Observability backend - ${each.key}"
  domain               = "obs-${each.key}.${var.domain}"
  type                 = "self_hosted"
  session_duration     = "8h"
  app_launcher_visible = false
  policies = [
    { id = cloudflare_zero_trust_access_policy.grafana_datasources.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.admins.id, precedence = 2 },
  ]
}

# ---------- DNS (only for clouds that are running)
locals {
  observability_dns = merge(
    { for c, ip in local.ingress_ips : "obs-${c}" => ip if c != "gcp" },
    contains(keys(local.ingress_ips), "gcp") ? { grafana = local.ingress_ips["gcp"] } : {},
  )
}

resource "cloudflare_dns_record" "observability" {
  for_each = local.observability_dns
  zone_id  = var.cloudflare_zone_id
  name     = "${each.key}.${var.domain}"
  type     = "A"
  content  = each.value
  proxied  = true
  ttl      = 1
  comment  = "Phase 9 observability - behind Cloudflare Access (terraform)"
}

# ---------- The service token, for the central Grafana (read by GKE External Secrets)
locals {
  grafana_secrets = {
    "grafana-cf-access-client-id"     = cloudflare_zero_trust_access_service_token.grafana.client_id
    "grafana-cf-access-client-secret" = cloudflare_zero_trust_access_service_token.grafana.client_secret
  }
}

resource "google_secret_manager_secret" "grafana" {
  for_each  = nonsensitive(toset(keys(local.grafana_secrets)))
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "grafana" {
  for_each    = nonsensitive(toset(keys(local.grafana_secrets)))
  secret      = google_secret_manager_secret.grafana[each.key].id
  secret_data = local.grafana_secrets[each.key]
}
