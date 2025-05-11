# ECS Fargateサービスモジュールのメイン定義（続き）

# ECSタスク定義
resource "aws_ecs_task_definition" "this" {
  family                   = "${local.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.host_port
          protocol      = "tcp"
        }
      ]

      environment = local.container_environment

      secrets = var.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    {
      Name = "${local.name_prefix}-task"
    },
    var.tags
  )
}

# ECSサービス
resource "aws_ecs_service" "this" {
  name                               = "${local.name_prefix}-service-new"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  enable_execute_command             = var.enable_execute_command

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # デプロイ設定
  deployment_controller {
    type = "ECS"
  }

  # デプロイ中にALBのヘルスチェックが失敗した場合にロールバック
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # タスク定義の変更を無視（CI/CDパイプラインで更新するため）
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-service"
    },
    var.tags
  )

  depends_on = [aws_lb_listener.http]
}

# ECSタスク用セキュリティグループ
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # コンテナポートへのインバウンドアクセスを許可
  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow inbound traffic to container port"
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
      Name = "${local.name_prefix}-ecs-tasks-sg"
    },
    var.tags
  )
}

# NLB
resource "aws_lb" "this" {
  name               = "${local.name_prefix}-nlb"
  internal           = var.alb_internal
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.alb_deletion_protection

  tags = merge(
    {
      Name = "${local.name_prefix}-nlb"
    },
    var.tags
  )
}

# ALB用セキュリティグループ
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  # HTTPSへのインバウンドアクセスを許可
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow HTTPS inbound traffic"
  }

  # HTTPへのインバウンドアクセスを許可（HTTPSにリダイレクト）
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow HTTP inbound traffic"
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
      Name = "${local.name_prefix}-alb-sg"
    },
    var.tags
  )
}

# NLBターゲットグループ
resource "aws_lb_target_group" "this" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = var.health_check_interval
    port                = "traffic-port"
    protocol            = "TCP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-tg"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# NLB TCPリスナー
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-tcp-listener"
    },
    var.tags
  )
}

# NLB TLSリスナー
resource "aws_lb_listener" "https" {
  count             = var.alb_ssl_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(
    {
      Name = "${local.name_prefix}-tls-listener"
    },
    var.tags
  )
}

# Auto Scaling
resource "aws_appautoscaling_target" "this" {
  count              = var.enable_auto_scaling ? 1 : 0
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity

  # サービス名が変更された場合に再作成されるように依存関係を追加
  depends_on = [aws_ecs_service.this]
}

# CPU使用率に基づくスケーリングポリシー
resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_auto_scaling ? 1 : 0
  name               = "${local.name_prefix}-cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# メモリ使用率に基づくスケーリングポリシー
resource "aws_appautoscaling_policy" "memory" {
  count              = var.enable_auto_scaling ? 1 : 0
  name               = "${local.name_prefix}-memory-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# 現在のリージョン情報を取得
data "aws_region" "current" {}
