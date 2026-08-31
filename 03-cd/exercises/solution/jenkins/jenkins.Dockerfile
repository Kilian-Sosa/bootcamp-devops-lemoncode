# ---------------------------------------------------------------------------
# jenkins.Dockerfile
#
# Imagen de Jenkins lista para Docker-in-Docker (DinD) en lugar de montar
# el socket del demonio Docker del host.
#
# Arquitectura:
#   - Un contenedor `docker:dind` (dind) expone un demonio Docker a traves de
#     TLS.
#   - Este contenedor Jenkins lleva el cliente Docker CLI y los plugins
#     necesarios para que la pipeline declarativa use un `agent { docker {...} }`.
#
# Plugins instalados (IDs exactos):
#   - docker          (plugin "Docker")
#   - docker-workflow (plugin "Docker Pipeline")
#   - docker-plugin   (plugin "Docker", aporta el tipo de agente Docker)
#
# Se usa jenkins-plugin-cli para una instalacion reproducible y versionada
# en lugar de instalar a mano desde la UI.
# ---------------------------------------------------------------------------

FROM jenkins/jenkins:lts-jdk17

USER root

# Cliente Docker CLI: necesario para que Jenkins hable con el demonio DinD.
# Usamos el paquete estatico oficial para no depender de la version de apt.
ARG DOCKER_VERSION=24.0.7
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && install -d /usr/local/lib/docker/cli-plugins /etc/docker \
    && curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && chmod +x /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Plugins requeridos por el ejercicio 2.
#   docker-workflow -> "Docker Pipeline" (sintaxis agent { docker {...} })
#   docker-plugin   -> "Docker"
# Las dependencias (docker-commons, etc.) se resuelven automaticamente.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Desactiva el asistente de instalacion inicial para acelerar la puesta
# en marcha del ejercicio local.
ENV JENKINS_OPTS="-Djenkins.install.runSetupWizard=false"

USER jenkins
