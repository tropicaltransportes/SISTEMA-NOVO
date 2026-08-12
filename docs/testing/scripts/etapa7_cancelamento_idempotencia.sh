#!/usr/bin/env bash
# ETAPA 7 (RC1) — itens 14 (cancelamento e estorno) e 15 (idempotencia,
# incluindo reexecucao apos >5s e chamadas concorrentes de verdade).
# Dados 100% novos (sufixo por timestamp), execucao real contra o Supabase
# QA autorizado.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
ENC_ID="a0000000-0000-0000-0000-000000000002"
CLIENTE="b0000000-0000-0000-0000-000000000001"
VEICULO="c0000000-0000-0000-0000-000000000001"
CHK="20000000-0000-0000-0000-000000000001"
CHKITEM="20000000-0000-0000-0000-000000000011"
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
rawid() { echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '\"'; }

echo "############################################################"
echo "# SETUP: peca dedicada RC1 (saldo 20), orcamento aprovado, OS"
echo "############################################################"
tbl_post "peca RC1_CANCEL" "$TOK_SUP" "pecas" "{\"sku\":\"QA_RC1_CANCEL_$TS\",\"descricao\":\"TESTE_RC1_Cancelamento\",\"unidade\":\"UN\",\"saldo_atual\":20,\"custo_medio\":10.00,\"estoque_minimo\":1}"
PECA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")

tbl_post "cria orcamento RC1 (insert direto)" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO\",\"cliente_id\":\"$CLIENTE\",\"versao\":1,\"status\":\"rascunho\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item do orcamento (peca, 5un)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA\",\"descricao\":\"TESTE RC1 item cancelamento\",\"quantidade\":5,\"valor_unitario\":50.00}"
ITEM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "aprova item" "$TOK_ENC" rpc_decidir_item_orcamento "{\"p_orcamento_item_id\":\"$ITEM\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"
rpc "cria OS a partir do orcamento" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC\",\"p_checklist_template_id\":\"$CHK\"}"
OS=$(rawid)
rpc "aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################################"
echo "# ITEM 15a: IDEMPOTENCIA - baixa de peca reexecutada (mesma idempotency_key) apos >5s"
echo "############################################################"
IDEMKEY=$(python -c "import uuid; print(uuid.uuid4())")
rpc "1a baixa (3un, com idempotency_key)" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":3,\"p_orcamento_item_id\":\"$ITEM\",\"p_idempotency_key\":\"$IDEMKEY\"}"
tbl_get "saldo apos 1a baixa (esperado 17)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"
echo "aguardando 6s (janela de dedup de 5s) antes de reexecutar com a MESMA idempotency_key..."
sleep 6
rpc "2a chamada, MESMA idempotency_key, apos 6s -- esperado BLOQUEADA (idempotencia, nao so dedup de 5s)" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":3,\"p_orcamento_item_id\":\"$ITEM\",\"p_idempotency_key\":\"$IDEMKEY\"}"
tbl_get "saldo apos a 2a tentativa (esperado continuar 17, sem duplicar)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"

echo
echo "############################################################"
echo "# ITEM 15b: IDEMPOTENCIA - criacao de cobranca reexecutada apos >5s (client_request_id se existir) + chamada concorrente real"
echo "############################################################"
rpc "marca item do orcamento como executado" "$TOK_ENC" rpc_marcar_item_orcamento_execucao "{\"p_orcamento_item_id\":\"$ITEM\",\"p_status\":\"executado\",\"p_motivo\":\"TESTE RC1\"}"
tbl_post "responde checklist obrigatorio" "$TOK_ENC" "os_checklist_respostas" "{\"os_id\":\"$OS\",\"template_item_id\":\"$CHKITEM\",\"ok\":true,\"respondido_por\":\"$ENC_ID\",\"respondido_em\":\"2026-08-15T12:00:00Z\"}"
rpc "em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"
rpc "conclui OS" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo "--- 2 chamadas SIMULTANEAS de rpc_criar_cobranca para a MESMA OS ---"
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_cobranca" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: application/json" -d "{\"p_cliente_id\":\"$CLIENTE\",\"p_os_ids\":[\"$OS\"],\"p_venda_ids\":null}" > /tmp/rc1_idem_cob1.txt 2>&1) &
P1=$!
(curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/rpc_criar_cobranca" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: application/json" -d "{\"p_cliente_id\":\"$CLIENTE\",\"p_os_ids\":[\"$OS\"],\"p_venda_ids\":null}" > /tmp/rc1_idem_cob2.txt 2>&1) &
P2=$!
wait $P1 $P2
echo "--- resultado chamada 1 ---"; cat /tmp/rc1_idem_cob1.txt
echo "--- resultado chamada 2 ---"; cat /tmp/rc1_idem_cob2.txt
tbl_get "quantas cobrancas existem para esta OS (esperado 1, nunca 2)" "$TOK_SUP" "cobranca_origens?os_id=eq.$OS&select=cobranca_id"

echo
echo "############################################################"
echo "# ITEM 14: CANCELAMENTO E ESTORNO -- OS DEDICADA nova (fica em em_diagnostico,"
echo "# unico estado que permite baixa E cancelamento juntos -- rpc_transicionar_os"
echo "# so aceita 'cancelada' a partir de aberta/em_diagnostico/aguardando_aprovacao,"
echo "# NAO de em_execucao -- achado real desta rodada, ver codigo de rpc_transicionar_os)"
echo "############################################################"
tbl_post "cria 2o orcamento RC1 (dedicado ao cancelamento)" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO\",\"cliente_id\":\"$CLIENTE\",\"versao\":1,\"status\":\"rascunho\",\"criado_por\":\"$ENC_ID\"}"
ORC2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item do 2o orcamento (peca, 5un)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC2\",\"peca_id\":\"$PECA\",\"descricao\":\"TESTE RC1 item cancelamento 2\",\"quantidade\":5,\"valor_unitario\":50.00}"
ITEM2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia 2o orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC2\"}"
rpc "aprova item do 2o orcamento" "$TOK_ENC" rpc_decidir_item_orcamento "{\"p_orcamento_item_id\":\"$ITEM2\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"
rpc "cria OS2 (dedicada ao cancelamento)" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC2\",\"p_checklist_template_id\":\"$CHK\"}"
OS2=$(rawid)
rpc "OS2 aberta->em_diagnostico (fica aqui -- NAO vai para em_execucao)" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS2\",\"p_novo_status\":\"em_diagnostico\"}"

tbl_get "saldo ANTES de qualquer baixa na OS2 (esperado 17, herdado do estado anterior)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"
rpc "baixa peca do item do orcamento (3un) em em_diagnostico" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":3,\"p_orcamento_item_id\":\"$ITEM2\"}"
tbl_get "saldo apos baixa do item original (esperado 14)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"

rpc "cria adicional na OS2 (peca extra)" "$TOK_EXE" rpc_criar_os_adicional "{\"p_os_id\":\"$OS2\",\"p_motivo\":\"TESTE RC1 cancelamento -- peca extra\"}"
ADIC=$(rawid)
rpc "inclui item do adicional (peca, 2un)" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":\"$PECA\",\"p_descricao\":\"TESTE RC1 peca adicional\",\"p_quantidade\":2,\"p_valor_unitario\":10.00,\"p_justificativa\":\"TESTE\"}"
ITEM_AD=$(rawid)
rpc "aprova item do adicional" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_AD\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"
rpc "baixa peca do adicional (2un)" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":2,\"p_os_adicional_item_id\":\"$ITEM_AD\"}"
tbl_get "saldo apos baixa do adicional (esperado 12 = 14-2)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"
tbl_get "movimentos de saida da OS2 antes do cancelamento (esperado 2 saidas, nenhum estorno ainda)" "$TOK_SUP" "estoque_movimentos?peca_id=eq.$PECA&origem_id=eq.$OS2&select=tipo,quantidade,estornado_de&order=criado_em"

echo "--- cancela a OS2 (em_diagnostico -> cancelada) ---"
rpc "ENCARREGADO cancela a OS2" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS2\",\"p_novo_status\":\"cancelada\"}"
tbl_get "status final da OS2 (esperado cancelada)" "$TOK_ENC" "ordens_servico?id=eq.$OS2&select=status"
tbl_get "saldo APOS cancelamento (esperado voltar a 17 -- as 2 saidas estornadas)" "$TOK_SUP" "pecas?id=eq.$PECA&select=saldo_atual"
tbl_get "movimentos apos cancelamento (esperado 2 saidas ORIGINAIS preservadas + 2 estornos novos vinculados, total 4 linhas)" "$TOK_SUP" "estoque_movimentos?peca_id=eq.$PECA&order=criado_em&select=tipo,quantidade,estornado_de,origem_id"
tbl_get "cobranca indevida para a OS2 cancelada (esperado vazio -- OS2 nunca chegou a concluida/cobranca)" "$TOK_SUP" "cobranca_origens?os_id=eq.$OS2&select=id"

echo "--- tenta baixar mais peca na OS ja cancelada -- esperado bloqueada (status nao permite mais baixa) ---"
rpc "tenta baixar peca na OS2 cancelada" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM2\"}"

echo
echo "############################################################"
echo "# FIM"
echo "############################################################"
