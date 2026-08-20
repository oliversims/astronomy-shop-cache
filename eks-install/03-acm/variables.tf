# AWS region for the ACM certificate. Must match the ALB region.
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Apex domain on the certificate, and the name of the public Route 53 hosted zone.
variable "domain_name" {
  description = "Primary domain name on the ACM certificate"
  type        = string
  default     = "simsoliver.com"
}

# Extra names on the certificate. The wildcard covers hostnames like app.simsoliver.com.
variable "subject_alternative_names" {
  description = "Subject alternative names on the ACM certificate"
  type        = list(string)
  default     = ["*.simsoliver.com"]
}
