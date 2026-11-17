output "name" {
  value = terraform_data.bucket.output.name
}

output "arn" {
  value = "arn:aws:s3:::${terraform_data.bucket.output.name}"
}
