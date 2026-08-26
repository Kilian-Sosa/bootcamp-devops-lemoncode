############################################
# Region
############################################

variable "aws_region" {
  description = "Region de AWS donde se despliega la infraestructura."
  type        = string
  default     = "eu-west-1"
}

############################################
# Networking
############################################

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && (startswith(var.vpc_cidr, "10.") || can(regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\.", var.vpc_cidr)) || startswith(var.vpc_cidr, "192.168."))
    error_message = "vpc_cidr debe ser un CIDR privado RFC1918 (10.x, 172.16-31.x o 192.168.x)."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR de la subred publica dentro de la VPC."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr)) && (startswith(var.public_subnet_cidr, "10.") || can(regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\.", var.public_subnet_cidr)) || startswith(var.public_subnet_cidr, "192.168."))
    error_message = "public_subnet_cidr debe ser un CIDR privado RFC1918."
  }
}

############################################
# Compute / cost safety
############################################

variable "create_instance" {
  description = <<-EOT
    Crea la instancia EC2 solo cuando se establece en true.
    Por defecto false para que la Fase A (pasos 1-4) no incurra en coste de compute.
    EOT
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "Tipo de instancia EC2. t3.micro por defecto (verificar Free Tier / creditos de la cuenta)."
  type        = string
  default     = "t3.micro"
}

############################################
# SSH / key pair
############################################

variable "ssh_public_key_path" {
  description = <<-EOT
    Ruta local a la clave PUBLICA SSH que se importara como aws_key_pair.
    Ejemplo: ~/.ssh/lemoncode-iac.pub
    La clave PRIVADA nunca entra en Terraform state.
    EOT
  type        = string
  default     = "~/.ssh/lemoncode-iac.pub"
}

variable "ssh_cidr" {
  description = <<-EOT
    CIDR origen permitido para SSH (TCP 22). Debe ser tu IP publica en formato /32,
    por ejemplo 203.0.113.10/32. NO usar 0.0.0.0/0.
    Si es null, no se crea la regla SSH. Si create_instance = true, es obligatorio
    que ssh_cidr != null (hay un precondition que lo garantiza).
    EOT
  type        = string
  default     = null

  # SSH is deliberately limited to one known public IP. This protects against
  # accidentally allowing broad public ranges such as 0.0.0.0/1.
  validation {
    condition     = var.ssh_cidr == null ? true : can(cidrnetmask(var.ssh_cidr)) && endswith(var.ssh_cidr, "/32")
    error_message = "ssh_cidr debe ser un CIDR IPv4 /32 con tu IP publica; no se permiten rangos amplios ni 0.0.0.0/0."
  }
}
