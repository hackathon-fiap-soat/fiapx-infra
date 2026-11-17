# Bucket de vídeos (ADR-006): Block Public Access, SSE-S3, CORS só para o POST de upload vindo do site,
# lifecycle e notificação ObjectCreated em uploads/ para a fila video-uploaded.
module "bucket" {
  source        = "../s3-bucket"
  name          = var.bucket_name
  force_destroy = !var.protect
}

# Bucket criado antes desta mudança pelo aws_s3_bucket: sai do state sem ser apagado.
removed {
  from = aws_s3_bucket.videos
  lifecycle {
    destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "videos" {
  bucket                  = module.bucket.name
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "videos" {
  bucket = module.bucket.name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "videos" {
  bucket = module.bucket.name
  cors_rule {
    allowed_origins = [var.web_origin]
    allowed_methods = ["POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "videos" {
  bucket = module.bucket.name
  rule {
    id     = "expira-uploads"
    status = "Enabled"
    filter {
      prefix = "uploads/"
    }
    expiration {
      days = 7
    }
  }
  rule {
    id     = "expira-results"
    status = "Enabled"
    filter {
      prefix = "results/"
    }
    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_notification" "videos" {
  bucket = module.bucket.name
  queue {
    id            = "uploads-para-video-uploaded"
    queue_arn     = var.video_uploaded_queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
}
