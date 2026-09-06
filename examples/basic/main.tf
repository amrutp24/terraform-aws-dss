# The smallest thing that produces a running DSS.
#
# Configuring what is inside it is a second root configuration; see the module
# README for why that cannot be the same apply.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "dss" {
  source = "../../"

  region = var.region

  # No default: DSS should not become reachable from the internet by accident.
  allowed_cidr_blocks = var.allowed_cidr_blocks
}

output "dss_url" {
  description = "Where DSS answers once it has finished installing, which takes several minutes on first boot."
  value       = module.dss.dss_url
}
