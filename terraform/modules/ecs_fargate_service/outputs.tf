# ECS Fargateサービスモジュールのアウトプット定義

output "ecs_cluster_id" {
  description = "ECSクラスターのID"
  value       = aws_ecs_cluster.this.id
}

output "ecs_cluster_name" {
  description = "ECSクラスターの名前"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECSクラスターのARN"
  value       = aws_ecs_cluster.this.arn
}

output "ecs_service_id" {
  description = "ECSサービスのID"
  value       = aws_ecs_service.this.id
}

output "ecs_service_name" {
  description = "ECSサービスの名前"
  value       = aws_ecs_service.this.name
}

output "ecs_task_definition_arn" {
  description = "ECSタスク定義のARN"
  value       = aws_ecs_task_definition.this.arn
}

output "ecs_task_execution_role_arn" {
  description = "ECSタスク実行ロールのARN"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ECSタスクロールのARN"
  value       = aws_iam_role.ecs_task_role.arn
}

output "alb_id" {
  description = "ALBのID"
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "ALBのARN"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALBのDNS名"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALBのゾーンID"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "ALB用セキュリティグループのID"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ECSタスク用セキュリティグループのID"
  value       = aws_security_group.ecs_tasks.id
}

output "target_group_arn" {
  description = "ターゲットグループのARN"
  value       = aws_lb_target_group.this.arn
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Logsグループ名"
  value       = aws_cloudwatch_log_group.this.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch Logsグループのarn"
  value       = aws_cloudwatch_log_group.this.arn
}
