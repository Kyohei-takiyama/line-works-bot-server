# ElastiCache for Redisモジュールのメイン定義

# ローカル変数
locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Redisサブネットグループ
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    {
      Name = "${local.name_prefix}-redis-subnet-group"
    },
    var.tags
  )
}

# Redisセキュリティグループ
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Security group for Redis cluster"
  vpc_id      = var.vpc_id

  # Redisポートへのインバウンドアクセスを許可
  ingress {
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "Allow Redis traffic from specified security groups"
  }

  # すべてのアウトバウンドトラフィックを許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-redis-sg"
    },
    var.tags
  )
}

# Redisクラスターパラメータグループ（必要に応じて）
resource "aws_elasticache_parameter_group" "this" {
  name   = "${local.name_prefix}-redis-params"
  family = "redis7"

  # 必要に応じてパラメータをカスタマイズ
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-redis-params"
    },
    var.tags
  )
}

# Redisレプリケーショングループ（クラスターモード無効）
resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "Redis cluster for ${local.name_prefix}"
  node_type                  = var.node_type
  port                       = var.port
  parameter_group_name       = aws_elasticache_parameter_group.this.name
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.redis.id]
  engine_version             = var.engine_version
  num_cache_clusters         = var.num_cache_nodes
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  apply_immediately          = var.apply_immediately

  tags = merge(
    {
      Name = "${local.name_prefix}-redis"
    },
    var.tags
  )

  # 環境に応じたバックアップ設定
  # 本番環境では7日間のバックアップを保持、それ以外の環境ではバックアップを無効化
  snapshot_retention_limit = var.environment == "prd" ? 7 : 0

  # 非本番環境では、インスタンスタイプの変更を無視する設定
  # 本番環境でも同じ設定を適用（必要に応じて手動で変更）
  lifecycle {
    ignore_changes = [node_type]
  }
}
