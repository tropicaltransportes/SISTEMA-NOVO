#!/usr/bin/env bash
# ETAPA 3 — lote 2 dos BLOQUEADO: OS-003/008/009/011, EST-001/003/012/014,
# EXE-008, CON-004/008, NFR-005 (referência cruzada inválida, testado junto
# com OS por reaproveitar rpc_criar_os).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  local resp
  if [ -n "$body" ]; then resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  else resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token"); fi
  HTTP_CODE=$(echo "$resp" | tail -n1); BODY=$(echo "$resp" | sed '$d')
  echo "HTTP $HTTP_CODE"; echo "$BODY"
}
call_patch() {
  local label="$1" token="$2" url="$3" body="$4"
  echo; echo "--- $label ---"
  local resp=$(curl -s -w '\n%{http_code}' -X PATCH "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  HTTP_CODE=$(echo "$resp" | tail -n1); BODY=$(echo "$resp" | sed '$d')
  echo "HTTP $HTTP_CODE"; echo "$BODY"
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
echo "# OS-003 — converter SEM aprovação (orçamento rascunho e enviado)"
echo "############################################"
rpc "tenta converter e...0001 (rascunho)" "$TOK_ENCARREGADO" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000001","p_tipo":"externa","p_orcamento_id":"e0000000-0000-0000-0000-000000000001"}'

echo
echo "############################################"
echo "# NFR-005 — referência cruzada inválida (OS interna com veículo de cliente externo)"
echo "############################################"
rpc "ADMIN tenta criar OS INTERNA usando veículo de cliente EXTERNO (c...0001)" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000001","p_tipo":"interna"}'

echo
echo "############################################"
echo "# Setup: nova OS interna exclusiva p/ OS-008/009/011/CON-004/CON-008/EXE-008/NFR-001/002"
echo "############################################"
rpc "ADMIN cria OS interna exclusiva" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna","p_checklist_template_id":"20000000-0000-0000-0000-000000000001"}'
OS_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_ID=$OS_ID"

echo
echo "############################################"
echo "# OS-008 — pular estado obrigatório (forçar direto p/ concluida via rpc_transicionar_os)"
echo "############################################"
rpc "ADMIN tenta transicionar aberta -> concluida diretamente (esperado: bloqueado, use RPC específica)" "$TOK_ADMIN" rpc_transicionar_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"concluida\"}"

echo
echo "############################################"
echo "# OS-011 — duplo início (aberta->em_diagnostico duas vezes)"
echo "############################################"
rpc "1ª chamada: aberta -> em_diagnostico (esperado: sucesso)" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "2ª chamada IMEDIATA: mesma transição de novo (esperado: bloqueado, já não está mais em 'aberta')" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_diagnostico\"}"
tbl_get "confirma status final (esperado: em_diagnostico, sem duplicar evento)" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=id,status"

rpc "avança em_diagnostico -> em_execucao (necessário p/ próximos testes)" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# EXE-008 — executor tenta alterar preço de item de orçamento (usa item do e...0006, aprovado)"
echo "############################################"
call_patch "EXECUTOR tenta alterar valor_unitario de item de orçamento (mesmo em rascunho, executor não tem perfil autorizado)" "$TOK_EXECUTOR" \
  "$URL/rest/v1/orcamento_itens?id=eq.1c177050-7f07-4376-bd5d-5c3e473fe2c9" '{"valor_unitario":1.00}'
tbl_get "confirma preço inalterado" "$TOK_ADMIN" "orcamento_itens?id=eq.1c177050-7f07-4376-bd5d-5c3e473fe2c9&select=id,valor_unitario"

echo
echo "############################################"
echo "# CON-004 — concluir com checklist incompleto (OS_ID já em em_execucao, checklist NUNCA respondido)"
echo "############################################"
rpc "ADMIN transiciona em_execucao -> aguardando_teste" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"aguardando_teste\"}"
rpc "ADMIN tenta CONCLUIR sem responder o item obrigatório do checklist (esperado: bloqueado)" "$TOK_ADMIN" rpc_concluir_os "{\"p_os_id\":\"$OS_ID\"}"
tbl_get "confirma status ainda aguardando_teste" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=id,status"

echo "-- agora completa o checklist de verdade, para poder testar CON-008 e OS-009 em seguida --"
tbl_post "EXECUTOR responde item obrigatório do checklist" "$TOK_EXECUTOR" "os_checklist_respostas" \
  "{\"os_id\":\"$OS_ID\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
rpc "ADMIN conclui a OS agora (esperado: sucesso)" "$TOK_ADMIN" rpc_concluir_os "{\"p_os_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# CON-008 — conclusão repetida (chamar rpc_concluir_os de novo na MESMA OS já concluída)"
echo "############################################"
rpc "ADMIN tenta concluir de novo (esperado: bloqueado, status já não é aguardando_teste)" "$TOK_ADMIN" rpc_concluir_os "{\"p_os_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# OS-009 — reabrir OS encerrada (concluida -> em_execucao, e depois liberada -> em_execucao)"
echo "############################################"
rpc "ADMIN tenta reabrir (concluida -> em_execucao) via rpc_transicionar_os (esperado: bloqueado)" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_execucao\"}"
echo "-- também tenta a partir de uma OS já LIBERADA (f...0006, liberada há 10 dias) --"
rpc "ADMIN tenta reabrir a OS f...0006 (liberada) direto para em_execucao (esperado: bloqueado)" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"f0000000-0000-0000-0000-000000000006\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# EST-001 — entrada por compra (fluxo completo NF, 10 unidades)"
echo "############################################"
tbl_post "SUPORTE cria peça exclusiva p/ EST-001" "$TOK_SUPORTE" "pecas" \
  '{"sku":"QA_PECA_EST001_E03","descricao":"TESTE_E03_Peca_EST001","unidade":"UN","saldo_atual":0,"custo_medio":0,"estoque_minimo":1}'
PECA_EST001=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "PECA_EST001=$PECA_EST001"
tbl_post "SUPORTE cria NF rascunho" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-EST001","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF_EST001=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE adiciona item (10un x R\$25)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF_EST001\",\"peca_id\":\"$PECA_EST001\",\"quantidade\":10,\"valor_unitario\":25.00}"
tbl_get "saldo ANTES de confirmar" "$TOK_ADMIN" "pecas?id=eq.$PECA_EST001&select=saldo_atual"
rpc "SUPORTE confirma a NF (registra entrada de 10un)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF_EST001\"}"
tbl_get "saldo DEPOIS (esperado: 10)" "$TOK_ADMIN" "pecas?id=eq.$PECA_EST001&select=saldo_atual,custo_medio"
tbl_get "movimento registrado (esperado: tipo=entrada, origem_tipo=nf_entrada)" "$TOK_ADMIN" "estoque_movimentos?peca_id=eq.$PECA_EST001&select=tipo,origem_tipo,origem_id,quantidade,custo_unitario"

echo
echo "############################################"
echo "# EST-003 — entrada com custo inválido (negativo)"
echo "############################################"
tbl_post "SUPORTE cria 2ª NF rascunho" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-EST003","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF_EST003=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE tenta adicionar item com custo NEGATIVO (esperado: bloqueado por CHECK constraint)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF_EST003\",\"peca_id\":\"$PECA_EST001\",\"quantidade\":5,\"valor_unitario\":-10.00}"

echo
echo "############################################"
echo "# EST-012 — alterar custo histórico (2ª entrada muda custo médio; movimento antigo deve preservar valor original)"
echo "############################################"
tbl_get "custo_unitario do movimento de entrada ORIGINAL (10un x R\$25)" "$TOK_ADMIN" "estoque_movimentos?peca_id=eq.$PECA_EST001&tipo=eq.entrada&select=id,custo_unitario&order=criado_em.asc&limit=1"
tbl_post "SUPORTE cria 3ª NF (2ª entrada real, custo diferente: 10un x R\$45 -> muda custo médio ponderado)" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-EST012","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF_EST012=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE adiciona item (10un x R\$45)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF_EST012\",\"peca_id\":\"$PECA_EST001\",\"quantidade\":10,\"valor_unitario\":45.00}"
rpc "SUPORTE confirma (custo_medio da peça deve subir para (10*25+10*45)/20=35)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF_EST012\"}"
tbl_get "peça DEPOIS (custo_medio esperado: 35.00, saldo 20)" "$TOK_ADMIN" "pecas?id=eq.$PECA_EST001&select=saldo_atual,custo_medio"
tbl_get "movimento ORIGINAL (1ª entrada) DEPOIS — custo_unitario deve CONTINUAR 25.00 (ledger imutável)" "$TOK_ADMIN" "estoque_movimentos?peca_id=eq.$PECA_EST001&tipo=eq.entrada&select=id,custo_unitario,quantidade&order=criado_em.asc"

echo
echo "############################################"
echo "# EST-014 — reconciliação de saldo (entradas - saídas + estornos = saldo_atual)"
echo "############################################"
tbl_get "todos os movimentos da peça EST001" "$TOK_ADMIN" "estoque_movimentos?peca_id=eq.$PECA_EST001&select=tipo,quantidade&order=criado_em.asc"
tbl_get "saldo_atual oficial da peça" "$TOK_ADMIN" "pecas?id=eq.$PECA_EST001&select=saldo_atual"
echo "(cálculo de reconciliação feito no relatório final a partir dos dados acima)"

echo
echo "PECA_EST001=$PECA_EST001"
echo "OS_ID (OS-008/009/011/CON-004/CON-008/EXE-008)=$OS_ID"
echo "=== FIM LOTE 2 ==="
