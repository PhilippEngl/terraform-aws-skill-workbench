terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.61, < 7.0"
    }
  }
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Non-negotiable in this module. A bucket created here is never public.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs entirely, so access is governed by policy alone.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # Cuts KMS request costs substantially for object-heavy buckets.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.lifecycle_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # Noncurrent version rules are meaningless until versioning exists.
  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Object-level events to EventBridge. On by default because it costs nothing on its own —
# events reach the default bus and are discarded unless a rule matches — and because it is
# the hook a tamper-detection rule needs.
resource "aws_s3_bucket_notification" "this" {
  count = var.eventbridge_notifications ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# Server access logs. Delivery is best-effort and can lag by hours, so this is an audit
# record rather than a monitoring signal — the thing you read after the fact to establish
# who touched the bucket, not the thing that tells you it happened.
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_target_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}
