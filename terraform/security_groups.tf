# RUNBOOK.md 1.2 — mismas 5 SGs, mismas reglas, referenciadas entre sí (sin CIDRs a mano).

resource "aws_security_group" "apigw_vpclink" {
  name        = "sg-apigw-vpclink"
  description = "VPC Link de API Gateway — sin inbound propio"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-apigw-vpclink" }
}

resource "aws_security_group" "alb" {
  name        = "sg-alb"
  description = "ALB interno — recibe solo del VPC Link"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.apigw_vpclink.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-alb" }
}

resource "aws_security_group" "vm_prod" {
  name        = "sg-vm-prod"
  description = "VM-PROD-1/2 — recibe solo del ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-vm-prod" }
}

resource "aws_security_group" "vm_ingesta" {
  name        = "sg-vm-ingesta"
  description = "VM-INGESTA — sin inbound, solo sale a VM-DB y S3"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-vm-ingesta" }
}

resource "aws_security_group" "vm_db" {
  name        = "sg-vm-db"
  description = "VM-DB — recibe de VM-PROD y VM-INGESTA en los 3 puertos de motor"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [3306, 5432, 27017]
    content {
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.vm_prod.id, aws_security_group.vm_ingesta.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-vm-db" }
}
