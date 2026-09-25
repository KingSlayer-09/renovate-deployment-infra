output "api_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/hello"
}

output "ecs_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "data_bucket" {
  value = aws_s3_bucket.data.bucket
}

output "secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "ecs_cluster" {
  value = aws_ecs_cluster.app.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}

