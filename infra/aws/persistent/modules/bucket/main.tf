# One S3 bucket with this repo's baseline applied in the same place it's created: versioning,
# KMS (customer-managed key) encryption, all four public-access blocks, TLS-only access, and
# optionally Object Lock. Keeping the bucket and its controls in one module call is what makes
# the controls checkable -- by a reviewer and by IaC scanners (trivy config) alike.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "object_lock" {
  description = "null for no Object Lock, or { mode = GOVERNANCE|COMPLIANCE, days = N } for a default retention."
  type = object({
    mode = string
    days = number
  })
  default = null
}

resource "aws_s3_bucket" "this" {
  bucket              = var.name
  object_lock_enabled = var.object_lock != null

  # Everything this module holds is meant to outlive the clusters that write to it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = var.object_lock == null ? 0 : 1
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock.mode
      days = var.object_lock.days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

output "id" {
  value = aws_s3_bucket.this.id
}

output "arn" {
  value = aws_s3_bucket.this.arn
}
