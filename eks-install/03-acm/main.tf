# -----------------------------------------------------------------------------
# Stack: 03-acm
# Public ACM certificate, validated with Route 53 DNS records.
# Apply after 00-s3. Does not depend on the VPC or EKS stacks.
# -----------------------------------------------------------------------------

# Pin Terraform and the AWS provider so applies stay compatible across machines.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state: S3 holds this stack's state; DynamoDB prevents concurrent applies.
  backend "s3" {
    bucket         = "terraform-eks-state-s3-bucket-cqidm4"
    key            = "03-acm/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
# ACM certs for an ALB must be in the same region as the load balancer.
provider "aws" {
  region = var.region
}

# Existing public hosted zone that already owns the domain (created outside Terraform).
data "aws_route53_zone" "public" {
  name         = var.domain_name
  private_zone = false
}

# Public certificate covering the apex domain and any SANs (typically the wildcard).
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  # Replace the cert before destroying the old one so HTTPS is not interrupted.
  lifecycle {
    create_before_destroy = true
  }
}

# One CNAME per domain on the cert. ACM checks these to prove we own the domain.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
}

# Wait until Route 53 records exist and ACM marks the certificate ISSUED.
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
