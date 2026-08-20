# Later stacks read this from local 00-s3 state (or the apply/destroy scripts).
output "state_bucket_name" {
  description = "S3 bucket that holds remote Terraform state for stacks 01–07"
  value       = aws_s3_bucket.terraform_state.id
}
