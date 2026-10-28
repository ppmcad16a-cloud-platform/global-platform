# "Full (strict)": Cloudflare -> cluster traffic is encrypted AND the
# cluster's certificate is verified (the origin certificate below).
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "always_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

# Origin certificate for our gateways: we create the private key ourselves
# (it never leaves Terraform + the vaults), send Cloudflare only a signing
# request (CSR), and Cloudflare signs it for 15 years.
resource "tls_private_key" "origin" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem
  subject {
    common_name  = var.domain
    organization = "ppmcad16a capstone"
  }
}

resource "cloudflare_origin_ca_certificate" "origin" {
  csr                = tls_cert_request.origin.cert_request_pem
  hostnames          = [var.domain, "*.${var.domain}"]
  request_type       = "origin-rsa"
  requested_validity = 5475

  # The API reports these fields back slightly differently (e.g. validity
  # counted down from today), which Terraform would treat as a change and
  # REPLACE the certificate - revoking the old one on every apply.
  # A certificate valid until 2041 never needs that; ignore the drift.
  lifecycle {
    ignore_changes = [requested_validity, csr]
  }
}
