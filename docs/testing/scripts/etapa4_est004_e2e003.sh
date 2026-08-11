#!/usr/bin/env bash
# ETAPA 4 (P1-A) — item D: EST-004/E2E-003, baixa vinculada ao item aprovado
# do orçamento em OS originada de orçamento.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
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
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# SETUP: peça, cliente/veiculo externo, orcamento com 2 itens (1 peca qtd 3, 1 mao de obra), aprovado -> OS"
echo "############################################"
tbl_post "SUPORTE cria peca exclusiva P1A_EST004" "$TOK_SUP" "pecas" \
  '{"sku":"QA_PECA_P1A_EST004","descricao":"TESTE_P1A_Peca_EST004","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE cria peca com saldo BAIXO P1A_EST004B" "$TOK_SUP" "pecas" \
  '{"sku":"QA_PECA_P1A_EST004B_BAIXO","descricao":"TESTE_P1A_Peca_EST004_Saldo_Baixo","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA_BAIXA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE cria NF rascunho" "$TOK_SUP" "notas_fiscais_entrada" \
  '{"numero":"NF-P1A-EST004","fornecedor":"TESTE_Fornecedor_P1A","status":"rascunho","data_emissao":"2026-08-12","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item NF: 10un peca principal" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA\",\"quantidade\":10,\"valor_unitario\":10.00}"
tbl_post "item NF: 1un peca saldo baixo" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_BAIXA\",\"quantidade\":1,\"valor_unitario\":10.00}"
rpc "confirma NF" "$TOK_SUP" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

CLIENTE_ID=$(curl -s "$URL/rest/v1/clientes?tipo=eq.externo&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'])")
VEICULO_ID=$(curl -s "$URL/rest/v1/veiculos?cliente_id=eq.$CLIENTE_ID&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'])")
echo "CLIENTE_ID=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"

tbl_post "cria orcamento rascunho" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item peca (qtd 3, aprovado)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA\",\"descricao\":\"TESTE peca principal\",\"quantidade\":3,\"valor_unitario\":50}"
ITEM_PECA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item mao de obra (sem peca)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE mao de obra\",\"quantidade\":1,\"valor_unitario\":200}"
ITEM_MDO=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item peca SALDO BAIXO (qtd 5, aprovado -- mais do que o estoque tem)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA_BAIXA\",\"descricao\":\"TESTE peca saldo insuficiente\",\"quantidade\":5,\"valor_unitario\":30}"
ITEM_BAIXA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC=$ORC ITEM_PECA=$ITEM_PECA ITEM_MDO=$ITEM_MDO ITEM_BAIXA=$ITEM_BAIXA"

rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "registra autorizacao (cliente externo)" "$TOK_ENC" rpc_registrar_autorizacao_orcamento "{\"p_orcamento_id\":\"$ORC\",\"p_autorizado_por_nome\":\"TESTE Responsavel\",\"p_comprovante_path\":\"comprovantes/teste-p1a-est004.pdf\"}"
rpc "aprova orcamento" "$TOK_ENC" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "converte em OS externa" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO_ID\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC\"}"
OS=$(echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '"')
echo "OS=$OS"

echo "--- SALDO da peca principal LOGO APOS a conversao (esperado: 10, NAO baixou nada na conversao -- decisao B) ---"
curl -s "$URL/rest/v1/pecas?id=eq.$PECA&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

rpc "transiciona aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"

echo
echo "############################################"
echo "# D1: baixa SEM informar orcamento_item_id -- deve BLOQUEAR (OS tem orcamento)"
echo "############################################"
rpc "EXECUTOR tenta baixar peca principal SEM p_orcamento_item_id" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":1}"

echo
echo "############################################"
echo "# D2: baixa vinculada a item aprovado, dentro da quantidade -- deve PASSAR"
echo "############################################"
rpc "EXECUTOR baixa 2un vinculada ao ITEM_PECA (aprovado 3)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":2,\"p_orcamento_item_id\":\"$ITEM_PECA\"}"
echo "--- saldo apos baixar 2un (esperado 8) ---"
curl -s "$URL/rest/v1/pecas?id=eq.$PECA&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo
echo "--- execucao_status do ITEM_PECA (esperado: parcial, 2 de 3) ---"
curl -s "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_PECA&select=id,quantidade,execucao_status" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

echo
echo "############################################"
echo "# D3: baixa que ULTRAPASSA o aprovado (2 ja baixado + 5 nao cabe em 3 aprovado) -- deve BLOQUEAR com msg de adicional"
echo "############################################"
rpc "EXECUTOR tenta baixar mais 5un do ITEM_PECA (so restam 1)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":5,\"p_orcamento_item_id\":\"$ITEM_PECA\"}"

echo
echo "############################################"
echo "# D4: completa exatamente o restante (1un) -- item deve virar 'executado'"
echo "############################################"
rpc "EXECUTOR baixa a 1un restante" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_PECA\"}"
echo "--- execucao_status do ITEM_PECA (esperado: executado, 3 de 3) ---"
curl -s "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_PECA&select=id,quantidade,execucao_status" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

echo
echo "############################################"
echo "# D5: tenta baixar peca FORA do escopo aprovado (peca de outro item, informando item errado) -- deve BLOQUEAR"
echo "############################################"
rpc "EXECUTOR tenta baixar PECA_BAIXA usando ITEM_PECA (peca nao bate com o item)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_BAIXA\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_PECA\"}"

echo
echo "############################################"
echo "# E2E-003: estoque insuficiente na baixa real (execucao), erro EXPLICITO, sem saldo negativo"
echo "############################################"
rpc "EXECUTOR tenta baixar 5un do ITEM_BAIXA (aprovado 5, mas estoque so tem 1)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_BAIXA\",\"p_quantidade\":5,\"p_orcamento_item_id\":\"$ITEM_BAIXA\"}"
echo "--- saldo da peca baixa (esperado: continua 1, nunca ficou negativo) ---"
curl -s "$URL/rest/v1/pecas?id=eq.$PECA_BAIXA&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

echo
echo "############################################"
echo "# CONTROLE: OS SEM orcamento (interna) continua permitindo baixa livre (sem p_orcamento_item_id) -- nao regrediu"
echo "############################################"
rpc "ADMIN cria OS interna livre" "$TOK_ENC" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS_LIVRE=$(echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '"')
rpc "transiciona" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_LIVRE\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "EXECUTOR baixa peca SEM orcamento_item_id em OS SEM orcamento (deve funcionar normal)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_LIVRE\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":1}"

echo
echo "ORC=$ORC OS=$OS ITEM_PECA=$ITEM_PECA ITEM_BAIXA=$ITEM_BAIXA PECA=$PECA PECA_BAIXA=$PECA_BAIXA"
echo "=== FIM ==="
