# Configure the S3 backend for state storage (must be at the beginning)
terraform {
  backend "s3" {
    bucket         = "craftapp-state-bucket"  # Your existing state bucket name
    key            = "backend-bucket/terraform.tfstate"
    region         = "eu-north-1"     # Change to your region
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create S3 Bucket for Backend Storage
resource "aws_s3_bucket" "backend_bucket" {
  bucket = "${var.project}-${var.region}-backend-${random_id.bucket_suffix.hex}"
  force_destroy = true
  
  tags = {
    Name        = "${var.project}-backend-bucket-${random_id.bucket_suffix.hex}"
    Project     = var.project
    Environment = var.environment
  }
}

# Enable versioning for backup/recovery
resource "aws_s3_bucket_versioning" "backend_versioning" {
  bucket = aws_s3_bucket.backend_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access (recommended for backend storage)
resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.backend_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Set bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "backend_ownership" {
  bucket = aws_s3_bucket.backend_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# IAM Policy for Backend Access
resource "aws_iam_policy" "backend_s3_access" {
  name        = "${var.project}-backend-s3-access"
  description = "Allows backend service to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource = [
          aws_s3_bucket.backend_bucket.arn,
          "${aws_s3_bucket.backend_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create DynamoDB table for state locking (if it doesn't exist)
resource "aws_dynamodb_table" "terraform_lock" {
  name           = "terraform-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform Lock Table"
  }
}

# Output the bucket name and ARN for reference
output "s3_bucket_name" {
  value = aws_s3_bucket.backend_bucket.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.backend_bucket.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.backend_s3_access.arn
}
