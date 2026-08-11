#!/usr/bin/env bash
# ETAPA 6 — cenários reais de estoque contra o projeto dev/teste autorizado.
set -uo pipefail

URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() {
  curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"
}
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")

rpc() {
  local label="$1" token="$2" fn="$3" body="$4"
  echo; echo "--- $label ---"
  curl -s -o /tmp/_r6.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$body"
  cat /tmp/_r6.json
}
saldo() {
  local label="$1" peca="$2"
  echo; echo "--- saldo atual: $label ---"
  curl -s "$URL/rest/v1/pecas?id=eq.$peca&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN"
  echo
}
movimentos() {
  local label="$1" peca="$2"
  echo; echo "--- estoque_movimentos: $label ---"
  curl -s "$URL/rest/v1/estoque_movimentos?peca_id=eq.$peca&select=tipo,origem_tipo,origem_id,quantidade,criado_por,criado_em,estornado_de&order=criado_em.desc&limit=5" \
    -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN"
  echo
}

echo "=== 1) saldo=10 (peça d...0005) -> baixar 2 -> confirmar saldo=8 ==="
saldo "antes" "d0000000-0000-0000-0000-000000000005"
rpc "EXECUTOR baixa 2 unidades de d...0005 na OS f...0009 (em_execucao)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  '{"p_os_id":"f0000000-0000-0000-0000-000000000009","p_peca_id":"d0000000-0000-0000-0000-000000000005","p_quantidade":2}'
saldo "depois (esperado: 8)" "d0000000-0000-0000-0000-000000000005"
movimentos "após baixa (origem/usuário/data devem estar presentes)" "d0000000-0000-0000-0000-000000000005"

echo
echo "=== 2) saldo=8 -> tentar baixar 20 (> saldo) -> BLOQUEADO, saldo não muda ==="
rpc "EXECUTOR tenta baixar 20 (EST-007 — esperado: bloqueado)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  '{"p_os_id":"f0000000-0000-0000-0000-000000000009","p_peca_id":"d0000000-0000-0000-0000-000000000005","p_quantidade":20}'
saldo "depois da tentativa bloqueada (esperado: continua 8)" "d0000000-0000-0000-0000-000000000005"

echo
echo "=== 3) Baixa duplicada / retry — repetir a MESMA baixa (2 unidades) imediatamente ==="
rpc "EXECUTOR repete a baixa de 2 unidades (EST-009/P0-04 — esperado: bloqueado por dedup de 5s)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  '{"p_os_id":"f0000000-0000-0000-0000-000000000009","p_peca_id":"d0000000-0000-0000-0000-000000000005","p_quantidade":2}'
saldo "depois (esperado: continua 8, não duplicou)" "d0000000-0000-0000-0000-000000000005"

echo
echo "=== 4) Estorno da baixa do passo 1 (EST-010/P0-05 — RPC nova rpc_estornar_saida_estoque) ==="
MOV_ID=$(curl -s "$URL/rest/v1/estoque_movimentos?peca_id=eq.d0000000-0000-0000-0000-000000000005&tipo=eq.saida&order=criado_em.desc&limit=1&select=id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "movimento a estornar: $MOV_ID"
rpc "SUPORTE estorna o movimento de saída" "$TOK_SUPORTE" rpc_estornar_saida_estoque "{\"p_movimento_id\":\"$MOV_ID\"}"
saldo "depois do estorno (esperado: volta a 10)" "d0000000-0000-0000-0000-000000000005"
movimentos "após estorno (deve aparecer estorno_saida com estornado_de preenchido)" "d0000000-0000-0000-0000-000000000005"
rpc "SUPORTE tenta estornar o MESMO movimento de novo (esperado: bloqueado, já estornado)" "$TOK_SUPORTE" rpc_estornar_saida_estoque "{\"p_movimento_id\":\"$MOV_ID\"}"

echo
echo "=== 5) Cancelamento de OS com estoque já baixado (OS-010/P0-05) — OS f...0008, peça d...0004 ==="
saldo "peça d...0004 ANTES de cancelar f...0008 (esperado: 8, já tinha 2 baixadas no seed)" "d0000000-0000-0000-0000-000000000004"
rpc "ADMIN cancela a OS f...0008 (em_diagnostico -> cancelada)" "$TOK_ADMIN" rpc_transicionar_os \
  '{"p_os_id":"f0000000-0000-0000-0000-000000000008","p_novo_status":"cancelada"}'
saldo "peça d...0004 DEPOIS de cancelar (esperado: volta a 10 — estorno automático)" "d0000000-0000-0000-0000-000000000004"
movimentos "após cancelamento (deve ter estorno_saida automático)" "d0000000-0000-0000-0000-000000000004"

echo
echo "=== 6) Venda avulsa real (EST-006) ==="
rpc "SUPORTE registra venda avulsa de 3un de d...0001 p/ cliente b...0001" "$TOK_SUPORTE" rpc_criar_venda_avulsa \
  '{"p_cliente_id":"b0000000-0000-0000-0000-000000000001","p_itens":[{"peca_id":"d0000000-0000-0000-0000-000000000001","quantidade":3,"valor_unitario":45.00}]}'

echo
echo "=== 7) Concorrência (EST-013/EST-016) — duas baixas simultâneas com quantidades DIFERENTES (5 e 6, soma 11 > saldo 8) em d...0005 ==="
echo "    Quantidades diferentes de propósito, p/ isolar o mecanismo de concorrência (FOR UPDATE)"
echo "    do guard de dedup do P0-04 (que só bloqueia baixa IDÊNTICA)."
saldo "d...0005 antes da concorrência (esperado: 8)" "d0000000-0000-0000-0000-000000000005"
(
curl -s -o /tmp/_conc1.json -w "conc1 (qtd 5) HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXECUTOR" -H "Content-Type: application/json" \
  -d '{"p_os_id":"f0000000-0000-0000-0000-000000000009","p_peca_id":"d0000000-0000-0000-0000-000000000005","p_quantidade":5}'
) &
(
curl -s -o /tmp/_conc2.json -w "conc2 (qtd 6) HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE" -H "Content-Type: application/json" \
  -d '{"p_os_id":"f0000000-0000-0000-0000-000000000009","p_peca_id":"d0000000-0000-0000-0000-000000000005","p_quantidade":6}'
) &
wait
echo "resultado conc1 (qtd 5):"; cat /tmp/_conc1.json; echo
echo "resultado conc2 (qtd 6):"; cat /tmp/_conc2.json; echo
saldo "d...0005 depois da concorrência (esperado: 3 [se a de 5 passou] ou 2 [se a de 6 passou] — nunca negativo, só UMA passa)" "d0000000-0000-0000-0000-000000000005"

echo
echo "=== FIM ETAPA 6 ==="
