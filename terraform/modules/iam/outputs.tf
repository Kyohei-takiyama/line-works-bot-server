# IAMモジュールのアウトプット定義

output "ci_cd_role_arn" {
  description = "CI/CDパイプライン用IAMロールのARN"
  value       = var.create_ci_cd_role ? aws_iam_role.ci_cd_role[0].arn : null
}

output "ci_cd_role_name" {
  description = "CI/CDパイプライン用IAMロールの名前"
  value       = var.create_ci_cd_role ? aws_iam_role.ci_cd_role[0].name : null
}

output "ecr_access_policy_arn" {
  description = "ECRアクセス用ポリシーのARN"
  value       = var.create_ci_cd_role && length(var.ecr_repository_arns) > 0 ? aws_iam_policy.ecr_access[0].arn : null
}

output "ecs_access_policy_arn" {
  description = "ECSアクセス用ポリシーのARN"
  value       = var.create_ci_cd_role && (length(var.ecs_cluster_arns) > 0 || length(var.ecs_service_arns) > 0 || length(var.ecs_task_definition_arns) > 0) ? aws_iam_policy.ecs_access[0].arn : null
}

output "secrets_manager_access_policy_arn" {
  description = "SecretsManagerアクセス用ポリシーのARN"
  value       = var.create_ci_cd_role && length(var.secrets_manager_arns) > 0 ? aws_iam_policy.secrets_manager_access[0].arn : null
}

output "cloudwatch_logs_access_policy_arn" {
  description = "CloudWatch Logsアクセス用ポリシーのARN"
  value       = var.create_ci_cd_role ? aws_iam_policy.cloudwatch_logs_access[0].arn : null
}

output "iam_passrole_policy_arn" {
  description = "IAMパススルーロール用ポリシーのARN"
  value       = var.create_ci_cd_role ? aws_iam_policy.iam_passrole[0].arn : null
}
