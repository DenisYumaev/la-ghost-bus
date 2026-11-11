output "bronze_bucket_name" {
  description = "Set as BRONZE_BUCKET in .env for the poller."
  value       = aws_s3_bucket.bronze.bucket
}

output "bronze_bucket_arn" {
  value = aws_s3_bucket.bronze.arn
}
