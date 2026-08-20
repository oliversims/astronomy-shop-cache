# AWS region for IAM, the EKS addon, and the controller Helm values.
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Must match the cluster created by 02-eks.
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "my-eks-cluster"
}
