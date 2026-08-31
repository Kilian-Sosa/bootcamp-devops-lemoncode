############################################
# Amazon Linux 2023 AMI
############################################

# AWS publishes the latest AL2023 AMI ID through a public SSM parameter.
# Resolve it explicitly so aws_instance receives a real ami-* ID.
data "aws_ssm_parameter" "al2023_ami" {
  count = var.create_instance ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_instance" "app" {
  count = var.create_instance ? 1 : 0

  ami = data.aws_ssm_parameter.al2023_ami[0].value
  # SSM AMI reference: avoids a stale hard-coded AMI ID that becomes invalid
  # over time. The AWS provider resolves this to the current Amazon Linux 2023
  # x86_64 AMI at apply time. We deliberately avoid a data source lookup for
  # the AMI in the default infrastructure-only phase.

  instance_type = var.instance_type

  # T3 instances default to Unlimited CPU credits, which can incur additional
  # usage. Standard mode is sufficient for this short training workload.
  credit_specification {
    cpu_credits = "standard"
  }

  # Keep the root disk deliberately small and predictable for the lab.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  subnet_id                   = aws_subnet.public.id
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
