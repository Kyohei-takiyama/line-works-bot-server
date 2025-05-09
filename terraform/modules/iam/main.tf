# IAMモジュールのメイン定義

# ローカル変数
locals {
  name_prefix = "${var.project}-${var.environment}"
}

# CI/CDパイプライン用IAMロール
resource "aws_iam_role" "ci_cd_role" {
  count = var.create_ci_cd_role ? 1 : 0
  name  = "${local.name_prefix}-ci-cd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat(
      [for account in var.ci_cd_role_trusted_accounts : {
        Effect    = "Allow",
        Principal = { "AWS" = "arn:aws:iam::${account}:root" },
        Action    = "sts:AssumeRole"
      }],
      [for service in var.ci_cd_role_trusted_services : {
        Effect    = "Allow",
        Principal = { "Service" = service },
        Action    = "sts:AssumeRole"
      }]
    )
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ci-cd-role"
    },
    var.tags
  )
}

# CI/CDパイプライン用ポリシー（ECRアクセス）
resource "aws_iam_policy" "ecr_access" {
  count       = var.create_ci_cd_role && length(var.ecr_repository_arns) > 0 ? 1 : 0
  name        = "${local.name_prefix}-ecr-access-policy"
  description = "Policy for ECR access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken"
        ],
        Resource = concat(var.ecr_repository_arns, ["*"])
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ecr-access-policy"
    },
    var.tags
  )
}

# CI/CDパイプライン用ポリシー（ECSアクセス）
resource "aws_iam_policy" "ecs_access" {
  count       = var.create_ci_cd_role && (length(var.ecs_cluster_arns) > 0 || length(var.ecs_service_arns) > 0 || length(var.ecs_task_definition_arns) > 0) ? 1 : 0
  name        = "${local.name_prefix}-ecs-access-policy"
  description = "Policy for ECS access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ],
        Resource = concat(
          var.ecs_cluster_arns,
          var.ecs_service_arns,
          var.ecs_task_definition_arns,
          ["*"]
        )
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-ecs-access-policy"
    },
    var.tags
  )
}

# CI/CDパイプライン用ポリシー（SecretsManagerアクセス）
resource "aws_iam_policy" "secrets_manager_access" {
  count       = var.create_ci_cd_role && length(var.secrets_manager_arns) > 0 ? 1 : 0
  name        = "${local.name_prefix}-secrets-manager-access-policy"
  description = "Policy for Secrets Manager access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = var.secrets_manager_arns
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-secrets-manager-access-policy"
    },
    var.tags
  )
}

# CI/CDパイプライン用ポリシー（CloudWatchLogsアクセス）
resource "aws_iam_policy" "cloudwatch_logs_access" {
  count       = var.create_ci_cd_role ? 1 : 0
  name        = "${local.name_prefix}-cloudwatch-logs-access-policy"
  description = "Policy for CloudWatch Logs access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-cloudwatch-logs-access-policy"
    },
    var.tags
  )
}

# CI/CDパイプライン用ポリシー（IAMパススルーロール）
resource "aws_iam_policy" "iam_passrole" {
  count       = var.create_ci_cd_role ? 1 : 0
  name        = "${local.name_prefix}-iam-passrole-policy"
  description = "Policy for IAM PassRole"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "iam:PassRole",
        Resource = "arn:aws:iam::*:role/*",
        Condition = {
          StringEquals = {
            "iam:PassedToService" : [
              "ecs-tasks.amazonaws.com",
              "ecs.amazonaws.com"
            ]
          }
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${local.name_prefix}-iam-passrole-policy"
    },
    var.tags
  )
}

# ポリシーアタッチメント（ECRアクセス）
resource "aws_iam_role_policy_attachment" "ecr_access" {
  count      = var.create_ci_cd_role && length(var.ecr_repository_arns) > 0 ? 1 : 0
  role       = aws_iam_role.ci_cd_role[0].name
  policy_arn = aws_iam_policy.ecr_access[0].arn
}

# ポリシーアタッチメント（ECSアクセス）
resource "aws_iam_role_policy_attachment" "ecs_access" {
  count      = var.create_ci_cd_role && (length(var.ecs_cluster_arns) > 0 || length(var.ecs_service_arns) > 0 || length(var.ecs_task_definition_arns) > 0) ? 1 : 0
  role       = aws_iam_role.ci_cd_role[0].name
  policy_arn = aws_iam_policy.ecs_access[0].arn
}

# ポリシーアタッチメント（SecretsManagerアクセス）
resource "aws_iam_role_policy_attachment" "secrets_manager_access" {
  count      = var.create_ci_cd_role && length(var.secrets_manager_arns) > 0 ? 1 : 0
  role       = aws_iam_role.ci_cd_role[0].name
  policy_arn = aws_iam_policy.secrets_manager_access[0].arn
}

# ポリシーアタッチメント（CloudWatchLogsアクセス）
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_access" {
  count      = var.create_ci_cd_role ? 1 : 0
  role       = aws_iam_role.ci_cd_role[0].name
  policy_arn = aws_iam_policy.cloudwatch_logs_access[0].arn
}

# ポリシーアタッチメント（IAMパススルーロール）
resource "aws_iam_role_policy_attachment" "iam_passrole" {
  count      = var.create_ci_cd_role ? 1 : 0
  role       = aws_iam_role.ci_cd_role[0].name
  policy_arn = aws_iam_policy.iam_passrole[0].arn
}
