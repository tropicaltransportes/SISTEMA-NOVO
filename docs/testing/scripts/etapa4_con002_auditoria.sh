#!/usr/bin/env bash
# ETAPA 4 (P1-A) — item E (CON-002) e item H (AUD-001/002/003), execução real.
# Reaproveita a OS/itens/orcamento montados por etapa4_est004_e2e003.sh
# (ITEM_PECA ja executado, ITEM_MDO ainda pendente, ITEM_BAIXA pendente).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")

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

# ORC/OS/ITEM ids do teste anterior (etapa4_est004_e2e003.sh)
ORC="818b64ac-00f7-4f18-a4f6-d803719fb6ac"
OS="87cf422d-8914-4095-abeb-6a3e89f25568"
ITEM_MDO="0c226844-d0a9-412d-8043-0d3a19f363cc"
ITEM_BAIXA="d89ce089-af77-4d4b-b045-6b6af92fd42a"
TEMPLATE_ID="20000000-0000-0000-0000-000000000001"

echo "############################################"
echo "# preparar: define checklist, avanca a OS ate aguardando_teste, responde checklist obrigatorio"
echo "############################################"
rpc "define checklist" "$TOK_ENC" rpc_definir_checklist_os "{\"p_os_id\":\"$OS\",\"p_checklist_template_id\":\"$TEMPLATE_ID\"}"
rpc "em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"
rpc "em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"
call "responde item obrigatorio do checklist (upsert)" POST "$TOK_EXE" "$URL/rest/v1/os_checklist_respostas" \
  "{\"os_id\":\"$OS\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"2026-08-12T00:00:00Z\"}"

echo
echo "############################################"
echo "# E1: tenta concluir com ITEM_MDO (mao de obra) ainda 'pendente' e ITEM_BAIXA 'pendente' -- deve BLOQUEAR (checklist ok, mas itens nao)"
echo "############################################"
rpc "tenta concluir OS (itens aprovados ainda pendentes)" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo
echo "############################################"
echo "# E2: marca ITEM_MDO como executado (mao de obra, sem sinal automatico)"
echo "############################################"
rpc "encarregado marca ITEM_MDO executado" "$TOK_ENC" rpc_marcar_item_orcamento_execucao \
  "{\"p_orcamento_item_id\":\"$ITEM_MDO\",\"p_status\":\"executado\"}"

echo
echo "############################################"
echo "# E3: tenta concluir ainda com ITEM_BAIXA pendente -- deve continuar BLOQUEADO"
echo "############################################"
rpc "tenta concluir (ITEM_BAIXA ainda pendente)" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo
echo "############################################"
echo "# E4: cancela ITEM_BAIXA sem motivo -- deve BLOQUEAR (motivo obrigatorio)"
echo "############################################"
rpc "tenta cancelar ITEM_BAIXA sem motivo" "$TOK_ENC" rpc_marcar_item_orcamento_execucao \
  "{\"p_orcamento_item_id\":\"$ITEM_BAIXA\",\"p_status\":\"cancelado\"}"

echo
echo "############################################"
echo "# E5: cancela ITEM_BAIXA com motivo (peca sem estoque suficiente, decisao operacional) -- deve PASSAR"
echo "############################################"
rpc "cancela ITEM_BAIXA com motivo" "$TOK_ENC" rpc_marcar_item_orcamento_execucao \
  "{\"p_orcamento_item_id\":\"$ITEM_BAIXA\",\"p_status\":\"cancelado\",\"p_motivo\":\"Estoque insuficiente no fornecedor, cliente ciente e dispensou o item\"}"

echo
echo "############################################"
echo "# E6: agora conclui a OS -- deve PASSAR (todos os itens: executado/executado/cancelado)"
echo "############################################"
rpc "conclui OS" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"
echo "--- status final da OS ---"
curl -s "$URL/rest/v1/ordens_servico?id=eq.$OS&select=id,status" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC"; echo

echo
echo "############################################"
echo "# H: trilha de auditoria — confirma que os eventos criticos ficaram registrados"
echo "############################################"
call "EXECUTOR (nao-gestao) tenta ler auditoria -- deve ser filtrado (0 linhas, nao erro)" GET "$TOK_EXE" "$URL/rest/v1/auditoria_eventos?entidade_id=eq.$OS&select=*"
call "ENCARREGADO le eventos de auditoria da OS (mudanca_status)" GET "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?entidade=eq.ordens_servico&entidade_id=eq.$OS&select=acao,valor_anterior,valor_novo,usuario_id,criado_em&order=criado_em.asc"
call "ENCARREGADO le eventos de auditoria do item MDO (marcar_execucao_item)" GET "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?entidade=eq.orcamento_itens&entidade_id=eq.$ITEM_MDO&select=acao,valor_anterior,valor_novo,motivo"
call "ENCARREGADO le eventos de auditoria do item BAIXA (cancelado com motivo)" GET "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?entidade=eq.orcamento_itens&entidade_id=eq.$ITEM_BAIXA&select=acao,valor_anterior,valor_novo,motivo"

echo
echo "############################################"
echo "# H (imutabilidade): auditoria nao pode ser alterada/apagada por usuario comum"
echo "############################################"
AUD_ID=$(curl -s "$URL/rest/v1/auditoria_eventos?entidade=eq.ordens_servico&entidade_id=eq.$OS&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "AUD_ID=$AUD_ID"
call "ENCARREGADO (gestao) tenta UPDATE direto em auditoria_eventos -- deve ser negado" PATCH "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?id=eq.$AUD_ID" '{"motivo":"tentativa de adulterar"}'
call "ADMIN tenta DELETE direto em auditoria_eventos -- deve ser negado" DELETE "$TOK_ENC" "$URL/rest/v1/auditoria_eventos?id=eq.$AUD_ID"

echo
echo "=== FIM ==="
