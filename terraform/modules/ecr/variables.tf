# ECRモジュールの変数定義

variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスとして使用）"
  type        = string
}

variable "environment" {
  description = "環境名（dev, stg, prd）"
  type        = string
}

variable "image_tag_mutability" {
  description = "イメージタグの変更可否（MUTABLE or IMMUTABLE）"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "イメージプッシュ時にスキャンを実行するかどうか"
  type        = bool
  default     = true
}

variable "tags" {
  description = "リソースに付与する追加のタグ"
  type        = map(string)
  default     = {}
}

variable "lifecycle_policy" {
  description = "ECRリポジトリのライフサイクルポリシー（JSON形式）"
  type        = string
  default     = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep only the last 30 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
}
