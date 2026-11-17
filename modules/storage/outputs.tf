output "bucket" {
  value = aws_s3_bucket.videos.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.videos.arn
}
