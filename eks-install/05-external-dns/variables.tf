# AWS region for IAM and the ExternalDNS add-on.
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

# Public domain ExternalDNS is allowed to create records in.
variable "domain_name" {
  description = "Route 53 hosted zone / domain filter for ExternalDNS"
  type        = string
  default     = "simsoliver.com"
}
