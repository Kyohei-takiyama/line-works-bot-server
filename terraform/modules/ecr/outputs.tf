# ECRモジュールのアウトプット定義

output "repository_url" {
  description = "ECRリポジトリのURL"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "ECRリポジトリの名前"
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "ECRリポジトリのARN"
  value       = aws_ecr_repository.this.arn
}

output "repository_registry_id" {
  description = "ECRリポジトリのレジストリID"
  value       = aws_ecr_repository.this.registry_id
}
