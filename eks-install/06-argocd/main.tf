# -----------------------------------------------------------------------------
# Stack: 06-argocd
# Install Argo CD and expose it on HTTPS via ALB + ACM + ExternalDNS.
# Apply after 03-acm, 04-alb, and 05-external-dns.
# -----------------------------------------------------------------------------

# Pin AWS, Helm, and Kubernetes providers.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  # Remote state: S3 holds this stack's state; DynamoDB prevents concurrent applies.
  backend "s3" {
    bucket         = "terraform-eks-state-s3-bucket-cqidm4"
    key            = "06-argocd/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# Look up the cluster created by 02-eks (endpoint and CA for Helm/Kubernetes).
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

# Short-lived token so Helm and Kubernetes can talk to the API.
data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# ACM certificate ARN from 03-acm (wildcard covers argocd.<domain>).
data "terraform_remote_state" "acm" {
  backend = "s3"

  config = {
    bucket = "terraform-eks-state-s3-bucket-cqidm4"
    key    = "03-acm/terraform.tfstate"
    region = "us-east-1"
  }
}

# Helm 3 provider: kubernetes is an argument (not a nested block).
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Kubernetes provider for the Ingress object.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Official Argo CD Helm chart. ALB terminates TLS, so the server serves HTTP.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.16"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      global = {
        domain = var.hostname
      }
      configs = {
        cm = {
          url = "https://${var.hostname}"
        }
        # server.insecure = true: listen on HTTP inside the cluster. The ALB holds the cert.
        params = {
          "server.insecure" = true
        }
      }
    })
  ]
}

# Public ALB Ingress. ACM cert on 443; HTTP:80 redirects to HTTPS.
# group.name shares one ALB with Grafana (and later the demo app Ingress).
resource "kubernetes_ingress_v1" "argocd" {
  wait_for_load_balancer = true

  metadata {
    name      = "argocd"
    namespace = "argocd"

    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/group.name"       = "${var.cluster_name}-public"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/certificate-arn"  = data.terraform_remote_state.acm.outputs.certificate_arn
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "external-dns.alpha.kubernetes.io/hostname"  = var.hostname
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
