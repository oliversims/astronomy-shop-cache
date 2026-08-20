# AWS region for EKS auth and remote state.
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

# Public hostname for Argo CD. Must be covered by the 03-acm wildcard certificate.
variable "hostname" {
  description = "Public DNS hostname for Argo CD"
  type        = string
  default     = "argocd.simsoliver.com"
}
