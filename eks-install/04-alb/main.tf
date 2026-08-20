# -----------------------------------------------------------------------------
# Stack: 04-alb
# AWS Load Balancer Controller (Helm) plus EKS Pod Identity so it can
# create ALBs from Ingress objects.
# Apply after 02-eks.
# -----------------------------------------------------------------------------

# Pin AWS, Helm, and HTTP providers. HTTP downloads the official LBC IAM policy.
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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }

  # Remote state: S3 holds this stack's state; DynamoDB prevents concurrent applies.
  backend "s3" {
    bucket         = "terraform-eks-state-s3-bucket-u17tc1"
    key            = "04-alb/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# Look up the cluster created by 02-eks (endpoint, CA, VPC ID).
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

# Short-lived token so Helm can talk to the Kubernetes API.
data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# Helm 3 provider: kubernetes is an argument (not a nested block).
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# DaemonSet on every node. Required before pods can assume IAM roles via Pod Identity.
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = data.aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Official IAM policy for the AWS Load Balancer Controller, pinned to the same
# release as the Helm chart below (chart 1.14.1 ships controller v2.14.1).
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json"
}

# IAM policy the controller uses to create ALBs, target groups, and listeners.
resource "aws_iam_policy" "lbc" {
  name   = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lbc_iam_policy.response_body
}

# IAM role the aws-load-balancer-controller service account will assume.
resource "aws_iam_role" "lbc" {
  name = "${var.cluster_name}-lbc-role"

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

# Attach the LBC policy to the role.
resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# Map kube-system/aws-load-balancer-controller to the IAM role above.
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = data.aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}

# Install the controller. It watches Ingress objects and creates AWS ALBs.
resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.1"
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  # Helm 3: set is a list of objects. SA name must match the Pod Identity association.
  # vpcId and region are set here because Pod Identity pods cannot always read them from IMDS.
  set = [
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "clusterName"
      value = data.aws_eks_cluster.main.name
    },
    {
      name  = "vpcId"
      value = data.aws_eks_cluster.main.vpc_config[0].vpc_id
    },
    {
      name  = "region"
      value = var.region
    }
  ]

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.lbc,
    aws_eks_pod_identity_association.lbc
  ]
}
