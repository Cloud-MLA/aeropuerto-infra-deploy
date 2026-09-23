#!/usr/bin/env bash
# scripts/reactivar-sesion.sh — RUNBOOK Parte 2 automatizada: deja todo operativo tras
# reactivar una sesión cortada del Learner Lab (objetivo < 15 min).
#
# Requiere: credenciales AWS de la sesión nueva ya configuradas (aws configure / .aws/credentials)
# y las 4 EC2 ya creadas por Terraform (no crea infra nueva, solo la reactiva).
#
# Uso:
#   ./scripts/reactivar-sesion.sh            # todo el flujo
#   ./scripts/reactivar-sesion.sh --check    # solo diagnostico, no arranca ni modifica nada
#
# Qué hace, en orden:
#   1. Verifica que las credenciales AWS sean válidas.
#   2. Arranca las 4 EC2 si están 'stopped' (Start) y espera a que pasen los status checks.
#   3. docker compose up -d en VM-DB, VM-PROD-1, VM-PROD-2 (VM-INGESTA no es un servicio
#      persistente -- sus 3 contenedores son jobs one-shot, no hace falta "levantarlos").
#   4. Verifica que los 2 targets del ALB queden 'healthy'.
#   5. Prueba la URL pública de API Gateway.
#   6. Imprime un resumen final en verde/rojo por componente.

set -uo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$HERE/../terraform"

FAIL=0
pass() { echo "  OK   $1"; }
fail() { echo "  FAIL $1"; FAIL=1; }
info() { echo "  ..   $1"; }

echo "=== 1. Credenciales AWS ==="
if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
  fail "credenciales AWS invalidas o sesion del Lab no iniciada -- correr 'aws configure' primero"
  exit 1
fi
pass "credenciales validas ($(aws sts get-caller-identity --query Arn --output text 2>/dev/null))"

echo "=== 2. Estado e inicio de las 4 EC2 ==="
INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=VM-PROD-1,VM-PROD-2,VM-DB,VM-INGESTA" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,State.Name]' \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  fail "no se encontraron las 4 EC2 (VM-PROD-1/2, VM-DB, VM-INGESTA) -- correr terraform apply primero"
  exit 1
fi

echo "$INSTANCE_IDS" | while read -r name id state; do
  echo "  $name ($id): $state"
done

STOPPED_IDS=$(echo "$INSTANCE_IDS" | awk '$3=="stopped"{print $2}')
if [ -n "$STOPPED_IDS" ]; then
  if [ "$CHECK_ONLY" = "1" ]; then
    info "hay instancias detenidas, pero --check no las arranca"
  else
    echo "Arrancando: $STOPPED_IDS"
    aws ec2 start-instances --region "$REGION" --instance-ids $STOPPED_IDS >/dev/null
    echo "Esperando status checks (2/2)..."
    aws ec2 wait instance-status-ok --region "$REGION" --instance-ids $STOPPED_IDS
  fi
fi

VMDB_ID=$(echo "$INSTANCE_IDS" | awk '$1=="VM-DB"{print $2}')
VMPROD1_ID=$(echo "$INSTANCE_IDS" | awk '$1=="VM-PROD-1"{print $2}')
VMPROD2_ID=$(echo "$INSTANCE_IDS" | awk '$1=="VM-PROD-2"{print $2}')
ALL_RUNNING=$(echo "$INSTANCE_IDS" | awk '$3!="running"' | wc -l | tr -d ' ')
if [ "$ALL_RUNNING" = "0" ]; then
  pass "las 4 instancias 'running'"
else
  info "algunas instancias no estan 'running' todavia (revisar arriba)"
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo "=== --check: no se toca docker compose, solo diagnostico de infra ==="
else
  echo "=== 3. docker compose up -d en VM-DB y VM-PROD ==="
  for entry in "$VMDB_ID:/opt/db" "$VMPROD1_ID:/opt/prod" "$VMPROD2_ID:/opt/prod"; do
    id="${entry%%:*}"; dir="${entry##*:}"
    [ -z "$id" ] && continue
    echo "  $id ($dir)..."
    CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$id" \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=[\"cd $dir && sudo docker compose up -d && sudo docker compose ps\"]" \
      --query "Command.CommandId" --output text)
    aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$id" 2>/dev/null || true
    STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$id" --query Status --output text)
    if [ "$STATUS" = "Success" ]; then
      pass "$id: docker compose up -d OK"
    else
      fail "$id: docker compose up -d fallo (status=$STATUS) -- revisar con SSM a mano"
    fi
  done
fi

echo "=== 4. Targets del ALB ==="
TG_ARN=$(aws elbv2 describe-target-groups --region "$REGION" --names tg-vm-prod --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  fail "no se encontro el target group tg-vm-prod"
else
  echo "Esperando healthchecks del ALB (hasta 90s)..."
  for i in $(seq 1 9); do
    UNHEALTHY=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
      --query "length(TargetHealthDescriptions[?TargetHealth.State!='healthy'])" --output text)
    [ "$UNHEALTHY" = "0" ] && break
    sleep 10
  done
  aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State}' --output table
  if [ "$UNHEALTHY" = "0" ]; then pass "2/2 targets healthy"; else fail "targets sin quedar healthy a tiempo"; fi
fi

echo "=== 5. API Gateway público ==="
API_URL="$(terraform -chdir="$TF_DIR" output -raw api_invoke_url 2>/dev/null)"
if [ -z "$API_URL" ]; then
  fail "no se pudo leer api_invoke_url de terraform output"
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$API_URL/api/pasajeros/health")
  if [ "$CODE" = "200" ]; then
    pass "API Gateway ($API_URL) responde 200"
  else
    fail "API Gateway respondio $CODE (esperado 200) -- puede tardar unos minutos mas en propagar"
  fi
fi

echo "==="
if [ "$FAIL" -eq 0 ]; then
  echo "RESULTADO: VERDE — todo operativo."
else
  echo "RESULTADO: ROJO — revisar los FAIL de arriba. Ver RUNBOOK.md Parte 2 para el detalle manual."
fi
exit "$FAIL"
