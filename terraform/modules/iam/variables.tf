# IAMモジュールの変数定義

variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}

variable "create_ci_cd_role" {
  description = "CI/CDパイプライン用のIAMロールを作成するかどうか"
  type        = bool
  default     = true
}

variable "ci_cd_role_trusted_accounts" {
  description = "CI/CDロールを引き受けることができるAWSアカウントIDのリスト"
  type        = list(string)
  default     = []
}

variable "ci_cd_role_trusted_services" {
  description = "CI/CDロールを引き受けることができるAWSサービスのリスト"
  type        = list(string)
  default     = ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
}

variable "ecr_repository_arns" {
  description = "アクセスを許可するECRリポジトリのARNのリスト"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_arns" {
  description = "アクセスを許可するECSクラスターのARNのリスト"
  type        = list(string)
  default     = []
}

variable "ecs_service_arns" {
  description = "アクセスを許可するECSサービスのARNのリスト"
  type        = list(string)
  default     = []
}

variable "ecs_task_definition_arns" {
  description = "アクセスを許可するECSタスク定義のARNのリスト"
  type        = list(string)
  default     = []
}

variable "secrets_manager_arns" {
  description = "アクセスを許可するSecretsManagerのARNのリスト"
  type        = list(string)
  default     = []
}
