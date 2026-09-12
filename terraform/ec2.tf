# RUNBOOK.md 1.4 — 4 EC2, sin key pair (acceso por SSM), LabInstanceProfile.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Ya existe en toda cuenta de AWS Academy Learner Lab — no se crea, solo se referencia.
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

locals {
  docker_user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    id -u ssm-user &>/dev/null || useradd -m ssm-user
    usermod -aG docker ssm-user
    echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  EOF
}

resource "aws_instance" "vm_prod" {
  count                       = 2
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.prod_instance_type
  subnet_id                   = aws_subnet.private[count.index].id
  vpc_security_group_ids      = [aws_security_group.vm_prod.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = false
  user_data                   = local.docker_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-PROD-${count.index + 1}" }
}

resource "aws_instance" "vm_db" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.vm_db.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = false
  user_data                   = local.docker_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-DB" }
}

resource "aws_instance" "vm_ingesta" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.ingesta_instance_type
  subnet_id                   = aws_subnet.private[1].id
  vpc_security_group_ids      = [aws_security_group.vm_ingesta.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = false
  user_data                   = local.docker_user_data

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "VM-INGESTA" }
}
