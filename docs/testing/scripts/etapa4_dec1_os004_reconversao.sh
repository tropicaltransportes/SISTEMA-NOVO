#!/usr/bin/env bash
# ETAPA 4 (P1-A) — Decisão de negócio #1: orçamento pós-cancelamento de OS.
# Regra formalizada: nunca mais de uma OS NÃO CANCELADA por orçamento; OS
# cancelada libera o orçamento para nova conversão; histórico mantém todas.
# O código (rpc_criar_os, checagem "status <> 'cancelada'") já implementa
# exatamente essa regra desde a ETAPA 3 (P0-03) — esta rodada só formaliza
# em BUSINESS_RULES.md e confirma com um cenário completo e uma 3a
# conversão bloqueada (não testado antes).
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
rpc() { call "$1" POST "$2" "$URL/rest/v1/rpc/$3" "$4"; }
tbl_post() { call "$1" POST "$2" "$URL/rest/v1/$3" "$4"; }
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# SETUP: orcamento novo aprovado (interno, sem exigir comprovante)"
echo "############################################"
tbl_post "cria orcamento" "$TOK_ENC" orcamentos \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000002","cliente_id":"b0000000-0000-0000-0000-000000000002","criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item" "$TOK_ENC" orcamento_itens "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE P1A OS-004\",\"quantidade\":1,\"valor_unitario\":50}"
rpc "envia" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "aprova (cliente interno, sem exigir autorizacao)" "$TOK_ENC" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
echo "ORC=$ORC"

echo
echo "############################################"
echo "# 1: orcamento SEM OS -> converter cria normalmente"
echo "############################################"
rpc "1a conversao" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000002\",\"p_tipo\":\"interna\",\"p_orcamento_id\":\"$ORC\"}"
OS1=$(echo "$BODY" | tr -d '"')
echo "OS1=$OS1"

echo
echo "############################################"
echo "# 2: orcamento COM OS ATIVA -> nova conversao deve BLOQUEAR"
echo "############################################"
rpc "tenta 2a conversao com OS1 ainda ativa" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000002\",\"p_tipo\":\"interna\",\"p_orcamento_id\":\"$ORC\"}"

echo
echo "############################################"
echo "# 3: cancela OS1 -> orcamento COM OS cancelada -> nova conversao deve PERMITIR"
echo "############################################"
rpc "cancela OS1" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS1\",\"p_novo_status\":\"cancelada\"}"
rpc "2a conversao (OS1 agora cancelada) -- deve criar OS2" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000002\",\"p_tipo\":\"interna\",\"p_orcamento_id\":\"$ORC\"}"
OS2=$(echo "$BODY" | tr -d '"')
echo "OS2=$OS2"

echo
echo "############################################"
echo "# 4: orcamento COM OS cancelada (OS1) + OS ativa (OS2) -> 3a conversao deve BLOQUEAR"
echo "############################################"
rpc "tenta 3a conversao com OS2 ativa" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000002\",\"p_tipo\":\"interna\",\"p_orcamento_id\":\"$ORC\"}"

echo
echo "############################################"
echo "# 5: cancela OS2 tambem -> agora 2 OS canceladas -> nova conversao (3a de verdade) deve PERMITIR de novo"
echo "############################################"
rpc "cancela OS2" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS2\",\"p_novo_status\":\"cancelada\"}"
rpc "3a conversao real (OS1 e OS2 ambas canceladas)" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000002\",\"p_tipo\":\"interna\",\"p_orcamento_id\":\"$ORC\"}"
OS3=$(echo "$BODY" | tr -d '"')
echo "OS3=$OS3"

echo
echo "############################################"
echo "# HISTORICO: todas as OS deste orcamento continuam consultaveis (nada apagado/ocultado)"
echo "############################################"
call "SELECT todas as OS do orcamento" GET "$TOK_ENC" "$URL/rest/v1/ordens_servico?orcamento_id=eq.$ORC&select=id,status&order=data_abertura.asc"

echo
echo "ORC=$ORC OS1=$OS1(cancelada) OS2=$OS2(cancelada) OS3=$OS3(ativa)"
echo "=== FIM ==="
