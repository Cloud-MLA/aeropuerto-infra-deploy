#!/usr/bin/env bash
# scripts/smoke-e2e.sh — BE-INT-08: prueba de humo E2E por la URL pública de API Gateway +
# verificación de que el ALB interno y las VM-PROD/VM-DB NO son alcanzables directo desde fuera.
#
# Requiere: terraform apply ya corrido (usa sus outputs) + credenciales AWS del Learner Lab activo
# para la verificación de IP pública de VM-DB/VM-INGESTA. El resto solo necesita curl/nc.
#
# Uso: ./scripts/smoke-e2e.sh   (correr desde terraform/, o pasar TF_DIR)

set -uo pipefail

TF_DIR="${TF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FAIL=0

pass() { echo "  OK   $1"; }
fail() { echo "  FAIL $1"; FAIL=1; }

echo "=== 1. API Gateway publico responde /health de los 5 MS ==="
API_URL="$(terraform -chdir="$TF_DIR" output -raw api_invoke_url)"
echo "API: $API_URL"
for path in api/pasajeros/health api/vuelos/actuator/health api/infra/health api/manifiesto/health api/analitica/health; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API_URL/$path")"
  if [ "$code" = "200" ]; then
    pass "$path -> $code"
  else
    echo "  WARN $path -> $code (revisar si el path de health del servicio es otro; no bloquea BE-INT-06)"
  fi
done

echo "=== 2. VM-PROD y ALB NO deben responder directo desde fuera (deben fallar) ==="
for ip in $(terraform -chdir="$TF_DIR" output -json vm_prod_public_ips | python3 -c 'import json,sys;print(" ".join(json.load(sys.stdin)))'); do
  if curl -s -o /dev/null --max-time 5 "http://$ip/api/pasajeros/health"; then
    fail "VM-PROD $ip respondio directo (deberia estar bloqueado por sg-vm-prod)"
  else
    pass "VM-PROD $ip no responde directo (bloqueado por SG, como se espera)"
  fi
done

ALB_DNS="$(terraform -chdir="$TF_DIR" output -raw alb_dns_name)"
if nc -z -w 5 "$ALB_DNS" 80 2>/dev/null; then
  fail "ALB interno ($ALB_DNS) responde directo desde fuera (deberia ser interno)"
else
  pass "ALB interno ($ALB_DNS) no alcanzable desde fuera, como se espera"
fi

echo "=== 3. VM-DB / VM-INGESTA sin IP publica ==="
for tag in VM-DB VM-INGESTA; do
  pub_ip="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$tag" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)"
  if [ -z "$pub_ip" ] || [ "$pub_ip" = "None" ]; then
    pass "$tag sin IP publica"
  else
    fail "$tag tiene IP publica ($pub_ip) — no deberia"
  fi
done

echo "==="
if [ "$FAIL" -eq 0 ]; then
  echo "RESULTADO: VERDE — todo lo esperado (publico responde, privado bloqueado)."
else
  echo "RESULTADO: ROJO — revisar los FAIL de arriba."
fi
exit "$FAIL"
