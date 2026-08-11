#!/usr/bin/env bash
# ETAPA 5 (P1-B) — complementa etapa5_e2e_apr002_adc.sh com os cenarios que
# ele nao cobre em sequencia unica: (C) 100% rejeitado bloqueia conversao em
# OS, e (N) concorrencia REAL (duas chamadas HTTP em paralelo de verdade,
# nao sequenciais) disputando a MESMA decisao de item.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
ENC_ID="a0000000-0000-0000-0000-000000000002"

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
rawid() { echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '\"'; }

CLIENTE_ID=$(curl -s "$URL/rest/v1/clientes?tipo=eq.externo&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'])")
VEICULO_ID=$(curl -s "$URL/rest/v1/veiculos?cliente_id=eq.$CLIENTE_ID&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'])")
echo "CLIENTE_ID=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"

echo
echo "############################################"
echo "# CENARIO C: 100% REJEITADO -- orcamento fica 'rejeitado', conversao em OS bloqueada"
echo "############################################"
tbl_post "cria orcamento rascunho" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC_C=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item unico R\$500" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC_C\",\"descricao\":\"TESTE cenario C item unico\",\"quantidade\":1,\"valor_unitario\":500}"
ITEM_C=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_C\"}"
rpc "decide item REJEITADO (unico item)" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_C\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel\"}"
tbl_get "status do orcamento (esperado: rejeitado)" "$TOK_ENC" "orcamentos?id=eq.$ORC_C&select=status"
rpc "tenta converter orcamento 100% rejeitado em OS -- deve BLOQUEAR" "$TOK_ENC" rpc_criar_os \
  "{\"p_veiculo_id\":\"$VEICULO_ID\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_C\"}"

echo
echo "############################################"
echo "# CENARIO N (concorrencia REAL): duas requisicoes HTTP EM PARALELO tentando decidir o MESMO item com decisoes DIFERENTES"
echo "############################################"
tbl_post "cria orcamento rascunho p/ teste de concorrencia" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC_N=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item unico R\$800 (alvo da corrida)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC_N\",\"descricao\":\"TESTE cenario N corrida\",\"quantidade\":1,\"valor_unitario\":800}"
ITEM_N=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_N\"}"

echo "--- disparando 2 chamadas REAIS em paralelo: ENCARREGADO aprova / SUPORTE rejeita, o MESMO item, ao mesmo tempo ---"
(curl -s -o /tmp/p1b_race_aprova.json -w '%{http_code}' -X POST "$URL/rest/v1/rpc/rpc_decidir_item_orcamento" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: application/json" \
  -d "{\"p_orcamento_item_id\":\"$ITEM_N\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Race\"}" > /tmp/p1b_race_aprova.code) &
PID1=$!
(curl -s -o /tmp/p1b_race_rejeita.json -w '%{http_code}' -X POST "$URL/rest/v1/rpc/rpc_decidir_item_orcamento" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: application/json" \
  -d "{\"p_orcamento_item_id\":\"$ITEM_N\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Race\"}" > /tmp/p1b_race_rejeita.code) &
PID2=$!
wait $PID1 $PID2

echo "--- resultado da chamada 'aprova' (ENCARREGADO) ---"
echo "HTTP $(cat /tmp/p1b_race_aprova.code)"; cat /tmp/p1b_race_aprova.json; echo
echo "--- resultado da chamada 'rejeita' (SUPORTE) ---"
echo "HTTP $(cat /tmp/p1b_race_rejeita.code)"; cat /tmp/p1b_race_rejeita.json; echo
tbl_get "estado FINAL do item apos a corrida (esperado: exatamente UMA das duas decisoes venceu, nunca as duas)" "$TOK_ENC" "orcamento_itens?id=eq.$ITEM_N&select=status_aprovacao,meio_aprovacao,registrado_por"
tbl_get "auditoria do item (esperado: 1 UNICO evento decisao_item_orcamento, nao 2)" "$TOK_ENC" "auditoria_eventos?entidade=eq.orcamento_itens&entidade_id=eq.$ITEM_N&acao=eq.decisao_item_orcamento&select=acao,valor_novo,usuario_id"

echo
echo "############################################"
echo "# Fixtures p/ cenarios H/J: OS interna simples (sem orcamento) so p/ hospedar adicionais 100%"
echo "############################################"
rpc "cria OS interna p/ hospedar os adicionais H/J" "$TOK_ENC" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS_HJ=$(rawid)
echo "OS_HJ=$OS_HJ"
rpc "transiciona" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_HJ\",\"p_novo_status\":\"em_diagnostico\"}"

echo
echo "############################################"
echo "# CENARIO H: adicional 100% APROVADO (todos os itens aprovados)"
echo "############################################"
rpc "cria adicional AD-H (2 itens, mao de obra)" "$TOK_ENC" rpc_criar_os_adicional "{\"p_os_id\":\"$OS_HJ\",\"p_motivo\":\"TESTE cenario H - adicional 100 por cento aprovado\"}"
ADIC_H=$(rawid)
rpc "inclui item H1" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_H\",\"p_peca_id\":null,\"p_descricao\":\"TESTE item H1\",\"p_quantidade\":1,\"p_valor_unitario\":100}"
ITEM_H1=$(rawid)
rpc "inclui item H2" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_H\",\"p_peca_id\":null,\"p_descricao\":\"TESTE item H2\",\"p_quantidade\":1,\"p_valor_unitario\":50}"
ITEM_H2=$(rawid)
rpc "decide H1 aprovado" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_H1\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Cliente H\"}"
rpc "decide H2 aprovado" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_H2\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Cliente H\"}"
tbl_get "status do adicional AD-H (esperado: aprovado, 100%)" "$TOK_ENC" "os_adicionais?id=eq.$ADIC_H&select=status"

echo
echo "############################################"
echo "# CENARIO J: adicional 100% REJEITADO (todos os itens rejeitados)"
echo "############################################"
rpc "cria adicional AD-J (2 itens, mao de obra)" "$TOK_ENC" rpc_criar_os_adicional "{\"p_os_id\":\"$OS_HJ\",\"p_motivo\":\"TESTE cenario J - adicional 100 por cento rejeitado\"}"
ADIC_J=$(rawid)
rpc "inclui item J1" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_J\",\"p_peca_id\":null,\"p_descricao\":\"TESTE item J1\",\"p_quantidade\":1,\"p_valor_unitario\":80}"
ITEM_J1=$(rawid)
rpc "inclui item J2" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_J\",\"p_peca_id\":null,\"p_descricao\":\"TESTE item J2\",\"p_quantidade\":1,\"p_valor_unitario\":40}"
ITEM_J2=$(rawid)
rpc "decide J1 rejeitado" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_J1\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"verbal_documentado\",\"p_autorizado_por_nome\":\"TESTE Cliente J\",\"p_observacao\":\"Cliente recusou ambos os itens por telefone, confirmado.\"}"
rpc "decide J2 rejeitado" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_J2\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"verbal_documentado\",\"p_autorizado_por_nome\":\"TESTE Cliente J\",\"p_observacao\":\"Cliente recusou ambos os itens por telefone, confirmado.\"}"
tbl_get "status do adicional AD-J (esperado: rejeitado, 100%)" "$TOK_ENC" "os_adicionais?id=eq.$ADIC_J&select=status"

echo
echo "=== FIM CENARIOS EXTRAS (C + N real + H + J) ==="
