

terraform {
  backend "s3" {
    bucket         = "craftapp-state-bucket"
    key            = "${var.project}/terraform.tfstate"
    region         = "${var.region}"
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
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "${var.project}-${var.region}-bucket-${random_id.bucket_suffix.hex}"
  force_destroy = true
  
  tags = {
    Name        = "${var.project}-bucket-${random_id.bucket_suffix.hex}"
    Project     = var.project
    Environment = var.environment
  }
}

# Enable versioning for backup/recovery
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access (recommended for backend storage)
resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.s3_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Set bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.s3_bucket.id
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
          aws_s3_bucket.s3_bucket.arn,
          "${aws_s3_bucket.s3_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Output the bucket name and ARN for reference
output "s3_bucket_name" {
  value = aws_s3_bucket.s3_bucket.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.s3_bucket.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.backend_s3_access.arn
}
