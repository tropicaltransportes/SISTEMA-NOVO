#!/usr/bin/env bash
# ETAPA 7 (RC1) — SETUP para EST-016 e GAR-008, concorrência real.
# Cria fixtures 100% novas (não reaproveita seed mutado por rodadas
# anteriores) e imprime as variáveis de ambiente que o script de disparo
# concorrente (etapa7_concorrencia_fire.sh) precisa.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")
ENC_ID="a0000000-0000-0000-0000-000000000002"
CLIENTE="b0000000-0000-0000-0000-000000000001"
VEICULO="c0000000-0000-0000-0000-000000000001"
CLIENTE_INT="b0000000-0000-0000-0000-000000000002"
VEICULO_INT="c0000000-0000-0000-0000-000000000002"
CHK="20000000-0000-0000-0000-000000000001"
CHKITEM="20000000-0000-0000-0000-000000000011"
TS=$(date +%s)

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
rawid() { echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '\"'; }

echo "############### EST-016: 2 pecas novas dedicadas, saldo=10 cada ###############" >&2
tbl_post "peca RC1_CONC_A" "$TOK_SUP" "pecas" "{\"sku\":\"QA_RC1_CONC_A_$TS\",\"descricao\":\"TESTE_RC1_Concorrencia_A\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":10.00,\"estoque_minimo\":1}"
PECA_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "peca RC1_CONC_B" "$TOK_SUP" "pecas" "{\"sku\":\"QA_RC1_CONC_B_$TS\",\"descricao\":\"TESTE_RC1_Concorrencia_B\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":10.00,\"estoque_minimo\":1}"
PECA_B=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "NF rascunho RC1" "$TOK_SUP" "notas_fiscais_entrada" "{\"numero\":\"NF-RC1-CONC-$TS\",\"fornecedor\":\"TESTE_Fornecedor_RC1\",\"status\":\"rascunho\",\"data_emissao\":\"2026-08-15\",\"criado_por\":\"a0000000-0000-0000-0000-000000000003\"}"
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item NF peca A (10un)" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_A\",\"quantidade\":10,\"valor_unitario\":10.00}"
tbl_post "item NF peca B (10un)" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_B\",\"quantidade\":10,\"valor_unitario\":10.00}"
rpc "confirma NF (credita saldo=10 nas duas pecas)" "$TOK_SUP" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

echo "############### OS interna dedicada (em_execucao) para os 2 cenarios ###############" >&2
rpc "cria OS interna RC1" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO_INT\",\"p_tipo\":\"interna\",\"p_checklist_template_id\":\"$CHK\"}"
OS=$(rawid)
rpc "aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo "############### Cenario A: adicional aprovado, peca A, quantidade=7 (baixa OS) ###############" >&2
rpc "cria adicional A" "$TOK_EXE" rpc_criar_os_adicional "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE RC1 concorrencia cenario A\"}"
ADIC_A=$(rawid)
rpc "inclui item adicional A (peca A, 7un)" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_A\",\"p_peca_id\":\"$PECA_A\",\"p_descricao\":\"TESTE RC1 item A\",\"p_quantidade\":7,\"p_valor_unitario\":10.00,\"p_justificativa\":\"TESTE RC1 concorrencia\"}"
ITEM_A=$(rawid)
rpc "decide (aprova) item A" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_A\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"

echo "############### Cenario B: adicional aprovado, peca B, quantidade=4 (baixa OS) ###############" >&2
rpc "cria adicional B" "$TOK_EXE" rpc_criar_os_adicional "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE RC1 concorrencia cenario B\"}"
ADIC_B=$(rawid)
rpc "inclui item adicional B (peca B, 4un)" "$TOK_ENC" rpc_incluir_item_os_adicional "{\"p_adicional_id\":\"$ADIC_B\",\"p_peca_id\":\"$PECA_B\",\"p_descricao\":\"TESTE RC1 item B\",\"p_quantidade\":4,\"p_valor_unitario\":10.00,\"p_justificativa\":\"TESTE RC1 concorrencia\"}"
ITEM_B=$(rawid)
rpc "decide (aprova) item B" "$TOK_ENC" rpc_decidir_item_os_adicional "{\"p_item_id\":\"$ITEM_B\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"

echo "############### GAR-008: OS externa nova, ate liberada, item aprovado, pronta para garantia ###############" >&2
tbl_post "cria orcamento (rascunho, insert direto -- nao existe rpc_criar_orcamento)" "$TOK_ENC" "orcamentos" \
  "{\"veiculo_id\":\"$VEICULO\",\"cliente_id\":\"$CLIENTE\",\"versao\":1,\"status\":\"rascunho\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "inclui item no orcamento (insert direto)" "$TOK_ENC" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE RC1 servico garantia\",\"quantidade\":1,\"valor_unitario\":300.00}"
ITEM_GAR=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "decide (aprova) item do orcamento" "$TOK_ENC" rpc_decidir_item_orcamento "{\"p_orcamento_item_id\":\"$ITEM_GAR\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE RC1\"}"
rpc "cria OS a partir do orcamento" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC\",\"p_checklist_template_id\":\"$CHK\"}"
OS_GAR=$(rawid)
rpc "aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GAR\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GAR\",\"p_novo_status\":\"em_execucao\"}"
tbl_post "responde item obrigatorio do checklist" "$TOK_ENC" "os_checklist_respostas" "{\"os_id\":\"$OS_GAR\",\"template_item_id\":\"$CHKITEM\",\"ok\":true,\"respondido_por\":\"$ENC_ID\",\"respondido_em\":\"2026-08-15T12:00:00Z\"}"
rpc "marca item do orcamento como executado (servico, sem peca)" "$TOK_ENC" rpc_marcar_item_orcamento_execucao "{\"p_orcamento_item_id\":\"$ITEM_GAR\",\"p_status\":\"executado\",\"p_motivo\":\"TESTE RC1\"}"
rpc "em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GAR\",\"p_novo_status\":\"aguardando_teste\"}"
rpc "conclui OS" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS_GAR\"}"
rpc "cria cobranca" "$TOK_SUP" rpc_criar_cobranca "{\"p_cliente_id\":\"$CLIENTE\",\"p_os_ids\":[\"$OS_GAR\"],\"p_venda_ids\":null}"
COBR=$(rawid)
rpc "parcela em 1x" "$TOK_SUP" rpc_parcelar_cobranca "{\"p_cobranca_id\":\"$COBR\",\"p_parcelas\":[{\"numero_parcela\":1,\"valor\":300.00,\"vencimento\":\"2026-09-15\"}]}"
tbl_get "busca parcela criada" "$TOK_SUP" "parcelas?cobranca_id=eq.$COBR&select=id"
PARCELA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "registra recebimento total (quita)" "$TOK_SUP" rpc_registrar_recebimento "{\"p_parcela_id\":\"$PARCELA\",\"p_valor_recebido\":300.00,\"p_forma_pagamento\":\"pix\",\"p_data_recebimento\":\"2026-08-15\"}"
rpc "libera OS" "$TOK_ENC" rpc_liberar_os "{\"p_os_id\":\"$OS_GAR\"}"

echo "############### RESUMO (exporta para o script de disparo) ###############" >&2
cat <<EOF
export TOK_ENC="$TOK_ENC"
export TOK_SUP="$TOK_SUP"
export TOK_EXE="$TOK_EXE"
export TOK_ADM="$TOK_ADM"
export OS="$OS"
export PECA_A="$PECA_A"
export PECA_B="$PECA_B"
export ITEM_A="$ITEM_A"
export ITEM_B="$ITEM_B"
export CLIENTE="$CLIENTE"
export OS_GAR="$OS_GAR"
export ITEM_GAR="$ITEM_GAR"
EOF
