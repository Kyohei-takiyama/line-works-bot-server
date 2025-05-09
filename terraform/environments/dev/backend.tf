# 開発環境のバックエンド設定
# S3バケットを使用してTerraformの状態を管理します

terraform {
  backend "s3" {
    bucket         = "line-works-bot-terraform-state-dev"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "line-works-bot-terraform-lock-dev"
  }
}
