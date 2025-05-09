# 開発環境の変数定義

# グローバル変数をインポート
variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

# 環境固有の変数
variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "使用するアベイラビリティゾーンのリスト"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットのCIDRブロックのリスト"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "プライベートサブネットのCIDRブロックのリスト"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "container_image_tag" {
  description = "コンテナイメージのタグ"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "コンテナのポート"
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "タスク定義のCPUユニット"
  type        = number
  default     = 256
}

variable "memory" {
  description = "タスク定義のメモリ（MiB）"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "サービスの希望タスク数"
  type        = number
  default     = 1
}

variable "enable_auto_scaling" {
  description = "Auto Scalingを有効にするかどうか"
  type        = bool
  default     = false
}

variable "alb_ssl_certificate_arn" {
  description = "ALBのSSL証明書ARN"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "WAFを有効にするかどうか"
  type        = bool
  default     = true
}

variable "enable_authorizer" {
  description = "カスタムオーソライザーを有効にするかどうか"
  type        = bool
  default     = false
}

variable "lw_api_bot_secret" {
  description = "LINE WORKS BOT Secret（オーソライザーで使用）"
  type        = string
  default     = ""
}

variable "domain" {
  description = "ドメイン名"
  type        = string
}

variable "secrets" {
  description = "SecretsManagerに保存する機密情報"
  type        = map(string)
  default     = {}
  sensitive   = true
}
