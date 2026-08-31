############################################
# Application security group
############################################

# Security group is created separately from the VPC module. We use the modern
# aws_vpc_security_group_ingress_rule / egress_rule resources (no deprecated
# aws_security_group_rule, no inline ingress/egress blocks).
resource "aws_security_group" "app" {
  name        = "lemoncode-iac-app-sg"
  description = "Reglas de la aplicacion: HTTP publica + SSH restringida + egress"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "lemoncode-iac-app-sg"
  })
}

############################################
# HTTP ingress (required by the exercise)
############################################

# HTTP TCP 80 from everywhere is explicitly required by the exercise so NGINX
# can be reached on port 80.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP (TCP 80) desde cualquier IPv4 - requerido por el ejercicio"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

############################################
# SSH ingress (conditional on user's /32)
############################################

# SSH must NOT be world-open. By default ssh_cidr = null and the rule is not
# created. If create_instance = true, a precondition forces ssh_cidr != null.
# Use your own public IP in /32, e.g. 203.0.113.10/32.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count             = var.ssh_cidr == null ? 0 : 1
  security_group_id = aws_security_group.app.id
  description       = "SSH (TCP 22) solo desde la IP publica del usuario en /32"
  cidr_ipv4         = var.ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

############################################
# Egress (allow outbound for Docker installs + image pulls)
############################################

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Salida libre para instalar Docker y descargar imagenes de contenedor"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
