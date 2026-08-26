############################################
# Availability Zones (dynamic selection)
############################################

# We do NOT hard-code an AZ like eu-west-1a. We feed the list of available AZs
# in the selected region into the VPC module and pick the first dynamically.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "region-name"
    values = [var.aws_region]
  }
}

############################################
# VPC module (refactor of step 8)
############################################

# This directory replaces the manually-created VPC / IGW / subnet / route table
# / route / route-table association with the official module. We deliberately
# do NOT keep duplicate manual network resources here.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1" # pinned; requires AWS provider >= 6.28

  name = "lemoncode-iac-vpc"
  cidr = var.vpc_cidr

  # Keep DNS settings explicit and identical to 01-manual-vpc for parity and
  # to document intent. The module already defaults both to true; setting them
  # explicitly guards against future upstream default changes.
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Single public subnet: pick one available AZ dynamically.
  azs            = [data.aws_availability_zones.available.names[0]]
  public_subnets = [var.public_subnet_cidr]

  # Public subnet must auto-assign public IPv4 so EC2 gets a public IP.
  map_public_ip_on_launch = true

  # Exercise explicitly forbids NAT Gateway / VPN gateway. Public subnet + IGW
  # is enough. This also avoids NAT Gateway + Elastic IP costs.
  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = local.common_tags
}
