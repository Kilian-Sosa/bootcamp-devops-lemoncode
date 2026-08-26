############################################
# Key pair (import public key only)
############################################

# We import an existing LOCAL PUBLIC key. We do NOT use tls_private_key, so no
# private key material is ever written to Terraform state.
# The user generates the key locally, e.g.:
#   ssh-keygen -t ed25519 -f ~/.ssh/lemoncode-iac
# and we register only the .pub path here.
resource "aws_key_pair" "main" {
  key_name   = "lemoncode-iac-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = local.common_tags
}
