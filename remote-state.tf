# Each cluster stack publishes "egress_ip". When a cluster is destroyed its
# state has no outputs, so try(...) returns null and that cloud is skipped.

data "terraform_remote_state" "gcp_cluster" {
  backend = "gcs"
  config = {
    bucket = "project-899ced78-a554-40c2-96c-tfstate"
    prefix = "prod/cluster"
  }
}

data "terraform_remote_state" "azure_cluster" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateo398md"
    container_name       = "tfstate"
    key                  = "prod/cluster.tfstate"
    subscription_id      = "9c0602c2-72a4-4432-a192-7abf998e2b60"
    tenant_id            = "0fd463ca-1b22-4674-bea5-699c2e0ad98b"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "azure_foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateo398md"
    container_name       = "tfstate"
    key                  = "prod/foundation.tfstate"
    subscription_id      = "9c0602c2-72a4-4432-a192-7abf998e2b60"
    tenant_id            = "0fd463ca-1b22-4674-bea5-699c2e0ad98b"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "aws_cluster" {
  backend = "s3"
  config = {
    bucket = "ppmcad16a-tfstate-722867460821-ap-south-1"
    key    = "aws/prod/cluster/terraform.tfstate"
    region = "ap-south-1"
  }
}

locals {
  clouds = toset(["aws", "azure", "gcp"])

  # { gcp = "34.x.x.x", ... } - only the clusters that are running right now
  egress_ips = {
    for cloud, ip in {
      gcp   = try(data.terraform_remote_state.gcp_cluster.outputs.egress_ip, null)
      azure = try(data.terraform_remote_state.azure_cluster.outputs.egress_ip, null)
      aws   = try(data.terraform_remote_state.aws_cluster.outputs.egress_ip, null)
    } : cloud => ip if ip != null
  }
}
