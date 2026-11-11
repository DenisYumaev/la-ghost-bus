# Bronze: raw feed snapshots, append-only, never edited (CLAUDE.md hard rule 1).

resource "aws_s3_bucket" "bronze" {
  # Bucket names are global across all AWS accounts; the account ID makes it unique.
  bucket = "la-ghost-bus-bronze-${data.aws_caller_identity.current.account_id}"

  # Refuse to delete a bucket that still holds objects, even outside Terraform plans.
  force_destroy = false

  lifecycle {
    # Terraform errors out on any plan that would destroy this bucket.
    prevent_destroy = true
  }
}

# Versioning: an accidental overwrite or delete keeps the old bytes as a
# recoverable noncurrent version. prevent_destroy protects the bucket;
# versioning protects the objects in it.
resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block every path to public access, including future ACLs or policies.
resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely; access is controlled by IAM and bucket policy only.
resource "aws_s3_bucket_ownership_controls" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3 (AES-256). This is the AWS default; stating it makes it reviewable.
# SSE-KMS was rejected: it adds a per-request KMS charge on ~10k writes a day.
resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Reject any request not made over TLS.
data "aws_iam_policy_document" "bronze_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.bronze.arn,
      "${aws_s3_bucket.bronze.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  policy = data.aws_iam_policy_document.bronze_tls_only.json

  # Policy must be applied after the public access block exists.
  depends_on = [aws_s3_bucket_public_access_block.bronze]
}

# Cost hygiene only: clean up parts of uploads that never finished.
# Deliberately no expiry rules: nothing in bronze ever expires.
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle config on a versioned bucket must come after versioning.
  depends_on = [aws_s3_bucket_versioning.bronze]
}
