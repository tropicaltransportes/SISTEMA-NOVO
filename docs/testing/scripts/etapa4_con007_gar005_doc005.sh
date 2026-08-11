#!/usr/bin/env bash
# ETAPA 4 (P1-A) — item F (CON-007), item G (GAR-005), item I (DOC-005).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
SERVICE_KEY_NOTE="usa apenas apikey anon + login de usuario real, sem service_role"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")

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
echo "# F (CON-007): apontamento nao editavel apos OS encerrada; correcao formal auditada"
echo "############################################"
rpc "cria OS interna exclusiva" "$TOK_ENC" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS=$(echo "$BODY" | tr -d '"')
echo "OS=$OS"
tbl_post "EXECUTOR cria apontamento" "$TOK_EXE" os_executores \
  "{\"os_id\":\"$OS\",\"usuario_id\":\"a0000000-0000-0000-0000-000000000001\",\"etapa\":\"diagnostico\",\"inicio\":\"2026-08-12T10:00:00Z\",\"observacao\":\"inicio\"}"
EXEC_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "EXEC_ID=$EXEC_ID"
call "EXECUTOR edita o proprio apontamento -- OS ainda aberta, deve PASSAR" PATCH "$TOK_EXE" "$URL/rest/v1/os_executores?id=eq.$EXEC_ID" '{"observacao":"editado enquanto aberta"}'

rpc "define checklist" "$TOK_ENC" rpc_definir_checklist_os "{\"p_os_id\":\"$OS\",\"p_checklist_template_id\":\"20000000-0000-0000-0000-000000000001\"}"
rpc "aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"
rpc "em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"
tbl_post "responde checklist obrigatorio" "$TOK_EXE" os_checklist_respostas \
  "{\"os_id\":\"$OS\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"2026-08-12T00:00:00Z\"}"
rpc "conclui OS" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"
echo "--- status da OS apos concluir ---"
curl -s "$URL/rest/v1/ordens_servico?id=eq.$OS&select=status" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

call "EXECUTOR tenta editar o MESMO apontamento apos OS CONCLUIDA -- deve BLOQUEAR (0 linhas)" PATCH "$TOK_EXE" "$URL/rest/v1/os_executores?id=eq.$EXEC_ID" '{"observacao":"tentativa pos-conclusao"}'
call "confirma que observacao NAO mudou" GET "$TOK_ENC" "$URL/rest/v1/os_executores?id=eq.$EXEC_ID&select=observacao"

rpc "ENCARREGADO tenta rpc_corrigir_apontamento SEM motivo -- deve BLOQUEAR" "$TOK_ENC" rpc_corrigir_apontamento \
  "{\"p_execucao_id\":\"$EXEC_ID\",\"p_nova_observacao\":\"correcao sem motivo\"}"
rpc "ENCARREGADO corrige via RPC formal COM motivo -- deve PASSAR (auditado)" "$TOK_ENC" rpc_corrigir_apontamento \
  "{\"p_execucao_id\":\"$EXEC_ID\",\"p_nova_observacao\":\"corrigido apos deteccao de horario errado\",\"p_motivo\":\"Executor esqueceu de preencher observacao correta antes da OS ser concluida\"}"
call "confirma correcao aplicada" GET "$TOK_ENC" "$URL/rest/v1/os_executores?id=eq.$EXEC_ID&select=observacao"
call "confirma trilha de auditoria da correcao" GET "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?entidade=eq.os_executores&entidade_id=eq.$EXEC_ID&select=acao,motivo,valor_anterior,valor_novo"

echo
echo "############################################"
echo "# G (GAR-005): vinculo de garantia com item original; sem vinculo bloqueia"
echo "############################################"
OS_ORIGINAL="f0000000-0000-0000-0000-000000000006"
ITEM_ORIGINAL="bbeec7c0-fa1f-461d-8961-a7cdbd605c78"
rpc "tenta abrir garantia SEM informar itens (OS original tem orcamento) -- deve BLOQUEAR" "$TOK_ENC" rpc_criar_os_garantia \
  "{\"p_os_origem_id\":\"$OS_ORIGINAL\"}"
rpc "abre garantia COM item original vinculado -- deve PASSAR" "$TOK_ENC" rpc_criar_os_garantia \
  "{\"p_os_origem_id\":\"$OS_ORIGINAL\",\"p_itens_originais\":[\"$ITEM_ORIGINAL\"]}"
OS_GARANTIA=$(echo "$BODY" | tr -d '"')
echo "OS_GARANTIA=$OS_GARANTIA"
call "confirma vinculo em os_garantia_itens" GET "$TOK_ENC" "$URL/rest/v1/os_garantia_itens?os_garantia_id=eq.$OS_GARANTIA&select=orcamento_item_original_id,motivo"

rpc "transiciona garantia p/ em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GARANTIA\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "tenta baixar peca NAO vinculada a este item de garantia (peca diferente, informando o item certo)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_GARANTIA\",\"p_peca_id\":\"d0000000-0000-0000-0000-000000000002\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_ORIGINAL\"}"
echo "^^^ esperado: bloqueado (peca nao bate com o item original)"
rpc "baixa a peca CORRETA vinculada ao item original da garantia -- deve PASSAR" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_GARANTIA\",\"p_peca_id\":\"d0000000-0000-0000-0000-000000000001\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_ORIGINAL\"}"

echo
echo "############################################"
echo "# I (DOC-005): comprovante/termo so aceito se objeto existe no Storage"
echo "############################################"
tbl_post "cria orcamento novo p/ testar autorizacao" "$TOK_ENC" orcamentos \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_DOC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item obrigatorio" "$TOK_ENC" orcamento_itens "{\"orcamento_id\":\"$ORC_DOC\",\"descricao\":\"TESTE item doc005\",\"quantidade\":1,\"valor_unitario\":10}"
rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_DOC\"}"

rpc "tenta registrar autorizacao com path INEXISTENTE no storage -- deve BLOQUEAR" "$TOK_ENC" rpc_registrar_autorizacao_orcamento \
  "{\"p_orcamento_id\":\"$ORC_DOC\",\"p_autorizado_por_nome\":\"TESTE\",\"p_comprovante_path\":\"caminho/que-nao-existe-p1a-doc005.pdf\"}"

echo "--- upload real de um arquivo no bucket comprovantes ---"
PATH_REAL="p1a-doc005/$(date +%s)-comprovante.txt"
resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/storage/v1/object/comprovantes/$PATH_REAL" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: text/plain" --data-binary "conteudo de teste P1A DOC-005")
echo "upload -> HTTP $(echo "$resp" | tail -n1)"
echo "PATH_REAL=$PATH_REAL"

rpc "registra autorizacao com path REAL (existe no storage) -- deve PASSAR" "$TOK_ENC" rpc_registrar_autorizacao_orcamento \
  "{\"p_orcamento_id\":\"$ORC_DOC\",\"p_autorizado_por_nome\":\"TESTE Responsavel\",\"p_comprovante_path\":\"$PATH_REAL\"}"

echo "--- remove o objeto do storage (simula race: documento removido antes de outro uso) ---"
curl -s -X DELETE "$URL/storage/v1/object/comprovantes/$PATH_REAL" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo
rpc "tenta reusar o MESMO path (agora removido) num termo de ciencia -- deve BLOQUEAR" "$TOK_ENC" rpc_registrar_termo_ciencia \
  "{\"p_cobranca_id\":\"10000000-0000-0000-0000-000000000001\",\"p_arquivo_path\":\"$PATH_REAL\"}"

echo
echo "=== FIM ==="
