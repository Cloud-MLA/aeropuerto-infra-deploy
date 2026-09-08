#!/bin/bash
# smoke-e2e.sh — Prueba de humo end-to-end (BE-INT-08) por la URL pública de API Gateway.
# Verifica: healths de los 5 MS + flujo MS1→MS2→MS4 + una consulta analítica de MS5.
#
# Uso:  BASE="https://<api-id>.execute-api.us-east-1.amazonaws.com" ./smoke-e2e.sh
set -uo pipefail

BASE=${BASE:?define BASE con la URL de API Gateway}
PASS=0 FAIL=0

check() { # descripcion  esperado_regex  comando...
  local desc=$1 want=$2; shift 2
  local out; out=$("$@" 2>&1)
  if echo "$out" | grep -Eq "$want"; then
    printf '  OK   %s\n' "$desc"; PASS=$((PASS+1))
  else
    printf '  FAIL %s\n       -> %s\n' "$desc" "$(echo "$out" | head -c 300)"; FAIL=$((FAIL+1))
  fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
body() { curl -s "$@"; }

echo "== Healths =="
check "MS1 /health"           '"?(status|UP|ok)"?' body "$BASE/api/pasajeros/health"
check "MS2 /health"           '"?(status|UP|ok)"?' body "$BASE/api/vuelos/health"
check "MS3 /health"           '"?(status|UP|ok)"?' body "$BASE/api/infra/health"
check "MS4 /health"           '"?(status|UP|ok)"?' body "$BASE/api/manifiesto/health"
check "MS5 /health"           '"?(status|UP|ok)"?' body "$BASE/api/analitica/health"

echo "== Consumo entre servicios =="
check "POST /tickets con vuelo inexistente -> 422" '^422$' \
  code -X POST "$BASE/api/pasajeros/tickets" -H 'content-type: application/json' \
  -d '{"pasajero_id": 100001, "vuelo_id": 999999}'

check "GET /vuelos lista"     '\[|\{'      body "$BASE/api/vuelos?limit=1"
check "GET /vuelos/1/exists"  'exists'     body "$BASE/api/vuelos/1/exists"
check "GET /manifiesto/1"     'vuelo|404' body "$BASE/api/manifiesto/manifiesto/1"

echo "== Analítica (MS5 <- Athena) =="
check "GET /analitica/recursos-mas-fallas" '\[|\{|rows' body "$BASE/api/analitica/recursos-mas-fallas?dias=7"

echo
echo "Resultado: $PASS OK, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
