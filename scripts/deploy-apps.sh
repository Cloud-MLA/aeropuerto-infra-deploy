#!/usr/bin/env bash
# scripts/deploy-apps.sh — (re)levanta los contenedores de una o varias VMs por AWS CLI + SSM
# Run Command, sin abrir sesión de Session Manager ni recrear instancias por Terraform.
#
# Reemplaza los pasos manuales del RUNBOOK Parte 2.3/2.4 ("SSM a la VM -> docker compose
# pull/up") por un solo comando. Pensado sobre todo para VM-PROD: el user_data de Terraform
# ya deja /opt/prod con docker-compose.yml/.env/nginx.conf, pero MS1..5 pueden no existir
# todavía en Docker Hub cuando la instancia arranca — corre esto cuando ya estén publicadas
# (o cada vez que publiques un tag nuevo) para que la VM las traiga sin recrearla.
#
# Requiere: AWS CLI v2 configurado con las credenciales temporales del Learner Lab
# (las mismas que exportas para Terraform — AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN) y que las
# instancias estén "running" con el agente SSM registrado (RUNBOOK 1.5).
#
# Uso:
#   ./scripts/deploy-apps.sh vm-db
#   ./scripts/deploy-apps.sh vm-prod
#   ./scripts/deploy-apps.sh vm-ingesta
#   ./scripts/deploy-apps.sh all

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TARGET="${1:-}"

usage() {
  echo "Uso: $0 {vm-db|vm-prod|vm-ingesta|all}" >&2
  exit 1
}

[ -n "$TARGET" ] || usage

# tag Name -> directorio remoto con el docker-compose.yml
declare -A DIR_BY_TAG=(
  ["VM-DB"]="/opt/db"
  ["VM-PROD-1"]="/opt/prod"
  ["VM-PROD-2"]="/opt/prod"
  ["VM-INGESTA"]="/opt/ingesta"
)

tags_for_target() {
  case "$1" in
    vm-db)      echo "VM-DB" ;;
    vm-prod)    echo "VM-PROD-1 VM-PROD-2" ;;
    vm-ingesta) echo "VM-INGESTA" ;;
    all)        echo "VM-DB VM-PROD-1 VM-PROD-2 VM-INGESTA" ;;
    *)          usage ;;
  esac
}

instance_id_for_tag() {
  local tag="$1"
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${tag}" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[0].InstanceId" \
    --output text
}

deploy_one() {
  local tag="$1"
  local dir="${DIR_BY_TAG[$tag]}"
  local instance_id
  instance_id="$(instance_id_for_tag "$tag")"

  if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
    echo "[$tag] sin instancia 'running' — sáltala (¿Start pendiente en EC2? ¿terraform apply corrido?)" >&2
    return 1
  fi

  echo "[$tag] $instance_id -> docker compose pull/up en $dir"

  local command_id
  command_id="$(aws ssm send-command \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$instance_id" \
    --comment "deploy-apps.sh: $tag" \
    --parameters "commands=[\"cd $dir && docker compose pull --ignore-pull-failures && docker compose up -d --remove-orphans && docker compose ps\"]" \
    --query "Command.CommandId" \
    --output text)"

  aws ssm wait command-executed \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$instance_id" 2>/dev/null || true

  local status
  status="$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --query "Status" \
    --output text)"

  echo "--- [$tag] salida (status: $status) ---"
  aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --query "StandardOutputContent" \
    --output text

  if [ "$status" != "Success" ]; then
    echo "--- [$tag] stderr ---" >&2
    aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --query "StandardErrorContent" \
      --output text >&2
    return 1
  fi
}

failed=0
for tag in $(tags_for_target "$TARGET"); do
  deploy_one "$tag" || failed=1
done

exit "$failed"
