# https://budougumi0617.github.io/2020/11/07/define_https_subdomain_by_terraform/
####################################################
# Route53 Host Zone
####################################################
# メインドメイン vngb.link のホストゾーンを取得
data "aws_route53_zone" "host_domain" {
  name = var.domain
}

####################################################
# Create ACM for API
####################################################
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-acm"
  }
}

resource "aws_route53_record" "this" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.value]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.host_domain.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.this : record.fqdn]
}

####################################################
# Create A Record for routing ALB
####################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/alb_hosted_zone_id
# data "aws_elb_hosted_zone_id" "main" {}
resource "aws_route53_record" "api_subdomain_alb" {
  zone_id = data.aws_route53_zone.host_domain.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
