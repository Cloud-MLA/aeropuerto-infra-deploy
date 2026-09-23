# RUNBOOK.md 1.9 — HTTP API pública -> VPC Link -> ALB interno.

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "aeropuerto-vpclink"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.apigw_vpclink.id]

  tags = { Name = "aeropuerto-vpclink" }
}

resource "aws_apigatewayv2_api" "main" {
  name          = "aeropuerto-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://main.d6qmhb5ipm8l2.amplifyapp.com"]
    allow_methods = ["GET", "POST", "PATCH", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
  integration_uri    = aws_lb_listener.http.arn
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}
