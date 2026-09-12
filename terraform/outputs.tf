output "alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "api_invoke_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "vm_prod_private_ips" {
  value = aws_instance.vm_prod[*].private_ip
}

output "vm_db_private_ip" {
  value = aws_instance.vm_db.private_ip
}

output "vm_ingesta_private_ip" {
  value = aws_instance.vm_ingesta.private_ip
}

output "bucket_name" {
  value = aws_s3_bucket.lake.bucket
}
