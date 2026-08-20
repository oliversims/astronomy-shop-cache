# AWS region for the state bucket and lock table.
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
