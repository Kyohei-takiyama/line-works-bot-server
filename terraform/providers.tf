# AWSプロバイダーの設定

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWSプロバイダーの設定
# 各環境ディレクトリのmain.tfでregionを上書きすることも可能
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
