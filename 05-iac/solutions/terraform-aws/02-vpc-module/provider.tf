provider "aws" {
  # Standard AWS provider credential chain (env vars, shared config, SSO, IAM
  # role, etc.). Never hard-code access_key/secret_key here and never recommend
  # root-user access keys.
  region = var.aws_region
}
