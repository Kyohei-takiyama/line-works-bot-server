variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
  default     = "line-works-bot"
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1" # 東京リージョン
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

# 共通タグ
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
