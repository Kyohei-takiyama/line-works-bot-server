# API Gatewayモジュールの変数定義

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

variable "private_subnet_ids" {
  description = "プライベートサブネットIDのリスト"
  type        = list(string)
}

variable "alb_dns_name" {
  description = "ALBのDNS名"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALBリスナーのARN"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALBセキュリティグループのID"
  type        = string
}

variable "webhook_path" {
  description = "Webhookパス"
  type        = string
  default     = "/callback"
}

variable "stage_name" {
  description = "APIステージ名"
  type        = string
  default     = "v1"
}

variable "enable_waf" {
  description = "WAFを有効にするかどうか"
  type        = bool
  default     = true
}

variable "waf_rule_rate_limit" {
  description = "WAFレート制限ルールの制限値（5分あたりのリクエスト数）"
  type        = number
  default     = 100
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

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}

variable "api_gateway_endpoint_type" {
  description = "API Gatewayのエンドポイントタイプ（REGIONAL, EDGE, PRIVATE）"
  type        = string
  default     = "REGIONAL"
}

variable "api_gateway_logging_level" {
  description = "API Gatewayのロギングレベル（OFF, ERROR, INFO）"
  type        = string
  default     = "INFO"
}

variable "api_gateway_metrics_enabled" {
  description = "API Gatewayのメトリクスを有効にするかどうか"
  type        = bool
  default     = true
}

variable "api_gateway_caching_enabled" {
  description = "API Gatewayのキャッシュを有効にするかどうか"
  type        = bool
  default     = false
}

variable "api_gateway_throttling_rate_limit" {
  description = "API Gatewayのスロットリングレート制限"
  type        = number
  default     = 1000
}

variable "api_gateway_throttling_burst_limit" {
  description = "API Gatewayのスロットリングバースト制限"
  type        = number
  default     = 2000
}
