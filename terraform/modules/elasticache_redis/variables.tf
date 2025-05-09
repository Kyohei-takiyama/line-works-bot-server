# ElastiCache for Redisモジュールの変数定義

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

variable "subnet_ids" {
  description = "Redisクラスターを配置するサブネットIDのリスト"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Redisクラスターへのアクセスを許可するセキュリティグループIDのリスト"
  type        = list(string)
  default     = []
}

variable "node_type" {
  description = "Redisノードのインスタンスタイプ"
  type        = string
  default     = "cache.t4g.micro" # 開発環境向けの小さいインスタンス
}

variable "engine_version" {
  description = "Redisエンジンのバージョン"
  type        = string
  default     = "7.0"
}

variable "port" {
  description = "Redisポート"
  type        = number
  default     = 6379
}

variable "parameter_group_name" {
  description = "Redisパラメータグループ名"
  type        = string
  default     = "default.redis7"
}

variable "num_cache_nodes" {
  description = "キャッシュノード数"
  type        = number
  default     = 1
}

variable "automatic_failover_enabled" {
  description = "自動フェイルオーバーを有効にするかどうか"
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "マルチAZを有効にするかどうか"
  type        = bool
  default     = false
}

variable "at_rest_encryption_enabled" {
  description = "保存データの暗号化を有効にするかどうか"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "転送中データの暗号化を有効にするかどうか"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "変更をすぐに適用するかどうか"
  type        = bool
  default     = false
}

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}
