# Credentials: MONGODB_ATLAS_PUBLIC_KEY / MONGODB_ATLAS_PRIVATE_KEY
provider "mongodbatlas" {}

# Credentials: CLOUDFLARE_API_TOKEN
provider "cloudflare" {}

# Credentials: your gcloud application-default login
provider "google" {
  project = var.gcp_project_id
  region  = "asia-south1"
}

# Credentials: your "az login"
provider "azurerm" {
  features {}
  subscription_id                 = var.azure_subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}

# Credentials: $env:AWS_PROFILE
provider "aws" {
  region = "ap-south-1"
}
