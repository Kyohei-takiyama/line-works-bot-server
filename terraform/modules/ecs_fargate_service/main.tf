# ECS Fargateサービスモジュールのメイン定義

# ローカル変数
locals {
  name_prefix     = "${var.project}-${var.environment}"
  container_name  = "${local.name_prefix}-container"
  container_image = "${var.ecr_repository_url}:${var.container_image_tag}"

  # デフォルトの環境変数
  default_environment = [
    {
      name  = "REDIS_HOST"
      value = var.redis_endpoint
    },
    {
      name  = "REDIS_PORT"
      value = tostring(var.redis_port)
    },
    {
      name  = "REDIS_DB"
      value = "0"
    }
  ]

  # 環境変数をマージ
  container_environment = concat(local.default_environment, var.container_environment)
}

# CloudWatch Logsグループ
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_in_days

  tags = merge(
    {
      Name = "${local.name_prefix}-logs"
    },
    var.tags
  )
}

# ECSクラスター
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-cluster"
    },
    var.tags
  )
}

# ECSタスク実行ロール
resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ecs-execution-role"
    },
    var.tags
  )
}

# ECSタスク実行ロールポリシーアタッチメント
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# SecretsManagerアクセス用ポリシー
resource "aws_iam_policy" "secrets_manager_access" {
  name        = "${local.name_prefix}-secrets-manager-access"
  description = "Allow access to Secrets Manager for ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ],
        Effect = "Allow",
        Resource = [
          var.private_key_secret_arn,
          "*" # 必要に応じて制限する
        ]
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-secrets-manager-access"
    },
    var.tags
  )
}

# SecretsManagerアクセスポリシーアタッチメント
resource "aws_iam_role_policy_attachment" "secrets_manager_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

# ECSタスクロール
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ecs-task-role"
    },
    var.tags
  )
}

# ECS Execを有効にするためのポリシー
resource "aws_iam_policy" "ecs_exec_policy" {
  count       = var.enable_execute_command ? 1 : 0
  name        = "${local.name_prefix}-ecs-exec-policy"
  description = "Allow ECS Exec functionality"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ecs-exec-policy"
    },
    var.tags
  )
}

# ECS Execポリシーアタッチメント
resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  count      = var.enable_execute_command ? 1 : 0
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy[0].arn
}

# CloudWatch Logsアクセス用ポリシー
resource "aws_iam_policy" "cloudwatch_logs_access" {
  name        = "${local.name_prefix}-cloudwatch-logs-access"
  description = "Allow access to CloudWatch Logs for ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-cloudwatch-logs-access"
    },
    var.tags
  )
}

# CloudWatch Logsアクセスポリシーアタッチメント
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_access.arn
}
