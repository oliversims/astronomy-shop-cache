# Private subnet IDs — passed to EKS so nodes and control-plane ENIs sit off the public internet.
output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}
