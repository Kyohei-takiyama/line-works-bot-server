# ECS Fargateサービスモジュールの変数定義

variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "パブリックサブネットIDのリスト（ALB用）"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "プライベートサブネットIDのリスト（Fargateタスク用）"
  type        = list(string)
}

variable "ecr_repository_url" {
  description = "ECRリポジトリURL"
  type        = string
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

variable "host_port" {
  description = "ホストのポート"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "ヘルスチェックパス"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "ヘルスチェック間隔（秒）"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "ヘルスチェックタイムアウト（秒）"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "ヘルスチェック正常しきい値"
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "ヘルスチェック異常しきい値"
  type        = number
  default     = 3
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

variable "max_capacity" {
  description = "Auto Scalingの最大キャパシティ"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Auto Scalingの最小キャパシティ"
  type        = number
  default     = 1
}

variable "deployment_maximum_percent" {
  description = "デプロイ時の最大タスク割合"
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "デプロイ時の最小ヘルシータスク割合"
  type        = number
  default     = 100
}

variable "enable_auto_scaling" {
  description = "Auto Scalingを有効にするかどうか"
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "ECS Execを有効にするかどうか"
  type        = bool
  default     = true
}

variable "alb_internal" {
  description = "ALBを内部向けにするかどうか"
  type        = bool
  default     = false
}

variable "alb_ssl_certificate_arn" {
  description = "ALBのSSL証明書ARN"
  type        = string
  default     = ""
}

variable "alb_idle_timeout" {
  description = "ALBのアイドルタイムアウト（秒）"
  type        = number
  default     = 60
}

variable "alb_deletion_protection" {
  description = "ALBの削除保護を有効にするかどうか"
  type        = bool
  default     = false
}

variable "container_environment" {
  description = "コンテナの環境変数"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "container_secrets" {
  description = "コンテナのシークレット環境変数"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "redis_endpoint" {
  description = "Redisエンドポイント"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redisポート"
  type        = number
  default     = 6379
}

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}

variable "allowed_cidr_blocks" {
  description = "ALBへのアクセスを許可するCIDRブロックのリスト"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_in_days" {
  description = "CloudWatch Logsの保持期間（日）"
  type        = number
  default     = 30
}

variable "private_key_secret_arn" {
  description = "LINE WORKS API秘密鍵のSecretsManagerのARN"
  type        = string
}

variable "domain" {
  description = "ドメイン名"
  type        = string
}

variable "domain_name" {
  description = "ドメイン名（FQDN）"
  type        = string
}
