# global-platform

Terraform for the things that sit **above** the three clouds and are shared by all of them.

> **In plain words:** AWS, Azure and GCP each run a full copy of the shop. This repo manages the
> pieces that tie the three copies together: the public domain name, the load balancer that sends
> each visitor to a healthy cloud, and the shared MongoDB Atlas database access.

## What lives here (Phase 5)

| Area | Resources |
|---|---|
| **Cloudflare** (`rishavmukhopadhyay.store`) | DNS records, Load Balancer with one pool per cloud + `/api/health` monitor, Origin CA certificates, Cloudflare Access apps for Jenkins / Grafana / Prometheus |
| **MongoDB Atlas** | One least-privilege DB user per cloud (`app-aws`, `app-azure`, `app-gcp`) + read-only `backup-ro`, IP allow-list with each cloud's static egress IP |
| **Shared app secrets** | `JWT_SECRET` (must be identical in every cloud), written into each cloud's vault |

## Rules

- No secret values in this repo. Provider credentials come from the CI identity; generated values go
  straight into the cloud vaults.
- Changes go through a pull request: `terraform plan` on the PR, `apply` only after approval.
