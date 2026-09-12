# RUNBOOK.md 1.3 — bucket del data lake + prefijos.

resource "aws_s3_bucket" "lake" {
  bucket = var.bucket_name
  tags   = { Name = "aeropuerto-lake" }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "prefixes" {
  for_each = toset(["raw/", "athena-results/", "backups/"])
  bucket   = aws_s3_bucket.lake.id
  key      = each.value
  content  = ""
}
