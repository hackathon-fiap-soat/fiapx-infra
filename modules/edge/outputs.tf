output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.this.id
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.video_api.arn
}

output "web_target_group_arn" {
  value = aws_lb_target_group.web.arn
}
