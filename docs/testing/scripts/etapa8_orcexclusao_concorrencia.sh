#!/usr/bin/env bash
# ETAPA 8 (FEATURE-ORCAMENTO-EXCLUSAO-01) — ORC-CONC-001, concorrência REAL
# de duas sessões HTTP simultâneas (mesmo padrão de
# docs/testing/scripts/etapa7_concorrencia_setup.sh/_fire.sh): cria um
# rascunho novo e dispara, no MESMO instante, uma chamada a
# rpc_excluir_orcamento_rascunho e uma chamada a rpc_enviar_orcamento sobre
# o mesmo orçamento. O `select ... for update` dentro de cada RPC garante
# que a segunda chamada só roda depois que a primeira já commitou (ou
# reverteu) — o resultado esperado é sempre UMA das duas ganhar e a outra
# falhar com erro específico, nunca os dois efeitos aplicados juntos
# (nunca status='enviado' com deleted_at preenchido ao mesmo tempo).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
OUT=/tmp/etapa8_orcexclusao_conc

login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
CLIENTE_INT="b0000000-0000-0000-0000-000000000002"
VEICULO_INT="c0000000-0000-0000-0000-000000000002"
ENC_ID="a0000000-0000-0000-0000-000000000002"

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo "--- $label ---" >&2
  if [ -n "$body" ]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | head -n -1)
  echo "HTTP $HTTP_CODE" >&2
  echo "$BODY" >&2
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

echo "############### SETUP: rascunho novo, item novo, pronto para a corrida ###############" >&2
TS=$(date +%s)
tbl_post "cria orcamento rascunho" "$TOK_ENC" "orcamentos" \
  "{\"veiculo_id\":\"$VEICULO_INT\",\"cliente_id\":\"$CLIENTE_INT\",\"versao\":1,\"status\":\"rascunho\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC=$ORC" >&2
tbl_post "inclui item" "$TOK_ENC" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE ETAPA8 concorrencia real\",\"quantidade\":1,\"valor_unitario\":100.00}"

rm -f "$OUT"_*.txt

echo >&2
echo "############### DISPARO SIMULTANEO: excluir vs enviar, MESMO orcamento ###############" >&2
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_excluir_orcamento_rascunho" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" \
  -d "{\"p_orcamento_id\":\"$ORC\",\"p_motivo\":\"ETAPA8 corrida - exclusao\"}" \
  > "$OUT"_exclusao.txt 2>&1) &
PID1=$!
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_enviar_orcamento" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" \
  -d "{\"p_orcamento_id\":\"$ORC\"}" \
  > "$OUT"_envio.txt 2>&1) &
PID2=$!
wait $PID1 $PID2
echo "--- resultado exclusao ---" >&2; cat "$OUT"_exclusao.txt >&2
echo "--- resultado envio ---" >&2; cat "$OUT"_envio.txt >&2

echo >&2
echo "############### VERIFICACAO: estado final nunca pode ser enviado+deleted_at juntos ###############" >&2
tbl_get "estado final do orcamento" "$TOK_ENC" "orcamentos?id=eq.$ORC&select=status,deleted_at,deleted_by"
echo "$BODY"
echo
echo "Critério de aceite ORC-CONC-001: exatamente UM dos dois arquivos acima deve conter"
echo "HTTP 200 (sucesso) e o outro deve conter HTTP 4xx/erro P0001; a consulta final deve"
echo "mostrar OU status=rascunho+deleted_at preenchido (exclusão venceu) OU status=enviado"
echo "+deleted_at nulo (envio venceu) — nunca as duas condições simultaneamente."
