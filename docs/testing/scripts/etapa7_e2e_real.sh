#!/usr/bin/env bash
# ETAPA 7 — E2E-001 (fluxo completo), E2E-007 (múltiplos executores), contra
# o projeto dev/teste autorizado. Usa variáveis de shell (não arquivos em
# /tmp) para capturar respostas — em Git Bash no Windows, "/tmp/..." é
# traduzido pelas ferramentas MSYS (curl, cat) mas NÃO pelo python.exe
# nativo, causando FileNotFoundError se um script tenta abrir o mesmo
# caminho depois de escrito por curl.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")

# Faz o POST/RPC, imprime "HTTP <code>" + corpo, e deixa o corpo em $BODY p/
# quem chamou extrair campos com: echo "$BODY" | python -c "..."
call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  local resp
  if [ -n "$body" ]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" \
      -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -H "Prefer: return=representation" -d "$body")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | sed '$d')
  echo "HTTP $HTTP_CODE"
  echo "$BODY"
}
rpc() { call "$1" POST "$2" "$URL/rest/v1/rpc/$3" "$4"; }
tbl_get() { call "$1" GET "$2" "$URL/rest/v1/$3"; }
tbl_post() { call "$1" POST "$2" "$URL/rest/v1/$3" "$4"; }

jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# E2E-001 — cliente externo normal, fluxo completo DE VERDADE DESDE O ORÇAMENTO"
echo "# (orçamentos aprovados do seed já estão todos vinculados a uma OS — criando um"
echo "#  novo, mais fiel ao fluxo real: orçar -> enviar -> autorizar -> aprovar -> converter)"
echo "# reusa cliente b...0001/veículo c...0001 (externo, já existentes no seed)"
echo "############################################"

tbl_post "0a) ENCARREGADO cria orçamento rascunho" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC_ID=$ORC_ID"

tbl_post "0b) ENCARREGADO adiciona item ao orçamento (peça d...0005, 2un x R\$100)" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_ID\",\"peca_id\":\"d0000000-0000-0000-0000-000000000005\",\"descricao\":\"PGTAP Servico E2E-001\",\"quantidade\":2,\"valor_unitario\":100.00}"

rpc "0c) ENCARREGADO envia o orçamento" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"
rpc "0d) SUPORTE registra autorização do cliente externo" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento \
  "{\"p_orcamento_id\":\"$ORC_ID\",\"p_autorizado_por_nome\":\"TESTE_Responsavel_E2E001\",\"p_comprovante_path\":\"comprovantes/pgtap-e2e001.pdf\"}"
rpc "0e) ENCARREGADO aprova o orçamento" "$TOK_ENCARREGADO" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"

rpc "1) ENCARREGADO converte orçamento aprovado em OS externa" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\"}"
OS_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_ID=$OS_ID"

rpc "1b) tentar reconverter o MESMO orçamento (OS-004/P0-03 — esperado: bloqueado)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\"}"

rpc "2) ENCARREGADO define checklist técnico" "$TOK_ENCARREGADO" rpc_definir_checklist_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_checklist_template_id\":\"20000000-0000-0000-0000-000000000001\"}"

rpc "3) ENCARREGADO inicia diagnóstico (aberta -> em_diagnostico)" "$TOK_ENCARREGADO" rpc_transicionar_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_diagnostico\"}"

rpc "4) ENCARREGADO inicia execução (em_diagnostico -> em_execucao)" "$TOK_ENCARREGADO" rpc_transicionar_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_execucao\"}"

INICIO_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tbl_post "5a) EXECUTOR insere apontamento" "$TOK_EXECUTOR" "os_executores" \
  "{\"os_id\":\"$OS_ID\",\"usuario_id\":\"a0000000-0000-0000-0000-000000000001\",\"etapa\":\"execucao\",\"inicio\":\"$INICIO_TS\"}"

rpc "5b) EXECUTOR baixa 2un da peça d...0005 vinculada ao orçamento aprovado" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_peca_id\":\"d0000000-0000-0000-0000-000000000005\",\"p_quantidade\":2}"

rpc "6) ENCARREGADO envia p/ teste (em_execucao -> aguardando_teste)" "$TOK_ENCARREGADO" rpc_transicionar_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"aguardando_teste\"}"

RESP_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tbl_post "7) responde item obrigatório do checklist (ok=true)" "$TOK_EXECUTOR" "os_checklist_respostas" \
  "{\"os_id\":\"$OS_ID\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"$RESP_TS\"}"

rpc "8) ENCARREGADO conclui a OS (checklist completo)" "$TOK_ENCARREGADO" rpc_concluir_os "{\"p_os_id\":\"$OS_ID\"}"

rpc "9) SUPORTE gera cobrança sobre a OS concluída" "$TOK_SUPORTE" rpc_criar_cobranca \
  "{\"p_cliente_id\":\"b0000000-0000-0000-0000-000000000001\",\"p_os_ids\":[\"$OS_ID\"],\"p_venda_ids\":null}"
COB_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "COB_ID=$COB_ID"

tbl_get "valor_total real da cobrança (evita hardcode)" "$TOK_SUPORTE" "cobrancas?id=eq.$COB_ID&select=valor_total"
VALOR_TOTAL=$(jf "print(d[0]['valor_total'] if d else '0')")
echo "VALOR_TOTAL=$VALOR_TOTAL"

rpc "10) SUPORTE parcela em 1x à vista" "$TOK_SUPORTE" rpc_parcelar_cobranca \
  "{\"p_cobranca_id\":\"$COB_ID\",\"p_parcelas\":[{\"numero_parcela\":1,\"valor\":$VALOR_TOTAL,\"vencimento\":\"$(date -u +%Y-%m-%d)\"}]}"

tbl_get "11) busca id da parcela criada" "$TOK_SUPORTE" "parcelas?cobranca_id=eq.$COB_ID&select=id"
PARCELA_ID=$(jf "print(d[0]['id'] if d else '')")
echo "PARCELA_ID=$PARCELA_ID"

rpc "12) SUPORTE registra pagamento total ($VALOR_TOTAL)" "$TOK_SUPORTE" rpc_registrar_recebimento \
  "{\"p_parcela_id\":\"$PARCELA_ID\",\"p_valor_recebido\":$VALOR_TOTAL,\"p_forma_pagamento\":\"pix\",\"p_data_recebimento\":\"$(date -u +%Y-%m-%d)\"}"

rpc "13) ENCARREGADO libera a OS (cobrança quitada — deve funcionar)" "$TOK_ENCARREGADO" rpc_liberar_os "{\"p_os_id\":\"$OS_ID\"}"

tbl_get "E2E-001: estado final da OS (esperado: liberada, data_liberacao preenchida)" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=status,data_liberacao,tipo"

rpc "14) GAR — ENCARREGADO abre garantia a partir da OS recém-liberada (dentro do prazo)" "$TOK_ENCARREGADO" rpc_criar_os_garantia "{\"p_os_origem_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# E2E-007 — múltiplos executores na mesma OS (usa a mesma OS_ID acima)"
echo "############################################"
INICIO2_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tbl_post "2º executor aponta observação na mesma OS" "$TOK_ENCARREGADO" "os_executores" \
  "{\"os_id\":\"$OS_ID\",\"usuario_id\":\"a0000000-0000-0000-0000-000000000002\",\"etapa\":\"revisao\",\"inicio\":\"$INICIO2_TS\",\"observacao\":\"PGTAP segundo executor\"}"

tbl_get "os_executores da OS (esperado: 2 linhas, um por usuário)" "$TOK_ADMIN" "os_executores?os_id=eq.$OS_ID&select=usuario_id,etapa,observacao"

echo
echo "=== FIM ETAPA 7 ==="
