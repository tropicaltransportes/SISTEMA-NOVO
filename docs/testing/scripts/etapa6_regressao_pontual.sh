#!/usr/bin/env bash
# ETAPA 6 (P1-C) — item 18: regressao pontual dos comportamentos criticos de
# rodadas anteriores que NAO fazem parte dos dois E2E principais desta
# rodada, mas cujo codigo (RLS/RPC) poderia ter sido afetado indiretamente
# por mudancas de schema (novas colunas nao-nulas, novas policies, etc.).
# pgTAP (supabase/tests/*.sql) nao pode ser executado neste ambiente (test db
# --linked exige Docker, indisponivel aqui -- mesma limitacao ja documentada
# em rodadas anteriores). Cobertura via REST direta, mesmo padrao dos
# scripts etapa3_*/etapa4_*.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_INATIVO=$(login "teste.inativo@qa.local")
TS=$(date +%s)

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
rpc() { call "$1" POST "$2" "$URL/rest/v1/rpc/$3" "$4"; }
tbl_post() { call "$1" POST "$2" "$URL/rest/v1/$3" "$4"; }
tbl_get() { call "$1" GET "$2" "$URL/rest/v1/$3"; }
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# AUT-004 (P1-A, decisao de negocio #2): usuario inativo continua bloqueado (leitura + escrita) apos as migrations desta rodada"
echo "############################################"
tbl_get "usuario INATIVO tenta LER clientes -- esperado 0 linhas (nao erro, mas vazio) ou bloqueio" "$TOK_INATIVO" "clientes?limit=1"
rpc "usuario INATIVO tenta criar centro de custo (RPC nova) -- deve BLOQUEAR" "$TOK_INATIVO" rpc_criar_centro_custo "{\"p_nome\":\"TESTE_REGRESSAO_NAO_DEVE_EXISTIR_$TS\"}"

echo
echo "############################################"
echo "# CAD-004 (P1-A): documento duplicado entre 2 clientes ATIVOS continua bloqueado"
echo "############################################"
tbl_post "cria cliente A com documento" "$TOK_SUP" "clientes" "{\"tipo\":\"externo\",\"nome\":\"TESTE_REGRESSAO_DOC_A_$TS\",\"documento\":\"777$TS\",\"telefone\":\"1\"}"
tbl_post "cria cliente B com MESMO documento -- deve BLOQUEAR (409/23505)" "$TOK_SUP" "clientes" "{\"tipo\":\"externo\",\"nome\":\"TESTE_REGRESSAO_DOC_B_$TS\",\"documento\":\"777$TS\",\"telefone\":\"2\"}"

echo
echo "############################################"
echo "# ORC-016 (P1-A): idempotencia de criacao de orcamento (client_request_id) continua funcionando"
echo "############################################"
tbl_post "cria cliente p/ idempotencia" "$TOK_SUP" "clientes" "{\"tipo\":\"externo\",\"nome\":\"TESTE_REGRESSAO_IDEMP_$TS\",\"documento\":\"888$TS\",\"telefone\":\"1\"}"
CLI=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "cria veiculo p/ idempotencia" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLI\",\"placa\":\"REG$TS\",\"modelo\":\"TESTE\"}"
VEI=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
CRI="a1b2c3d4-0000-0000-0000-$(printf '%012d' "$TS")"
ENC_ID="a0000000-0000-0000-0000-000000000002"
tbl_post "1a chamada (client_request_id)" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEI\",\"cliente_id\":\"$CLI\",\"criado_por\":\"$ENC_ID\",\"client_request_id\":\"$CRI\"}"
tbl_post "2a chamada RETRY (MESMO client_request_id) -- deve BLOQUEAR 409" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEI\",\"cliente_id\":\"$CLI\",\"criado_por\":\"$ENC_ID\",\"client_request_id\":\"$CRI\"}"
tbl_get "confirma so 1 orcamento criado com esse client_request_id" "$TOK_ENC" "orcamentos?client_request_id=eq.$CRI&select=id"

echo
echo "############################################"
echo "# BR-027: auditoria continua append-only (tentativa de UPDATE/DELETE direto -- deve BLOQUEAR)"
echo "############################################"
tbl_get "pega 1 evento de auditoria qualquer" "$TOK_ENC" "auditoria_eventos?select=id&limit=1"
AUD_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
call "tenta UPDATE direto em auditoria_eventos -- deve BLOQUEAR/0 linhas" PATCH "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?id=eq.$AUD_ID" '{"motivo":"TENTATIVA_REGRESSAO_NAO_DEVE_FUNCIONAR"}'
tbl_get "confirma motivo NAO foi alterado" "$TOK_ENC" "auditoria_eventos?id=eq.$AUD_ID&select=motivo"

echo
echo "############################################"
echo "# BR-023/liberacao: continua exigindo cobranca gerada antes de liberar OS externa (regra pre-existente, nao tocada nesta rodada)"
echo "############################################"
rpc "tenta liberar OS externa inexistente -- so confirma que a RPC segue validando (nao regressao de acesso)" "$TOK_ENC" rpc_liberar_os "{\"p_os_id\":\"00000000-0000-0000-0000-000000000000\"}"

echo
echo "=== FIM REGRESSAO PONTUAL ==="
