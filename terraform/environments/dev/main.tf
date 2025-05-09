# 開発環境のメイン定義

# VPCモジュール
module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = true
  single_nat_gateway   = true

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# ECRモジュール
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# SecretsManager（機密情報管理）
resource "aws_secretsmanager_secret" "line_works_bot" {
  name        = "${var.project}-${var.environment}-secrets"
  description = "Secrets for LINE WORKS Bot"



  tags = {
    Name        = "${var.project}-${var.environment}-secrets"
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_secretsmanager_secret_version" "line_works_bot" {
  secret_id     = aws_secretsmanager_secret.line_works_bot.id
  secret_string = jsonencode(var.secrets)
}

# ElastiCache for Redisモジュール
module "elasticache_redis" {
  source = "../../modules/elasticache_redis"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  # 開発環境用の小さいインスタンスタイプ
  node_type = "cache.t4g.micro"

  # セキュリティグループは後で設定するECSタスクからのアクセスを許可
  allowed_security_group_ids = []

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# ECS Fargateサービスモジュール
module "ecs_fargate_service" {
  source = "../../modules/ecs_fargate_service"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  ecr_repository_url  = module.ecr.repository_url
  container_image_tag = var.container_image_tag
  container_port      = var.container_port

  cpu           = var.cpu
  memory        = var.memory
  desired_count = var.desired_count

  enable_auto_scaling = var.enable_auto_scaling

  # ALB設定
  alb_internal            = false
  alb_ssl_certificate_arn = var.alb_ssl_certificate_arn

  # Redis設定
  redis_endpoint = module.elasticache_redis.redis_endpoint
  redis_port     = module.elasticache_redis.redis_port

  # 秘密鍵のSecretsManager ARN
  private_key_secret_arn = aws_secretsmanager_secret.line_works_bot.arn

  # コンテナの環境変数
  container_environment = [
    {
      name  = "ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "LW_API_PRIVATEKEY_PATH"
      value = "/app/private.key"
    },
    {
      name  = "ANTHROPIC_MODEL"
      value = "claude-3-haiku-20240307"
    },
    {
      name  = "SF_API_VERSION"
      value = "v59.0"
    }
  ]

  # コンテナのシークレット環境変数
  container_secrets = [
    {
      name      = "LW_API_ID"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:LW_API_ID::"
    },
    {
      name      = "LW_API_BOT_ID"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:LW_API_BOT_ID::"
    },
    {
      name      = "LW_API_BOT_SECRET"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:LW_API_BOT_SECRET::"
    },
    {
      name      = "LW_API_SERVICE_ACCOUNT"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:LW_API_SERVICE_ACCOUNT::"
    },
    {
      name      = "CLIENT_ID"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:CLIENT_ID::"
    },
    {
      name      = "CLIENT_SECRET"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:CLIENT_SECRET::"
    },
    {
      name      = "ANTHROPIC_API_KEY"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:ANTHROPIC_API_KEY::"
    },
    {
      name      = "SF_CLIENT_ID"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:SF_CLIENT_ID::"
    },
    {
      name      = "SF_CLIENT_SECRET"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:SF_CLIENT_SECRET::"
    },
    {
      name      = "SF_TOKEN_URL"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:SF_TOKEN_URL::"
    },
    {
      name      = "SF_AGENT_ID"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:SF_AGENT_ID::"
    },
    {
      name      = "SF_BASE_URL"
      valueFrom = "${aws_secretsmanager_secret.line_works_bot.arn}:SF_BASE_URL::"
    }
  ]

  domain      = var.domain
  domain_name = "${var.project}-${var.environment}.${var.domain}"

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }

  # ElastiCacheセキュリティグループにECSタスクからのアクセスを許可
  depends_on = [module.elasticache_redis]
}

# API Gatewayモジュール
module "api_gateway_webhook" {
  source = "../../modules/api_gateway_webhook"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids

  alb_dns_name          = module.ecs_fargate_service.alb_dns_name
  alb_listener_arn      = module.ecs_fargate_service.alb_arn
  alb_security_group_id = module.ecs_fargate_service.alb_security_group_id

  webhook_path = "/callback"
  stage_name   = "v1"

  enable_waf        = var.enable_waf
  enable_authorizer = var.enable_authorizer
  lw_api_bot_secret = var.lw_api_bot_secret

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# IAMモジュール（CI/CD用）
module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment

  create_ci_cd_role = true

  # CI/CDパイプラインを実行するAWSアカウントID
  ci_cd_role_trusted_accounts = []

  # CI/CDパイプラインが使用するAWSサービス
  ci_cd_role_trusted_services = ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]

  # アクセスを許可するリソース
  ecr_repository_arns      = [module.ecr.repository_arn]
  ecs_cluster_arns         = [module.ecs_fargate_service.ecs_cluster_arn]
  ecs_service_arns         = [module.ecs_fargate_service.ecs_service_id]
  ecs_task_definition_arns = [module.ecs_fargate_service.ecs_task_definition_arn]
  secrets_manager_arns     = [aws_secretsmanager_secret.line_works_bot.arn]

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# 出力
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "ECRリポジトリURL"
  value       = module.ecr.repository_url
}

output "redis_endpoint" {
  description = "Redisエンドポイント"
  value       = module.elasticache_redis.redis_endpoint
}

output "alb_dns_name" {
  description = "ALB DNS名"
  value       = module.ecs_fargate_service.alb_dns_name
}

output "api_gateway_invoke_url" {
  description = "API Gateway呼び出しURL"
  value       = module.api_gateway_webhook.api_gateway_invoke_url
}

output "ci_cd_role_arn" {
  description = "CI/CDパイプライン用IAMロールのARN"
  value       = module.iam.ci_cd_role_arn
}

output "secrets_manager_arn" {
  description = "SecretsManagerのARN"
  value       = aws_secretsmanager_secret.line_works_bot.arn
}
