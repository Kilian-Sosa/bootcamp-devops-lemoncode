terraform {
  # Compatible with current stable Terraform 1.x without beta-only features.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AWS provider 6.x. The terraform-aws-modules/vpc/aws 6.6.1 module
      # requires AWS provider >= 6.28, so we stay on a 6.x constraint that
      # satisfies the module.
      version = "~> 6.60"
    }
  }
}
