# API Gatewayモジュールのアウトプット定義

output "api_gateway_id" {
  description = "API Gateway REST APIのID"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_gateway_name" {
  description = "API Gateway REST APIの名前"
  value       = aws_api_gateway_rest_api.this.name
}

output "api_gateway_execution_arn" {
  description = "API Gateway実行ARN"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "api_gateway_stage_name" {
  description = "API Gatewayステージ名"
  value       = aws_api_gateway_stage.this.stage_name
}

output "api_gateway_stage_arn" {
  description = "API Gatewayステージのarn"
  value       = aws_api_gateway_stage.this.arn
}

output "api_gateway_invoke_url" {
  description = "API Gateway呼び出しURL"
  value       = "${aws_api_gateway_stage.this.invoke_url}${aws_api_gateway_resource.webhook.path}"
}

output "vpc_link_id" {
  description = "VPCリンクのID"
  value       = aws_api_gateway_vpc_link.this.id
}

output "vpc_link_arn" {
  description = "VPCリンクのARN"
  value       = aws_api_gateway_vpc_link.this.arn
}

output "authorizer_lambda_function_name" {
  description = "オーソライザーLambda関数の名前"
  value       = var.enable_authorizer ? aws_lambda_function.authorizer[0].function_name : null
}

output "authorizer_lambda_function_arn" {
  description = "オーソライザーLambda関数のARN"
  value       = var.enable_authorizer ? aws_lambda_function.authorizer[0].arn : null
}

output "waf_web_acl_id" {
  description = "WAF Web ACLのID"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].id : null
}

output "waf_web_acl_arn" {
  description = "WAF Web ACLのARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Logsグループ名"
  value       = aws_cloudwatch_log_group.api_gateway.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch Logsグループのarn"
  value       = aws_cloudwatch_log_group.api_gateway.arn
}

output "custom_domain_name" {
  description = "API Gatewayのカスタムドメイン名"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.this[0].domain_name : null
}

output "custom_domain_url" {
  description = "API Gatewayのカスタムドメインを使用した呼び出しURL"
  value       = var.enable_custom_domain ? "https://${aws_api_gateway_domain_name.this[0].domain_name}/${aws_api_gateway_resource.webhook.path_part}" : null
}

output "regional_domain_name" {
  description = "API Gatewayのリージョナルドメイン名"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.this[0].regional_domain_name : null
}

output "regional_zone_id" {
  description = "API GatewayのリージョナルゾーンID"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.this[0].regional_zone_id : null
}
