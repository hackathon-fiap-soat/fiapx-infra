# Entrada pública da API (ADR-010): HTTP API do API Gateway → VPC Link → ALB interno → pods (TargetGroupBinding).
# As rotas ficam nos repositórios dos serviços (/api/auth/* no fiapx-auth, /api/videos* no fiapx-video-api).
# O site (S3 website) está em outra origem, então o HTTP API responde CORS só para ela (ADR-019).
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_api" "this" {
  name          = var.prefix
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins  = [var.web_origin]
    allow_methods  = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers  = ["authorization", "content-type", "x-correlation-id"]
    expose_headers = ["x-correlation-id"]
    max_age        = 3600
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttle_burst
    throttling_rate_limit  = var.throttle_rate
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId         = "$context.requestId", ip = "$context.identity.sourceIp", method = "$context.httpMethod",
      path              = "$context.path", status = "$context.status", latencyMs = "$context.responseLatency",
      integrationStatus = "$context.integrationStatus", authorizerError = "$context.authorizer.error",
      userId            = "$context.authorizer.user_id"
    })
  }
}

# --- VPC Link e ALB interno ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_link" {
  name        = "${var.prefix}-vpc-link"
  description = "VPC Link do API Gateway"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb"
  description = "ALB interno: só o VPC Link entra"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

# Os pods do video-api usam o security group do cluster (VPC CNI); o ALB precisa alcançar a porta deles.
resource "aws_vpc_security_group_ingress_rule" "alb_para_pods" {
  security_group_id            = var.pods_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "ALB interno para os pods (TargetGroupBinding)"
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = var.prefix
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_lb" "this" {
  name               = var.prefix
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "video_api" {
  name        = "${var.prefix}-video-api"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/api/health/live"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.video_api.arn
  }
}
