# RUNBOOK.md 1.4 — 4 EC2, sin key pair (acceso por SSM), LabInstanceProfile.
# AMI: Cloud9 Ubuntu 22 (var.ami_id) — la misma usada a mano en consola, privada de la
# cuenta (no resoluble por filtro de nombre público, por eso va fija por ID).
#
# Cada instancia recibe por user_data su docker-compose.yml, .env y (VM-PROD) nginx.conf ya
# rellenos, e intenta levantar los contenedores sola al arrancar. VM-DB y VM-INGESTA usan
# imágenes que ya existen en Docker Hub, así que quedan arriba. VM-PROD depende de MS1..5,
# que todavía no están publicados — esa parte falla en silencio al primer boot y se reintenta
# después con scripts/deploy-apps.sh (sin tener que recrear la instancia).
#
# NOTA sobre estos heredocs: el contenido va pegado al margen izquierdo (sin indentar) a
# propósito. Terraform recorta la indentación de un heredoc `<<-` según la del delimitador
# de cierre; si el contenido quedara indentado, esa indentación se filtraría dentro de los
# archivos .env generados (rompería el parseo de MYSQL_ROOT_PASSWORD/etc.) y de los propios
# .yml/.conf incrustados. Al margen izquierdo, el recorte es 0 y no hay ese riesgo.

# Ya existe en toda cuenta de AWS Academy Learner Lab — no se crea, solo se referencia.
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

locals {
  # Parte común: Docker + SSM + libera puertos 80/3306 que la AMI de Cloud9 trae ocupados
  # por apache2/mysql nativos (RUNBOOK 1.4).
  base_setup = <<-EOF
apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
usermod -aG docker ubuntu
id -u ssm-user &>/dev/null || useradd -m ssm-user
usermod -aG docker ssm-user
echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

systemctl stop apache2.service mysql.service || true
systemctl disable apache2.service mysql.service || true
EOF

  # --- VM-DB -------------------------------------------------------------

  vm_db_env = <<-EOT
MYSQL_ROOT_PASSWORD=${var.db_mysql_root_password}
POSTGRES_PASSWORD=${var.db_postgres_password}
EOT

  vm_db_user_data = <<-EOF
#!/bin/bash
${local.base_setup}

mkdir -p /opt/db && cd /opt/db
cat > docker-compose.yml <<'COMPOSE'
${file("${path.module}/../compose/vm-db/docker-compose.yml")}
COMPOSE
cat > .env <<'ENVFILE'
${local.vm_db_env}
ENVFILE

docker compose up -d
EOF

  # --- VM-PROD -------------------------------------------------------------

  vm_prod_env = <<-EOT
DB_HOST=${aws_instance.vm_db.private_ip}
MYSQL_ROOT_PASSWORD=${var.db_mysql_root_password}
POSTGRES_PASSWORD=${var.db_postgres_password}
ATHENA_OUTPUT=s3://${var.bucket_name}/athena-results/
TAG_MS1=${var.tag_ms1}
TAG_MS2=${var.tag_ms2}
TAG_MS3=${var.tag_ms3}
TAG_MS4=${var.tag_ms4}
TAG_MS5=${var.tag_ms5}
TAG_SWAGGER=${var.tag_swagger}
EOT

  # nginx sin swagger-aggregator por defecto: si se activa el upstream sin que la imagen
  # exista en Docker Hub, nginx no arranca para NINGÚN microservicio.
  vm_prod_nginx_conf = (
    var.enable_swagger_aggregator
    ? file("${path.module}/../nginx/nginx-with-swagger.conf")
    : file("${path.module}/../nginx/nginx.conf")
  )

  vm_prod_services = "nginx ms1 ms2 ms3 ms4 ms5${var.enable_swagger_aggregator ? " swagger-aggregator" : ""}"

  vm_prod_user_data = <<-EOF
#!/bin/bash
${local.base_setup}

mkdir -p /opt/prod && cd /opt/prod
cat > docker-compose.yml <<'COMPOSE'
${file("${path.module}/../compose/vm-prod/docker-compose.yml")}
COMPOSE
cat > nginx.conf <<'NGINX'
${local.vm_prod_nginx_conf}
NGINX
cat > .env <<'ENVFILE'
${local.vm_prod_env}
ENVFILE

# MS1..MS5 (y swagger, si está activo) pueden no existir todavía en Docker Hub — no
# bloquea el arranque de la instancia. Reintentar con scripts/deploy-apps.sh una vez
# publicadas las imágenes, sin recrear la VM.
docker compose pull ${local.vm_prod_services} || true
docker compose up -d ${local.vm_prod_services} || true
EOF

  # --- VM-INGESTA ----------------------------------------------------------
  # compose/vm-ingesta/docker-compose.yml es un placeholder (ver ese archivo) — reemplázalo
  # cuando el equipo de Data tenga el compose real de aeropuerto-data-science/ingesta/.

  vm_ingesta_env = <<-EOT
DB_HOST=${aws_instance.vm_db.private_ip}
S3_BUCKET=${var.bucket_name}
EOT

  vm_ingesta_user_data = <<-EOF
#!/bin/bash
${local.base_setup}

mkdir -p /opt/ingesta && cd /opt/ingesta
cat > docker-compose.yml <<'COMPOSE'
${file("${path.module}/../compose/vm-ingesta/docker-compose.yml")}
COMPOSE
cat > .env <<'ENVFILE'
${local.vm_ingesta_env}
ENVFILE

docker compose up -d
EOF
}

resource "aws_instance" "vm_prod" {
  count                       = 2
  ami                         = var.ami_id
  instance_type               = var.prod_instance_type
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.vm_prod.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = true
  user_data                   = local.vm_prod_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-PROD-${count.index + 1}" }
}

resource "aws_instance" "vm_db" {
  ami                         = var.ami_id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.vm_db.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = false
  user_data                   = local.vm_db_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-DB" }
}

resource "aws_instance" "vm_ingesta" {
  ami                         = var.ami_id
  instance_type               = var.ingesta_instance_type
  subnet_id                   = aws_subnet.private[1].id
  vpc_security_group_ids      = [aws_security_group.vm_ingesta.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = false
  user_data                   = local.vm_ingesta_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-INGESTA" }
}
