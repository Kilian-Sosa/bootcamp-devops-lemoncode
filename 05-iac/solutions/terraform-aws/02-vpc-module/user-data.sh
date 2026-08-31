#!/bin/bash
# user_data para Amazon Linux 2023.
# Instala Docker pero NO arranca NGINX automaticamente: el ejercicio pide que
# el alumno se conecte por SSH y lance el contenedor NGINX a mano.

set -euo pipefail

# 1) Instalar Docker (Amazon Linux 2023 usa dnf).
dnf install -y docker

# 2) Habilitar e iniciar el servicio docker.
systemctl enable docker
systemctl start docker

# 3) Permitir que ec2-user use Docker sin sudo.
usermod -aG docker ec2-user
