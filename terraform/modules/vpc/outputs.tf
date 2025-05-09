# VPCモジュールのアウトプット定義

output "vpc_id" {
  description = "作成されたVPCのID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPCのCIDRブロック"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "パブリックサブネットのIDリスト"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "プライベートサブネットのIDリスト"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "パブリックサブネットのCIDRブロックリスト"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "プライベートサブネットのCIDRブロックリスト"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ids" {
  description = "NATゲートウェイのIDリスト"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "NATゲートウェイのパブリックIPアドレスリスト"
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "パブリックルートテーブルのID"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "プライベートルートテーブルのIDリスト"
  value       = aws_route_table.private[*].id
}

output "vpc_endpoint_s3_id" {
  description = "S3 VPCエンドポイントのID"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "ECR API VPCエンドポイントのID"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ECR Docker VPCエンドポイントのID"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_logs_id" {
  description = "CloudWatch Logs VPCエンドポイントのID"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_secretsmanager_id" {
  description = "Secrets Manager VPCエンドポイントのID"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "vpc_endpoints_security_group_id" {
  description = "VPCエンドポイント用セキュリティグループのID"
  value       = aws_security_group.vpc_endpoints.id
}
