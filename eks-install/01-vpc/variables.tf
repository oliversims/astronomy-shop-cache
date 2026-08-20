# AWS region for the VPC and related networking.
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Used in resource Name tags and kubernetes.io/cluster/... tags.
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "my-eks-cluster"
}

# Primary IPv4 range for the VPC (must be large enough for all subnets below).
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# One AZ per subnet index; keep this list the same length as the subnet CIDR lists.
variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# Private subnets host EKS worker nodes (no direct internet inbound).
variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# Public subnets host NAT gateways and internet-facing load balancers.
variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}
