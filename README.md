# global-platform

Terraform for everything that sits **above** the three clouds and ties them together: the public domain and global load balancer (Cloudflare), the shared database access (MongoDB Atlas), the application secrets written into all three cloud vaults, and the automatic failover trigger.

**Terraform** 1.16 · **Providers:** Cloudflare, MongoDB Atlas, Google, AzureRM, AWS · **Remote state:** GCS `<gcp-project>-tfstate/global`

## What it manages

| File | Resources |
|---|---|
| `cloudflare.tf` | zone settings: SSL **Full (strict)**, *Always use HTTPS*, minimum TLS 1.2; Origin CA certificate for the clusters |
| `loadbalancer.tf` | health monitor `GET /api/health`, one pool per cloud, load balancer on the apex domain with **failover order gcp → azure → aws**, DNS records `gcp.` / `azure.` / `aws.` |
| `failover.tf` | Worker `mern-failover` + notification policy: when the **gcp** pool turns unhealthy, the Worker starts the `failover-wake` GitHub workflow that wakes the standbys |
| `observability.tf` | `grafana.` (central Grafana) and `obs-azure.` / `obs-aws.` (its read-only data sources) behind Cloudflare Access with service tokens, Slack webhook copied to all vaults, Cloudflare pool-health notifications to Slack |
| `jenkins-access.tf` | `jenkins.` DNS record (only while GKE runs), Cloudflare Access application and policies, service token for GitHub Actions, CI secrets |
| `atlas.tf` | one Atlas database user per cloud (`readWrite` on `mern_ecommerce` only), read-only `backup-ro`, IP access list with each cluster's fixed egress IP |
| `secrets.tf` | shared `JWT_SECRET`, seed admin password, per-cloud MongoDB URI, origin TLS — written into GCP Secret Manager, Azure Key Vault and AWS SSM `/mern/*` |
| `dr.tf` | copies the backup decryption key to Key Vault and SSM (outside `/mern/`); `restore-drill` Atlas user limited to the scratch database |
| `remote-state.tf` | reads the cluster stacks of the three cloud repos (ingress and egress IPs) |

## Dependencies

| Depends on | For |
|---|---|
| [gcp-platform](https://github.com/ppmcad16a-cloud-platform/gcp-platform), [azure-platform](https://github.com/ppmcad16a-cloud-platform/azure-platform), [aws-platform](https://github.com/ppmcad16a-cloud-platform/aws-platform) | cluster ingress/egress IPs (remote state); the vaults created by their foundation stacks |
| GCP Secret Manager (set once by hand) | `mern-slack-webhook-url`, `mern-backup-age-key`, `failover-github-token` |
| [platform-automation](https://github.com/ppmcad16a-cloud-platform/platform-automation) | its `failover-wake.yml` workflow is what the Worker starts |

| Used by | For |
|---|---|
| all clusters | read their secrets from their own vault through External Secrets |
| [core-cloud-platform](https://github.com/ppmcad16a-cloud-platform/core-cloud-platform) `trigger-deploy.yaml` | reads the Jenkins Access token and trigger token |

## Usage

Applied by `platform-automation` (`up.yml`: create/update only; `down.yml`: delete/update only). By hand:

```bash
read -rsp "Cloudflare API token: " CLOUDFLARE_API_TOKEN; echo; export CLOUDFLARE_API_TOKEN
read -rsp "Atlas public key: " MONGODB_ATLAS_PUBLIC_KEY; echo; export MONGODB_ATLAS_PUBLIC_KEY
read -rsp "Atlas private key: " MONGODB_ATLAS_PRIVATE_KEY; echo; export MONGODB_ATLAS_PRIVATE_KEY
cat > terraform.tfvars <<EOF        # git-ignored
admin_emails      = ["you@example.com"]
workers_subdomain = "<your-workers-subdomain>"
EOF
terraform init && terraform plan && terraform apply
```

Account identifiers (Cloudflare zone/account, Atlas project, domain, GCP project, Azure subscription) are variables with this project's defaults in `variables.tf`.

## Rules

* No secret values in git: provider tokens are typed in per session; generated values go straight into the vaults.
* The Atlas API key has its own IP access list — add your current IP there before applying.
* A perpetual "update" of `cloudflare_notification_policy_webhooks.slack` is provider behaviour and harmless.
