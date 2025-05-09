# VPCモジュールの変数定義

variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

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

variable "enable_nat_gateway" {
  description = "NATゲートウェイを有効にするかどうか"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "単一のNATゲートウェイを使用するかどうか（コスト削減のため）"
  type        = bool
  default     = true
}

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}
