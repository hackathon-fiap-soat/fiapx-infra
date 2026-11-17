# Bucket criado e apagado pelo AWS CLI. Na AWS Academy, uma SCP da organização nega
# s3:GetBucketObjectLockConfiguration, que o recurso aws_s3_bucket sempre lê; por isso o bucket em si fica
# fora do provider (ADR-019). Todas as configurações (BPA, criptografia, CORS, política...) continuam em
# recursos aws_s3_bucket_* que recebem o nome.
resource "terraform_data" "bucket" {
  input = {
    name          = var.name
    region        = var.region
    force_destroy = var.force_destroy
  }

  provisioner "local-exec" {
    command = <<-SH
      set -e
      if aws s3api head-bucket --bucket "${self.input.name}" 2>/dev/null; then
        echo "bucket ${self.input.name} já existe"
      else
        aws s3api create-bucket --bucket "${self.input.name}" --region "${self.input.region}" >/dev/null
        aws s3api wait bucket-exists --bucket "${self.input.name}"
        echo "bucket ${self.input.name} criado"
      fi
    SH
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-SH
      set -e
      aws s3api head-bucket --bucket "${self.input.name}" 2>/dev/null || exit 0
      if [ "${self.input.force_destroy}" = "true" ]; then
        aws s3 rm "s3://${self.input.name}" --recursive --only-show-errors
        # Versões e marcadores de exclusão (se o versionamento tiver sido ligado).
        aws s3api list-object-versions --bucket "${self.input.name}" --output json \
          --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' > /tmp/versoes.json || true
        if grep -q '"Key"' /tmp/versoes.json 2>/dev/null; then
          aws s3api delete-objects --bucket "${self.input.name}" --delete file:///tmp/versoes.json >/dev/null
        fi
      fi
      aws s3api delete-bucket --bucket "${self.input.name}"
    SH
  }
}
