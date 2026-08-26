############################################
# EC2 instance (cost-safe, conditional creation)
############################################

# EC2 is NOT created by default. With create_instance = false only the
# VPC/network/SG/key pair are created (Fase A). The instance is only created
# when the user explicitly sets create_instance = true (Fase B).
#
# We use count for conditional creation so the outputs can safely return null
# when no instance exists.
resource "aws_instance" "app" {
  count = var.create_instance ? 1 : 0

  ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  # SSM AMI reference: avoids a stale hard-coded AMI ID that becomes invalid
  # over time. The AWS provider resolves this to the current Amazon Linux 2023
  # x86_64 AMI at apply time. We deliberately avoid a data source lookup for
  # the AMI in the default infrastructure-only phase.

  instance_type = var.instance_type

  # Use the VPC module's public subnet output for the EC2 subnet.
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  key_name = aws_key_pair.main.key_name

  user_data = file("${path.module}/user-data.sh")

  # IMDSv2 as a small security improvement.
  metadata_options {
    http_tokens = "required"
  }

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-ec2"
  })

  # Safety precondition: if we create the instance, a restricted SSH path is
  # mandatory (step 5 requires SSH access). SSH must never fall back to
  # 0.0.0.0/0.
  lifecycle {
    precondition {
      condition     = var.ssh_cidr != null
      error_message = "create_instance = true requiere ssh_cidr != null. Configura ssh_cidr con tu IP publica en /32 (ej. 203.0.113.10/32)."
    }
  }
}
