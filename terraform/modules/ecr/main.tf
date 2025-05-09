# ECRモジュールのメイン定義

# リポジトリ名をローカル変数として定義
locals {
  repository_name = "${var.project}-${var.environment}"
}

# ECRリポジトリ
resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(
    {
      Name = local.repository_name
    },
    var.tags
  )
}

# ECRリポジトリポリシー
resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowPullFromECR",
        Effect = "Allow",
        Principal = {
          Service = "ecs.amazonaws.com"
        },
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# ECRライフサイクルポリシー
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy
}
