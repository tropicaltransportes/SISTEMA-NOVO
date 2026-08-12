#!/usr/bin/env bash
# ETAPA 7 (RC1) — item 2 e 3: dispara as chamadas REALMENTE simultâneas
# (processos curl em background, mesmo instante, sem sequencial) para
# EST-016 (cenário A: excede saldo; cenário B: ambas cabem) e GAR-008.
# Requer variáveis exportadas por etapa7_concorrencia_setup.sh (source
# /tmp/rc1_setup_env.sh antes de rodar este script).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
OUT=/tmp/rc1_concorrencia

rm -f "$OUT"_*.txt

echo "=== CENARIO A (EST-016): saldo=10, baixa OS=7 (item_A) + venda avulsa=6 SIMULTANEAS -- devem exceder ==="
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXE" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_A\",\"p_quantidade\":7,\"p_os_adicional_item_id\":\"$ITEM_A\"}" \
  > "$OUT"_A_os.txt 2>&1) &
PID1=$!
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_venda_avulsa" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: application/json" \
  -d "{\"p_cliente_id\":\"$CLIENTE\",\"p_itens\":[{\"peca_id\":\"$PECA_A\",\"quantidade\":6,\"valor_unitario\":10.00}]}" \
  > "$OUT"_A_venda.txt 2>&1) &
PID2=$!
wait $PID1 $PID2
echo "--- resultado baixa OS (7un) ---"; cat "$OUT"_A_os.txt
echo "--- resultado venda avulsa (6un) ---"; cat "$OUT"_A_venda.txt

echo
echo "=== CENARIO B (EST-016): saldo=10, baixa OS=4 (item_B) + venda avulsa=5 SIMULTANEAS -- ambas devem caber ==="
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXE" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_B\",\"p_quantidade\":4,\"p_os_adicional_item_id\":\"$ITEM_B\"}" \
  > "$OUT"_B_os.txt 2>&1) &
PID3=$!
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_venda_avulsa" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: application/json" \
  -d "{\"p_cliente_id\":\"$CLIENTE\",\"p_itens\":[{\"peca_id\":\"$PECA_B\",\"quantidade\":5,\"valor_unitario\":10.00}]}" \
  > "$OUT"_B_venda.txt 2>&1) &
PID4=$!
wait $PID3 $PID4
echo "--- resultado baixa OS (4un) ---"; cat "$OUT"_B_os.txt
echo "--- resultado venda avulsa (5un) ---"; cat "$OUT"_B_venda.txt

echo
echo "=== GAR-008: 2 chamadas SIMULTANEAS de rpc_criar_os_garantia para o MESMO item da MESMA OS liberada ==="
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_os_garantia" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" \
  -d "{\"p_os_origem_id\":\"$OS_GAR\",\"p_itens_originais\":[\"$ITEM_GAR\"]}" \
  > "$OUT"_gar1.txt 2>&1) &
PID5=$!
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_os_garantia" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" \
  -d "{\"p_os_origem_id\":\"$OS_GAR\",\"p_itens_originais\":[\"$ITEM_GAR\"]}" \
  > "$OUT"_gar2.txt 2>&1) &
PID6=$!
wait $PID5 $PID6
echo "--- resultado chamada 1 ---"; cat "$OUT"_gar1.txt
echo "--- resultado chamada 2 ---"; cat "$OUT"_gar2.txt
