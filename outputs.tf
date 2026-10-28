output "atlas_allowlisted_ips" {
  description = "Cluster egress IPs currently allowed into MongoDB Atlas"
  value       = local.egress_ips
}

output "secret_names" {
  value = sort(tolist(local.secret_names))
}

output "seed_admin_password" {
  description = "Login for the shop admin (seed job). Show with: terraform output -raw seed_admin_password"
  value       = random_password.seed_admin.result
  sensitive   = true
}

output "live_clouds" {
  value = local.live_clouds
}

output "urls" {
  value = merge(
    { shop = "https://${var.domain}" },
    { for c in keys(local.ingress_ips) : c => "https://${c}.${var.domain}" },
  )
}
