variable "aws_region" {
  description = "Región del Learner Lab (la única garantizada)."
  type        = string
  default     = "us-east-1"
}

variable "frontend_origin" {
  description = "Origen HTTPS exacto del frontend en Amplify, sin barra final; actualizar si se recrea la app."
  type        = string
  default     = "https://main.d6qmhb5ipm8l2.amplifyapp.com"
}

variable "azs" {
  description = "AZs a usar (2, una por subred pública/privada)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "ami_id" {
  description = "AMI Cloud9 Ubuntu 22 usada a mano en el Learner Lab (RUNBOOK 1.4) — privada de la cuenta, se busca por ID en EC2 > Browse more AMIs > Owned by me / Private images, no por filtro de nombre."
  type        = string
  default     = "ami-01112e374e42e3f3c"
}

variable "bucket_name" {
  description = "Bucket S3 del data lake. Debe ser único globalmente — cambiar si ya existe."
  type        = string
  default     = "mla-aeropuerto-lake"
}

variable "prod_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ingesta_instance_type" {
  type    = string
  default = "t3.small"
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "alb_health_check_path" {
  type    = string
  default = "/api/pasajeros/health"
}

# --- Contenedores (automatización BE-INT-03/04) -----------------------------

variable "db_mysql_root_password" {
  description = "MYSQL_ROOT_PASSWORD de VM-DB. Sin '$', '\\', comillas ni backticks (ver RUNBOOK 1.6). Poner en terraform.tfvars, no tiene default."
  type        = string
  sensitive   = true
}

variable "db_postgres_password" {
  description = "POSTGRES_PASSWORD de VM-DB. Mismas restricciones que db_mysql_root_password. Poner en terraform.tfvars, no tiene default."
  type        = string
  sensitive   = true
}

variable "tag_ms1" {
  type    = string
  default = "latest"
}

variable "tag_ms2" {
  type    = string
  default = "latest"
}

variable "tag_ms3" {
  type    = string
  default = "latest"
}

variable "tag_ms4" {
  type    = string
  default = "latest"
}

variable "tag_ms5" {
  type    = string
  default = "latest"
}

variable "tag_swagger" {
  type    = string
  default = "latest"
}

variable "enable_swagger_aggregator" {
  description = "Activa el upstream/location de swagger-aggregator en nginx y lo incluye en el 'docker compose up' de VM-PROD. Déjalo en false hasta que esa imagen exista en Docker Hub — si no, nginx no arranca para NINGÚN microservicio (host not found in upstream)."
  type        = bool
  default     = false
}
