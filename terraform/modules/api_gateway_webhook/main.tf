# API Gatewayモジュールのメイン定義

# ローカル変数
locals {
  name_prefix = "${var.project}-${var.environment}"
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "this" {
  name        = "${local.name_prefix}-api"
  description = "API Gateway for ${local.name_prefix} webhook"

  endpoint_configuration {
    types = [var.api_gateway_endpoint_type]
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-api"
    },
    var.tags
  )
}

# API Gateway リソース（/callback）
resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = replace(var.webhook_path, "/", "")
}

# API Gateway メソッド（POST）
resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id = var.enable_authorizer ? aws_api_gateway_authorizer.webhook[0].id : null

  request_parameters = {
    "method.request.header.X-Works-Signature" = true
  }
}

# API Gateway カスタムオーソライザー
resource "aws_api_gateway_authorizer" "webhook" {
  count          = var.enable_authorizer ? 1 : 0
  name           = "${local.name_prefix}-webhook-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.this.id
  authorizer_uri = aws_lambda_function.authorizer[0].invoke_arn

  authorizer_credentials           = aws_iam_role.authorizer[0].arn
  authorizer_result_ttl_in_seconds = 300
  type                             = "REQUEST"
  identity_source                  = "method.request.header.X-Works-Signature"
}

# Lambda関数（オーソライザー）
resource "aws_lambda_function" "authorizer" {
  count         = var.enable_authorizer ? 1 : 0
  function_name = "${local.name_prefix}-webhook-authorizer"
  role          = aws_iam_role.authorizer[0].arn
  handler       = "authorizer.handler"
  runtime       = "python3.11"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.authorizer_zip[0].output_path
  source_code_hash = data.archive_file.authorizer_zip[0].output_base64sha256

  environment {
    variables = {
      LW_API_BOT_SECRET = var.lw_api_bot_secret
    }
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-webhook-authorizer"
    },
    var.tags
  )
}

# Lambda関数のソースコードをZIP化
data "archive_file" "authorizer_zip" {
  count       = var.enable_authorizer ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_authorizer.zip"
  source_dir  = "${path.module}/lambda_authorizer"
}

# Lambda関数用IAMロール（オーソライザー）
resource "aws_iam_role" "authorizer" {
  count = var.enable_authorizer ? 1 : 0
  name  = "${local.name_prefix}-webhook-authorizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-webhook-authorizer-role"
    },
    var.tags
  )
}

# Lambda関数用ポリシー（オーソライザー）
resource "aws_iam_policy" "authorizer" {
  count       = var.enable_authorizer ? 1 : 0
  name        = "${local.name_prefix}-webhook-authorizer-policy"
  description = "Policy for webhook authorizer Lambda function"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-webhook-authorizer-policy"
    },
    var.tags
  )
}

# Lambda関数用ポリシーアタッチメント（オーソライザー）
resource "aws_iam_role_policy_attachment" "authorizer" {
  count      = var.enable_authorizer ? 1 : 0
  role       = aws_iam_role.authorizer[0].name
  policy_arn = aws_iam_policy.authorizer[0].arn
}

# VPCリンク
resource "aws_api_gateway_vpc_link" "this" {
  name        = "${local.name_prefix}-vpc-link-new"
  description = "VPC Link for ${local.name_prefix}"
  target_arns = [var.alb_arn]

  tags = merge(
    {
      Name = "${local.name_prefix}-vpc-link-new"
    },
    var.tags
  )
}

# API Gateway 統合（NLBへのプロキシ）
resource "aws_api_gateway_integration" "webhook_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook_post.http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "http://${var.alb_dns_name}${var.webhook_path}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.this.id

  request_parameters = {
    "integration.request.header.X-Works-Signature" = "method.request.header.X-Works-Signature"
  }
}

# API Gateway デプロイメント
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.webhook.id,
      aws_api_gateway_method.webhook_post.id,
      aws_api_gateway_integration.webhook_post.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.webhook_post,
    aws_api_gateway_integration.webhook_post
  ]
}

# API Gateway ステージ
resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  # ログ設定を無効化（CloudWatch Logs role ARNが設定されていないため）
  # access_log_settings {
  #   destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  #   format = jsonencode({
  #     requestId               = "$context.requestId",
  #     sourceIp                = "$context.identity.sourceIp",
  #     requestTime             = "$context.requestTime",
  #     protocol                = "$context.protocol",
  #     httpMethod              = "$context.httpMethod",
  #     resourcePath            = "$context.resourcePath",
  #     routeKey                = "$context.routeKey",
  #     status                  = "$context.status",
  #     responseLength          = "$context.responseLength",
  #     integrationErrorMessage = "$context.integrationErrorMessage"
  #   })
  # }

  xray_tracing_enabled = true

  tags = merge(
    {
      Name = "${local.name_prefix}-${var.stage_name}-stage"
    },
    var.tags
  )
}

# API Gateway メソッド設定
resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = var.api_gateway_metrics_enabled
    logging_level          = var.api_gateway_logging_level
    data_trace_enabled     = var.api_gateway_logging_level == "INFO"
    throttling_rate_limit  = var.api_gateway_throttling_rate_limit
    throttling_burst_limit = var.api_gateway_throttling_burst_limit
    caching_enabled        = var.api_gateway_caching_enabled
  }
}

# CloudWatch Logsグループ（API Gateway）
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = 30

  tags = merge(
    {
      Name = "${local.name_prefix}-api-gateway-logs"
    },
    var.tags
  )
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "this" {
  count       = var.enable_waf ? 1 : 0
  name        = "${local.name_prefix}-web-acl"
  description = "WAF Web ACL for ${local.name_prefix} API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # レート制限ルール
  rule {
    name     = "rate-limit-rule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rule_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit-rule"
      sampled_requests_enabled   = true
    }
  }

  # AWS マネージドルール - コアルールセット
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # AWS マネージドルール - 既知の不正な入力
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-web-acl"
    },
    var.tags
  )
}

# WAF Web ACLとAPI Gatewayの関連付け
resource "aws_wafv2_web_acl_association" "this" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

# API Gateway カスタムドメイン名
resource "aws_api_gateway_domain_name" "this" {
  count                    = var.enable_custom_domain ? 1 : 0
  domain_name              = var.domain_name
  regional_certificate_arn = var.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-domain"
    },
    var.tags
  )
}

# API Gateway ベースパスマッピング
resource "aws_api_gateway_base_path_mapping" "this" {
  count       = var.enable_custom_domain ? 1 : 0
  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
}

# Route53 レコード
resource "aws_route53_record" "this" {
  count   = var.enable_custom_domain ? 1 : 0
  name    = aws_api_gateway_domain_name.this[0].domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.this[0].zone_id

  alias {
    name                   = aws_api_gateway_domain_name.this[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.this[0].regional_zone_id
    evaluate_target_health = false
  }
}

# Route53 ホストゾーン
data "aws_route53_zone" "this" {
  count = var.enable_custom_domain ? 1 : 0
  name  = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name)) - 2, length(split(".", var.domain_name))))
}
