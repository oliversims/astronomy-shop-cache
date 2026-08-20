# Certificate ARN for the ALB / Ingress (alb.ingress.kubernetes.io/certificate-arn).
output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
