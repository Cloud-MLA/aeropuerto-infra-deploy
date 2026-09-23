#!/usr/bin/env bash
# scripts/backup-db.sh — BE-INT-07: formaliza el dump manual del RUNBOOK (Parte 2.x) en un
# comando reproducible por SSM Run Command, sin abrir sesión interactiva en VM-DB.
#
# El script real (scripts/remote/backup-db-remote.sh) se sube a S3 y se ejecuta ahí — evita
# problemas de escapado de variables ($MYSQL_ROOT_PASSWORD, etc.) entre esta máquina y la VM.
#
# Uso: ./scripts/backup-db.sh [bucket]
# Requiere: credenciales AWS del Learner Lab activo + VM-DB "running" con SSM registrado.

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
BUCKET="${1:-mla-aeropuerto-lake}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTANCE_ID="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=VM-DB" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  echo "VM-DB no está 'running' — nada que respaldar." >&2
  exit 1
fi

echo "Subiendo script de backup a S3..."
aws s3 cp "$HERE/remote/backup-db-remote.sh" "s3://$BUCKET/deploy/scripts/backup-db-remote.sh" --region "$REGION" >/dev/null

echo "VM-DB: $INSTANCE_ID -> ejecutando backup hacia s3://$BUCKET/backups/"
CMD_ID="$(aws ssm send-command --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "backup-db.sh" \
  --parameters "commands=[\"aws s3 cp s3://$BUCKET/deploy/scripts/backup-db-remote.sh /tmp/backup-db-remote.sh\",\"chmod +x /tmp/backup-db-remote.sh\",\"/tmp/backup-db-remote.sh $BUCKET\"]" \
  --query "Command.CommandId" --output text)"

aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" 2>/dev/null || true

STATUS="$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query Status --output text)"
echo "--- salida (status: $STATUS) ---"
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query StandardOutputContent --output text
if [ "$STATUS" != "Success" ]; then
  echo "--- stderr ---" >&2
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --query StandardErrorContent --output text >&2
  exit 1
fi

echo "Verificando en S3 (backups mas recientes):"
aws s3 ls "s3://$BUCKET/backups/" --region "$REGION" | tail -5
