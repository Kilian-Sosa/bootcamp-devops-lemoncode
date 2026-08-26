output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID de la subred publica."
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID del security group de la aplicacion."
  value       = aws_security_group.app.id
}

output "key_pair_name" {
  description = "Nombre del key pair importado."
  value       = aws_key_pair.main.key_name
}

output "availability_zone" {
  description = "AZ dinamica seleccionada para la subred publica."
  value       = data.aws_availability_zones.available.names[0]
}

############################################
# EC2 outputs (null-safe when create_instance = false)
############################################

output "public_ip" {
  description = "IP publica IPv4 de la instancia EC2 (null si create_instance = false)."
  # count = 0 safe: never index instance[0] when it does not exist.
  value = var.create_instance ? aws_instance.app[0].public_ip : null
}

output "ssh_command" {
  description = "Comando SSH sugerido (null si create_instance = false)."
  # Example: ssh -i ~/.ssh/lemoncode-iac ec2-user@<PUBLIC_IP>
  value = var.create_instance ? "ssh -i ${var.ssh_public_key_path} ec2-user@${aws_instance.app[0].public_ip}" : null
}

output "http_url" {
  description = "URL HTTP para acceder a NGINX (null si create_instance = false)."
  value       = var.create_instance ? "http://${aws_instance.app[0].public_ip}" : null
}
