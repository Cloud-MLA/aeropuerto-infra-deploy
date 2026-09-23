output "alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "api_invoke_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "vm_prod_private_ips" {
  value = aws_instance.vm_prod[*].private_ip
}

output "vm_prod_public_ips" {
  description = "IP pública de cada VM-PROD — usar para probar con Postman/Swagger directo, sin pasar por API Gateway/ALB (ej. http://<ip>/api/pasajeros/docs, http://<ip>:8002/api/vuelos/docs)."
  value       = aws_instance.vm_prod[*].public_ip
}

output "vm_db_private_ip" {
  value = aws_instance.vm_db.private_ip
}

output "vm_ingesta_private_ip" {
  value = aws_instance.vm_ingesta.private_ip
}

output "bucket_name" {
  # Gestionado fuera de Terraform (ver s3.tf) — el bucket ya existe, solo se referencia el nombre.
  value = var.bucket_name
}
