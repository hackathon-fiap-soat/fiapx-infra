# Site do fiapx-web em S3 static website (ADR-019; o CloudFront é negado na AWS Academy). Leitura pública só
# dos objetos; o index.html também é o documento de erro, para as rotas do React funcionarem em qualquer
# caminho. O conteúdo é publicado pelo deploy do fiapx-web.
resource "aws_s3_bucket" "web" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LeituraPublicaDoSite"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.web]
}
