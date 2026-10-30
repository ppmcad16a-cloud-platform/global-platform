# ---------------------------------------------------------------
# Stopped-standby failover, AUTOMATIC: when Cloudflare sees the PRIMARY
# (GCP) pool go unhealthy, it calls the Worker below, which starts the
# GitHub Actions workflow "failover-wake" (platform-automation). That
# workflow wakes Azure and AWS with keyless identities that may only
# start / resize them.
# The Worker holds two secrets: a GitHub token that may ONLY run workflows
# in platform-automation (stored by hand once in GCP Secret Manager), and
# the shared secret that Cloudflare's alert must present.
# ---------------------------------------------------------------
data "google_secret_manager_secret_version" "failover_github_token" {
  secret = "failover-github-token"
}

resource "random_password" "failover_webhook" {
  length  = 40
  special = false
}

resource "cloudflare_workers_script" "failover" {
  account_id         = var.cloudflare_account_id
  script_name        = "mern-failover"
  main_module        = "failover.js"
  content            = file("${path.module}/workers/failover.js")
  compatibility_date = "2025-09-01"
  bindings = [
    {
      name = "GITHUB_TOKEN"
      type = "secret_text"
      text = data.google_secret_manager_secret_version.failover_github_token.secret_data
    },
    {
      name = "WEBHOOK_SECRET"
      type = "secret_text"
      text = random_password.failover_webhook.result
    },
  ]
}

# https://mern-failover.<subdomain>.workers.dev
resource "cloudflare_workers_script_subdomain" "failover" {
  account_id       = var.cloudflare_account_id
  script_name      = cloudflare_workers_script.failover.script_name
  enabled          = true
  previews_enabled = false
}

resource "cloudflare_notification_policy_webhooks" "failover" {
  account_id = var.cloudflare_account_id
  name       = "mern-failover-worker"
  url        = "https://mern-failover.${var.workers_subdomain}.workers.dev/"
  secret     = random_password.failover_webhook.result
  depends_on = [cloudflare_workers_script_subdomain.failover]
}

# Only "the GCP pool went Unhealthy" - the standbys' pools are unhealthy all
# the time while they sleep and must NOT trigger anything. Exists only while
# GCP runs (it filters on the GCP pool's id).
resource "cloudflare_notification_policy" "failover" {
  count       = contains(keys(local.ingress_ips), "gcp") ? 1 : 0
  account_id  = var.cloudflare_account_id
  name        = "MERN shop - GCP down: wake the standbys"
  description = "Primary pool unhealthy -> Worker mern-failover -> GitHub Actions failover-wake"
  alert_type  = "load_balancing_health_alert"
  enabled     = true
  filters = {
    event_source = ["pool"]
    pool_id      = [cloudflare_load_balancer_pool.cloud["gcp"].id]
    new_health   = ["Unhealthy"]
  }
  mechanisms = {
    webhooks = [{ id = cloudflare_notification_policy_webhooks.failover.id }]
  }
}

output "failover_webhook_secret" {
  description = "Only for testing the Worker by hand: terraform output -raw failover_webhook_secret"
  value       = random_password.failover_webhook.result
  sensitive   = true
}
