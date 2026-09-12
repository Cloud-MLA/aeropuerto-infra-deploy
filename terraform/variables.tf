variable "aws_region" {
  description = "Región del Learner Lab (la única garantizada)."
  type        = string
  default     = "us-east-1"
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
