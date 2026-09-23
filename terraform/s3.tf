# RUNBOOK.md 1.3 — bucket del data lake + prefijos.
#
# NO gestionado por Terraform: en cuentas de AWS Academy Learner Lab, el provider AWS intenta
# leer la configuracion de Object Lock del bucket (s3:GetBucketObjectLockConfiguration) en cada
# refresh/plan/apply de "aws_s3_bucket", y esa llamada esta denegada explicitamente por una SCP a
# nivel de organizacion (no configurable desde el Lab). El bucket, el bloqueo de acceso publico y
# los 3 prefijos se crean una vez por CLI y quedan fuera del state para no romper cada apply:
#
#   aws s3api create-bucket --bucket ${var.bucket_name} --region us-east-1
#   aws s3api put-public-access-block --bucket ${var.bucket_name} \
#     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
#   aws s3api put-object --bucket ${var.bucket_name} --key raw/
#   aws s3api put-object --bucket ${var.bucket_name} --key athena-results/
#   aws s3api put-object --bucket ${var.bucket_name} --key backups/
#
# (Ya ejecutado el 2026-09-22 para "mla-aeropuerto-lake" — ver docs/plan/personas/benja.md.)
