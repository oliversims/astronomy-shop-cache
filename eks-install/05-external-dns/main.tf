# -----------------------------------------------------------------------------
# Stack: 05-external-dns
# ExternalDNS EKS add-on. Watches Ingress/Service hosts and creates Route 53
# records that point at the load balancer.
# Apply after 04-alb (Pod Identity agent and LBC webhook must already be running).
# -----------------------------------------------------------------------------

# Pin the AWS provider so applies stay compatible across machines.
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
    bucket         = "terraform-eks-state-s3-bucket-wv8zkt"
    key            = "05-external-dns/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# Public hosted zone that already owns the domain (same zone used by 03-acm).
data "aws_route53_zone" "public" {
  name         = var.domain_name
  private_zone = false
}

# IAM role ExternalDNS assumes via Pod Identity.
resource "aws_iam_role" "external_dns" {
  name = "${var.cluster_name}-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
    }]
  })
}

# Allow record changes only on this hosted zone. List APIs are account-wide.
resource "aws_iam_role_policy" "external_dns" {
  name = "${var.cluster_name}-external-dns"
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.public.zone_id}"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Install ExternalDNS. Pod Identity maps the add-on SA to the IAM role above.
resource "aws_eks_addon" "external_dns" {
  cluster_name                = var.cluster_name
  addon_name                  = "external-dns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.external_dns.arn
    service_account = "external-dns"
  }

  # Only manage this domain's public zone. txtOwnerId marks records this cluster owns.
  # policy=sync deletes DNS records when the Ingress/Service is deleted.
  configuration_values = jsonencode({
    domainFilters = [var.domain_name]
    extraArgs     = ["--aws-zone-type=public"]
    txtOwnerId    = var.cluster_name
    policy        = "sync"
    sources       = ["ingress", "service"]
  })

  depends_on = [aws_iam_role_policy.external_dns]
}
