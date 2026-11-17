output "bucket" {
  value = aws_s3_bucket.web.bucket
}

output "url" {
  description = "URL pública do site (HTTP)."
  value       = "http://${aws_s3_bucket_website_configuration.web.website_endpoint}"
}
