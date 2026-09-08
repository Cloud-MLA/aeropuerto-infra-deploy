#!/bin/bash
# user-data común para las 4 EC2 (Amazon Linux 2023): instala Docker + compose plugin.
# Pegar en "Advanced details → User data" al lanzar la instancia, o incluir con include-file.
set -euxo pipefail

dnf update -y
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

# docker compose v2 como plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

docker --version
docker compose version
