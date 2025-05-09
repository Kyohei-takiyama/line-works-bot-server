# ElastiCache for Redisモジュールのアウトプット定義

output "redis_endpoint" {
  description = "Redisプライマリエンドポイント"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Redisリーダーエンドポイント"
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "redis_port" {
  description = "Redisポート"
  value       = var.port
}

output "redis_security_group_id" {
  description = "Redis用セキュリティグループID"
  value       = aws_security_group.redis.id
}

output "redis_subnet_group_name" {
  description = "Redisサブネットグループ名"
  value       = aws_elasticache_subnet_group.this.name
}

output "redis_parameter_group_name" {
  description = "Redisパラメータグループ名"
  value       = aws_elasticache_parameter_group.this.name
}

output "redis_replication_group_id" {
  description = "Redisレプリケーショングループ ID"
  value       = aws_elasticache_replication_group.this.id
}

output "redis_arn" {
  description = "Redis ARN"
  value       = aws_elasticache_replication_group.this.arn
}

output "redis_connection_string" {
  description = "Redis接続文字列"
  value       = "redis://${aws_elasticache_replication_group.this.primary_endpoint_address}:${var.port}"
}
