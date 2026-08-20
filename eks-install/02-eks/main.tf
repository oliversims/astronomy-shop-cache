# -----------------------------------------------------------------------------
# Stack: 02-eks
# EKS control plane, IAM roles, and managed node groups.
# Apply after 01-vpc. Reads private subnet IDs from that stack's remote state.
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
    key            = "02-eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-eks-state-locks"
    encrypt        = true
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# Read private subnet IDs from the 01-vpc stack.
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "terraform-eks-state-s3-bucket-cqidm4"
    key    = "01-vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# IAM role the EKS control plane assumes to manage AWS resources for the cluster.
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# AWS-managed policy required for the EKS control plane (ENIs, load balancers, etc.).
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# EKS control plane. Subnets here are the private ones from the VPC stack.
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # Place control-plane ENIs in the private subnets.
  # Private endpoint: node-to-API stays in the VPC (does not hairpin via NAT).
  # Public endpoint: kubectl from outside the VPC. Restrict CIDRs in production.
  vpc_config {
    subnet_ids              = data.terraform_remote_state.vpc.outputs.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    # Public API is limited to this machine's current public IP (kubectl / Helm from here).
    # Nodes still use the private endpoint inside the VPC. Update this if your IP changes.
    public_access_cidrs     = ["68.195.155.202/32"]
  }

  # Wait until the cluster IAM policy is attached before creating the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# IAM role assumed by EC2 worker nodes in the managed node groups.
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Worker node policies:
# - AmazonEKSWorkerNodePolicy: join the cluster
# - AmazonEKS_CNI_Policy: manage pod networking (aws-vpc-cni)
# - AmazonEC2ContainerRegistryReadOnly: pull images from ECR
resource "aws_iam_role_policy_attachment" "node_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])

  policy_arn = each.value
  role       = aws_iam_role.node.name
}

# One managed node group per entry in var.node_groups (instance type, capacity, scaling).
# Nodes sit in the same private subnets as the control-plane ENIs.
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # AL2023 is the current EKS-optimized AMI; AL2 is not released for 1.34+.
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  # 50 GiB leaves room for container images (Prometheus + Argo CD + the demo app).
  disk_size      = 50

  # Auto Scaling bounds for this node group.
  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  # Roll at most one node at a time during AMI or version updates.
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy
  ]
}
