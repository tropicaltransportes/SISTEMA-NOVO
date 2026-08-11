#!/usr/bin/env bash
# ETAPA 4 (P1-A) — item B (CAD-004) e item C (ORC-016), execução real.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  if [ -n "$body" ]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | head -n -1)
  echo "HTTP $HTTP_CODE"
  echo "$BODY"
}
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# CAD-004 — documento duplicado (normalizado)"
echo "############################################"
DOC="55555555000199"
call "cria cliente A com documento $DOC" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1A_CAD004_A\",\"documento\":\"$DOC\"}"
CLI_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLI_A=$CLI_A"

call "tenta criar cliente B com o MESMO documento (identico)" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1A_CAD004_B_IDENTICO\",\"documento\":\"$DOC\"}"
echo "^^^ esperado: HTTP 409 (conflict), nenhum cliente criado"

call "tenta criar cliente C com o MESMO documento, MASCARA diferente (pontuacao)" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1A_CAD004_C_MASCARA\",\"documento\":\"55.555.555/0001-99\"}"
echo "^^^ esperado: HTTP 409 (mesmo documento normalizado, mascara diferente)"

call "cria cliente D com documento nulo (permitido, cliente interno)" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  '{"tipo":"interno","nome":"TESTE_P1A_CAD004_D_SEMDOC","documento":null}'
call "cria cliente E TAMBEM com documento nulo (deve ser permitido, nulo nao concorre)" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  '{"tipo":"interno","nome":"TESTE_P1A_CAD004_E_SEMDOC","documento":null}'
echo "^^^ esperado: ambos HTTP 201 (documento nulo nunca bloqueia)"

echo "--- inativa cliente A ---"
call "inativa cliente A (deleted_at)" PATCH "$TOK_ENC" "$URL/rest/v1/clientes?id=eq.$CLI_A" '{"deleted_at":"2026-08-12T00:00:00Z"}'

call "agora cria cliente F com o MESMO documento do A (que esta INATIVO) -> deve ser PERMITIDO" POST "$TOK_ENC" "$URL/rest/v1/clientes" \
  "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1A_CAD004_F_REATIVA_DOC\",\"documento\":\"$DOC\"}"
echo "^^^ esperado: HTTP 201 (cliente inativo nao bloqueia reaproveitamento do documento)"

echo
echo "############################################"
echo "# ORC-016 — duplo submit de orcamento (2 chamadas paralelas, mesma client_request_id)"
echo "############################################"
CRI=$(python -c "import uuid; print(uuid.uuid4())")
echo "client_request_id=$CRI"
VEICULO_ID=$(curl -s "$URL/rest/v1/veiculos?select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
CLIENTE_ID=$(curl -s "$URL/rest/v1/veiculos?id=eq.$VEICULO_ID&select=cliente_id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['cliente_id'] if d else '')")
ENC_ID="a0000000-0000-0000-0000-000000000002"
echo "VEICULO_ID=$VEICULO_ID CLIENTE_ID=$CLIENTE_ID"

disparar() {
  curl -s -o /tmp/orc_dup_$1.json -w '%{http_code}' -X POST "$URL/rest/v1/orcamentos" \
    -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\",\"client_request_id\":\"$CRI\"}" > /tmp/orc_dup_code_$1.txt
}
disparar 1 &
disparar 2 &
wait
echo "chamada 1 -> HTTP $(cat /tmp/orc_dup_code_1.txt) | corpo: $(cat /tmp/orc_dup_1.json)"
echo "chamada 2 -> HTTP $(cat /tmp/orc_dup_code_2.txt) | corpo: $(cat /tmp/orc_dup_2.json)"

echo "--- confirma no banco: quantos orcamentos existem com essa client_request_id? (deve ser exatamente 1) ---"
curl -s "$URL/rest/v1/orcamentos?client_request_id=eq.$CRI&select=id,client_request_id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"
echo

echo "=== FIM ==="
