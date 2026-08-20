# -----------------------------------------------------------------------------
# Stack: 07-monitoring
# kube-prometheus-stack (Prometheus, Grafana, Alertmanager, exporters).
# Only Grafana is public (HTTPS). Apply after 03-acm, 04-alb, and 05-external-dns.
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
    key            = "07-monitoring/terraform.tfstate"
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

# ACM certificate ARN from 03-acm (wildcard covers grafana.<domain>).
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

# Kubernetes provider for the Grafana Ingress object.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Prometheus Operator + Prometheus + Grafana + Alertmanager + node/kube exporters.
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "70.4.0"
  namespace        = "monitoring"
  create_namespace = true

  wait    = true
  timeout = 900

  values = [
    yamlencode({
      # Grafana is ClusterIP; the Ingress below is the public HTTPS front door.
      grafana = {
        adminUser                = "admin"
        defaultDashboardsEnabled = true
        # Plugin so Grafana can query OpenSearch (shop logs in otel-demo).
        plugins                  = ["grafana-opensearch-datasource"]
        "grafana.ini" = {
          server = {
            domain   = var.hostname
            root_url = "https://${var.hostname}/"
          }
        }
        # Prometheus stays the default datasource (cluster + shop metrics).
        # OpenSearch is extra: diary lines from otelcol (index otel).
        additionalDataSources = [
          {
            name      = "OpenSearch"
            type      = "grafana-opensearch-datasource"
            url       = "http://opentelemetry-demo-opensearch.otel-demo.svc.cluster.local:9200"
            access    = "proxy"
            isDefault = false
            jsonData = {
              database        = "otel"
              flavor          = "opensearch"
              logLevelField   = "severity"
              logMessageField = "body"
              pplEnabled      = true
              timeField       = "observedTimestamp"
              version         = "2.18.0"
            }
          }
        ]
      }
      prometheus = {
        prometheusSpec = {
          # Accept OTLP metrics from otelcol (namespace otel-demo).
          # POST http://...prometheus:9090/api/v1/otlp
          enableOTLPReceiver = true
          # Pick up ServiceMonitors in any namespace (not only this Helm release).
          serviceMonitorSelectorNilUsesHelmValues = false
          serviceMonitorSelector                  = {}
          serviceMonitorNamespaceSelector         = {}
        }
      }
      # EKS control plane is AWS-managed; these scrapes would fail.
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeEtcd              = { enabled = false }
    })
  ]
}

# Public ALB Ingress for Grafana only. ACM on 443; ExternalDNS creates the record.
# group.name shares one ALB with Argo CD instead of creating a second load balancer.
resource "kubernetes_ingress_v1" "grafana" {
  wait_for_load_balancer = true

  metadata {
    name      = "grafana"
    namespace = "monitoring"

    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/group.name"       = "${var.cluster_name}-public"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/certificate-arn"  = data.terraform_remote_state.acm.outputs.certificate_arn
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
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
              name = "kube-prometheus-stack-grafana"

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
