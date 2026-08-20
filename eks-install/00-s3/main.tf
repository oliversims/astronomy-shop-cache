# -----------------------------------------------------------------------------
# Stack: 00-s3
# Bootstrap remote state (S3 bucket + DynamoDB lock table).
# Apply this first, using local state. Then apply 01-vpc → 02-eks → 03-acm
# → 04-alb → 05-external-dns → 06-argocd → 07-monitoring.
# -----------------------------------------------------------------------------

# Pin Terraform and the AWS provider so applies stay compatible across machines.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Default AWS provider. Region comes from var.region.
provider "aws" {
  region = var.region
}

# S3 names are global. This suffix makes the bucket unique across all accounts.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Bucket that stores terraform.tfstate for every later stack.
# After apply, paste the bucket name into backend.s3.bucket (and remote_state)
# in 01-vpc → 07-monitoring.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-eks-state-s3-bucket-${random_string.suffix.result}"

  # Block terraform destroy on this bucket. Remove this block first if you
  # really intend to delete remote state.
  lifecycle {
    prevent_destroy = false
  }
}

# Keep previous state versions so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest with SSE-S3 (AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access. State files contain resource IDs and sometimes secrets.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced disables ACLs; this account owns every object.
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuse any request that is not TLS so state cannot be read or written in cleartext.
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.terraform_state.arn,
        "${aws_s3_bucket.terraform_state.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })

  # Public-access block must exist first or the bucket policy can fail to attach.
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# Lock table. Stops two terraform apply runs from writing the same state at once.
# Name must match backend.s3.dynamodb_table in later stacks.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-eks-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  # Partition key Terraform uses to look up the lock item.
  attribute {
    name = "LockID"
    type = "S"
  }
}
