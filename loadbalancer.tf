# ---------------------------------------------------------------
# Direct per-cloud entrances: gcp./azure./aws.rishavmukhopadhyay.store
# proxied = true -> visitors still go through Cloudflare (TLS, protection),
# and the cluster only accepts Cloudflare's IPs anyway.
# ---------------------------------------------------------------
resource "cloudflare_dns_record" "cloud" {
  for_each = local.ingress_ips
  zone_id  = var.cloudflare_zone_id
  name     = "${each.key}.${var.domain}"
  type     = "A"
  content  = each.value
  proxied  = true
  ttl      = 1 # 1 = "automatic" (required for proxied records)
  comment  = "Direct entrance to the ${each.key} cluster (terraform)"
}

# ---------------------------------------------------------------
# Health check: HTTPS GET /api/health must return 200.
# Host header = our domain, so the cluster's route matches.
# ---------------------------------------------------------------
resource "cloudflare_load_balancer_monitor" "health" {
  account_id     = var.cloudflare_account_id
  description    = "MERN shop deep health check (terraform)"
  type           = "https"
  method         = "GET"
  path           = "/api/health"
  port           = 443
  expected_codes = "200"
  interval       = 60 # seconds between checks
  timeout        = 5
  retries        = 2 # 2 failed checks -> pool marked unhealthy
  header = {
    "Host" = [var.domain]
  }
}

# One pool per cloud that has a cluster (running OR asleep), each with that
# cloud's front-door IP. A sleeping cluster's pool is simply unhealthy.
resource "cloudflare_load_balancer_pool" "cloud" {
  for_each        = local.ingress_ips
  account_id      = var.cloudflare_account_id
  name            = "mern-${each.key}"
  description     = "${each.key} cluster front door (terraform)"
  monitor         = cloudflare_load_balancer_monitor.health.id
  minimum_origins = 1
  origins = [
    {
      name    = each.key
      address = each.value
      enabled = true
      weight  = 1
    },
  ]
}

# The load balancer ON the domain itself. Only exists while at least one
# cluster is running.
resource "cloudflare_load_balancer" "shop" {
  count       = length(local.live_clouds) > 0 ? 1 : 0
  zone_id     = var.cloudflare_zone_id
  name        = var.domain
  description = "MERN shop across GCP / Azure / AWS (terraform)"
  proxied     = true

  default_pools = [for c in local.live_clouds : cloudflare_load_balancer_pool.cloud[c].id]
  fallback_pool = cloudflare_load_balancer_pool.cloud[local.live_clouds[0]].id

  # FAILOVER, not sharing: every visitor goes to the FIRST healthy pool in
  # default_pools - GCP (primary), then Azure, then AWS (standbys that sleep
  # until GCP fails and they are woken; see platform-automation wake.yml).
  steering_policy = "off"

  # A visitor keeps going to the same cloud (cookie), important for the
  # Socket.IO support chat whose state lives in one cluster.
  session_affinity = "cookie"
}
