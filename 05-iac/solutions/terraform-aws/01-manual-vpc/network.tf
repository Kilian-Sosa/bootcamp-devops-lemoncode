############################################
# Availability Zones (dynamic selection)
############################################

# We do NOT hard-code an AZ like eu-west-1a. We list available AZs in the
# selected region and pick the first one dynamically.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "region-name"
    values = [var.aws_region]
  }
}

############################################
# VPC
############################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-vpc"
  })
}

############################################
# Internet Gateway
############################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-igw"
  })
}

############################################
# Public subnet
############################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-public-subnet"
    Tier = "public"
  })
}

############################################
# Public route table + default route + association
############################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-public-rt"
  })
}

# 0.0.0.0/0 -> Internet Gateway. A public subnet + IGW is enough for this
# exercise. We deliberately do NOT create a NAT Gateway.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
