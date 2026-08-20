# AWS region for the EKS cluster and IAM roles.
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Name of the EKS cluster and prefix for related IAM roles.
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "my-eks-cluster"
}

# Kubernetes version for the control plane. Must be on EKS standard or extended support.
variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

# Map of managed node groups. Key = node group name.
# capacity_type is ON_DEMAND or SPOT; scaling_config sets ASG min/desired/max.
variable "node_groups" {
  description = "EKS node group configuration"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      scaling_config = {
        desired_size = 4
        max_size     = 4
        min_size     = 1
      }
    }
  }
}
