#!/usr/bin/env bash
# ETAPA 3 — lote 3 dos BLOQUEADO: FIN-002/005/007/008/009, LIB-007/008,
# GAR-006, AUD-005, PER-003/005, DOC-004, NFR-001/002/010.
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
echo "# Setup: fluxo completo novo (orçamento->OS externa->concluída->cobrança) p/ FIN e LIB"
echo "############################################"
tbl_post "ENCARREGADO cria orçamento" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "adiciona item (1x R\$400)" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_ID\",\"descricao\":\"TESTE_E03_FIN_LIB\",\"quantidade\":1,\"valor_unitario\":400.00}"
rpc "envia" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"
rpc "autoriza" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento "{\"p_orcamento_id\":\"$ORC_ID\",\"p_autorizado_por_nome\":\"TESTE_Resp_FinLib\",\"p_comprovante_path\":\"comprovantes/e03-finlib.pdf\"}"
rpc "aprova" "$TOK_ENCARREGADO" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"
rpc "converte em OS externa" "$TOK_ENCARREGADO" rpc_criar_os "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\",\"p_checklist_template_id\":\"20000000-0000-0000-0000-000000000001\"}"
OS_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_ID=$OS_ID"
rpc "diagnostico" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "execucao" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"em_execucao\"}"
rpc "aguardando_teste" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"aguardando_teste\"}"
tbl_post "checklist ok" "$TOK_EXECUTOR" "os_checklist_respostas" \
  "{\"os_id\":\"$OS_ID\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
rpc "conclui" "$TOK_ENCARREGADO" rpc_concluir_os "{\"p_os_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# FIN-007 — não presumir pagamento (recém-concluída, SEM cobrança/pagamento ainda)"
echo "############################################"
tbl_get "confirma que NENHUMA cobrança foi criada automaticamente ao concluir a OS" "$TOK_ADMIN" "cobranca_origens?os_id=eq.$OS_ID&select=id"
tbl_get "status da OS após concluir (esperado: 'concluida', não 'liberada'/'paga' automaticamente)" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=id,status,data_liberacao"

echo
echo "############################################"
echo "# LIB-007 — liberar com checklist incompleto: tentativa de alcançar essa precondição"
echo "############################################"
echo "-- checklist já é gate obrigatório em rpc_concluir_os (ver CON-004, lote 2) — não existe caminho na API"
echo "-- para uma OS chegar a 'concluida' com checklist obrigatório pendente. Confirma que não há via de"
echo "-- escrita direta na tabela que bypasse isso (ordens_servico não tem policy de update p/ authenticated):"
call_patch "tenta forçar status=concluida via PATCH direto (bypass), numa OS nova ainda aberta" "$TOK_ADMIN" \
  "$URL/rest/v1/ordens_servico?id=eq.$OS_ID" '{"status":"concluida"}'

echo
echo "############################################"
echo "# FIN-005 — parcelamento inconsistente (soma != valor_total)"
echo "############################################"
rpc "SUPORTE gera cobrança sobre a OS concluída (valor real R\$400)" "$TOK_SUPORTE" rpc_criar_cobranca \
  "{\"p_cliente_id\":\"b0000000-0000-0000-0000-000000000001\",\"p_os_ids\":[\"$OS_ID\"],\"p_venda_ids\":null}"
COB_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "COB_ID=$COB_ID"
tbl_get "valor_total real da cobrança" "$TOK_SUPORTE" "cobrancas?id=eq.$COB_ID&select=valor_total"
rpc "SUPORTE tenta parcelar com soma DIVERGENTE (2 parcelas de R\$100 = 200, != 400)" "$TOK_SUPORTE" rpc_parcelar_cobranca \
  "{\"p_cobranca_id\":\"$COB_ID\",\"p_parcelas\":[{\"numero_parcela\":1,\"valor\":100.00,\"vencimento\":\"$(date -u +%Y-%m-%d)\"},{\"numero_parcela\":2,\"valor\":100.00,\"vencimento\":\"$(date -u +%Y-%m-%d)\"}]}"
tbl_get "confirma que NENHUMA parcela foi criada" "$TOK_SUPORTE" "parcelas?cobranca_id=eq.$COB_ID&select=id"

echo
echo "############################################"
echo "# LIB-007 (continuação, financeiramente elegível mas SEM parcelamento/pagamento ainda) -- controle: liberar deve estar bloqueado por condição financeira, não por checklist (checklist já não é mais um fator aqui)"
echo "############################################"
rpc "ENCARREGADO tenta liberar ANTES de formalizar parcelamento (esperado: bloqueado por condição financeira)" "$TOK_ENCARREGADO" rpc_liberar_os "{\"p_os_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# FIN-008 — pagamento parcial (parcela corretamente formalizada, depois recebimento PARCIAL)"
echo "############################################"
rpc "SUPORTE parcela corretamente em 2x de R\$200 (soma bate)" "$TOK_SUPORTE" rpc_parcelar_cobranca \
  "{\"p_cobranca_id\":\"$COB_ID\",\"p_parcelas\":[{\"numero_parcela\":1,\"valor\":200.00,\"vencimento\":\"$(date -u +%Y-%m-%d)\"},{\"numero_parcela\":2,\"valor\":200.00,\"vencimento\":\"$(date -u -d '+30 days' +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)\"}]}"
tbl_get "parcela 1 criada" "$TOK_SUPORTE" "parcelas?cobranca_id=eq.$COB_ID&numero_parcela=eq.1&select=id,valor,status"
PARCELA1=$(curl -s "$URL/rest/v1/parcelas?cobranca_id=eq.$COB_ID&numero_parcela=eq.1&select=id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "PARCELA1=$PARCELA1"
rpc "SUPORTE registra recebimento PARCIAL de R\$80 (parcela vale R\$200)" "$TOK_SUPORTE" rpc_registrar_recebimento \
  "{\"p_parcela_id\":\"$PARCELA1\",\"p_valor_recebido\":80.00,\"p_forma_pagamento\":\"pix\",\"p_data_recebimento\":\"$(date -u +%Y-%m-%d)\"}"
tbl_get "parcela 1 DEPOIS (esperado: status ainda 'pendente', não 'paga')" "$TOK_SUPORTE" "parcelas?id=eq.$PARCELA1&select=id,valor,status"
tbl_get "cobrança DEPOIS (esperado: status 'parcial')" "$TOK_SUPORTE" "cobrancas?id=eq.$COB_ID&select=id,valor_total,status"

echo
echo "############################################"
echo "# LIB-007 real: agora a OS está financeiramente elegível (tem parcelamento formalizado) — libera normalmente"
echo "############################################"
rpc "ENCARREGADO libera a OS agora (condição financeira satisfeita por parcelamento formalizado)" "$TOK_ENCARREGADO" rpc_liberar_os "{\"p_os_id\":\"$OS_ID\"}"
tbl_get "confirma liberada" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=id,status,data_liberacao"

echo
echo "############################################"
echo "# LIB-008 — dupla liberação"
echo "############################################"
rpc "ENCARREGADO tenta liberar de novo a MESMA OS já liberada (esperado: bloqueado)" "$TOK_ENCARREGADO" rpc_liberar_os "{\"p_os_id\":\"$OS_ID\"}"

echo
echo "############################################"
echo "# FIN-002 — item rejeitado nunca chega a compor cobrança (via orçamento reprovado)"
echo "############################################"
tbl_post "cria orçamento p/ FIN-002" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_FIN002=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "adiciona item" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_FIN002\",\"descricao\":\"TESTE_E03_FIN002_Item_Sera_Rejeitado\",\"quantidade\":1,\"valor_unitario\":250.00}"
rpc "envia" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_FIN002\"}"
rpc "REJEITA o orçamento inteiro (não há rejeição por item nesta versão do sistema)" "$TOK_ENCARREGADO" rpc_rejeitar_orcamento "{\"p_orcamento_id\":\"$ORC_FIN002\"}"
rpc "tenta converter em OS mesmo assim (esperado: bloqueado, item nunca chega a OS/cobrança)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_FIN002\"}"

echo
echo "############################################"
echo "# FIN-009 — alterar valor após pagamento (tenta editar valor_total da cobrança já com recebimento)"
echo "############################################"
call_patch "SUPORTE tenta editar valor_total da cobrança que já tem recebimento parcial registrado" "$TOK_SUPORTE" \
  "$URL/rest/v1/cobrancas?id=eq.$COB_ID" '{"valor_total":1.00}'
tbl_get "confirma valor_total inalterado" "$TOK_ADMIN" "cobrancas?id=eq.$COB_ID&select=id,valor_total"

echo
echo "############################################"
echo "# GAR-006 — tentar alterar data_liberacao diretamente (forçar garantia)"
echo "############################################"
call_patch "ENCARREGADO tenta editar data_liberacao da OS f...0007 (liberada há 100d) para 'hoje' via PATCH direto" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/ordens_servico?id=eq.f0000000-0000-0000-0000-000000000007" "{\"data_liberacao\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
tbl_get "confirma data_liberacao NÃO mudou" "$TOK_ADMIN" "ordens_servico?id=eq.f0000000-0000-0000-0000-000000000007&select=id,data_liberacao"

echo
echo "############################################"
echo "# AUD-005 — alteração de aprovação (histórico anterior permanece após versionar orçamento aprovado)"
echo "############################################"
tbl_get "orçamento e...0003 (aprovado, será versionado) ANTES" "$TOK_ADMIN" "orcamentos?id=eq.e0000000-0000-0000-0000-000000000003&select=id,status,autorizado_por_nome"
echo "-- nota: e...0003 já foi convertido em OS f...0004 no seed original; rpc_criar_versao_orcamento não valida"
echo "-- isso, então usamos um orçamento aprovado NOVO e exclusivo para não interferir com f...0004 --"
tbl_post "cria orçamento aprovado exclusivo p/ AUD-005" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_AUD005=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "adiciona item" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_AUD005\",\"descricao\":\"TESTE_E03_AUD005\",\"quantidade\":1,\"valor_unitario\":60.00}"
rpc "envia" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_AUD005\"}"
rpc "autoriza" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento "{\"p_orcamento_id\":\"$ORC_AUD005\",\"p_autorizado_por_nome\":\"TESTE_Resp_AUD005\",\"p_comprovante_path\":\"comprovantes/e03-aud005.pdf\"}"
rpc "aprova" "$TOK_ENCARREGADO" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC_AUD005\"}"
tbl_get "confirma aprovado, com evidência" "$TOK_ADMIN" "orcamentos?id=eq.$ORC_AUD005&select=id,status,autorizado_por_nome,comprovante_path"
rpc "ENCARREGADO cria nova versão a partir do orçamento APROVADO (only allowed path to 'alter')" "$TOK_ENCARREGADO" rpc_criar_versao_orcamento "{\"p_orcamento_id\":\"$ORC_AUD005\"}"
NOVA_V=$(jf "print(d if isinstance(d,str) else '')")
echo "NOVA_V=$NOVA_V"
tbl_get "orçamento ORIGINAL após versionar (esperado: status='substituido', autorizado_por_nome PRESERVADO — histórico não sumiu)" "$TOK_ADMIN" "orcamentos?id=eq.$ORC_AUD005&select=id,status,autorizado_por_nome,comprovante_path"

echo
echo "############################################"
echo "# PER-003 — encarregado altera preço (operação permitida)"
echo "############################################"
tbl_post "cria orçamento rascunho p/ PER-003" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_PER003=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "adiciona item (preço inicial R\$10)" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_PER003\",\"descricao\":\"TESTE_E03_PER003\",\"quantidade\":1,\"valor_unitario\":10.00}"
ITEM_PER003=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
call_patch "ENCARREGADO altera o preço para R\$25 (esperado: permitido)" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_PER003" '{"valor_unitario":25.00}'

echo
echo "############################################"
echo "# PER-005 — manipulação de ID (tenta editar apontamento de OUTRO usuário)"
echo "############################################"
tbl_get "apontamento existente de OUTRO usuário (encarregado) na OS f...0009" "$TOK_ADMIN" "os_executores?os_id=eq.f0000000-0000-0000-0000-000000000009&select=id,usuario_id&limit=1"
APONT_ID=$(curl -s "$URL/rest/v1/os_executores?os_id=eq.f0000000-0000-0000-0000-000000000009&select=id,usuario_id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "APONT_ID=$APONT_ID"
if [ -n "$APONT_ID" ]; then
call_patch "EXECUTOR (usuario_id diferente) tenta editar o apontamento de OUTRO usuário via manipulação de ID na URL" "$TOK_EXECUTOR" \
  "$URL/rest/v1/os_executores?id=eq.$APONT_ID" '{"observacao":"TESTE_E03_PER005_tentativa_indevida"}'
tbl_get "confirma que a observação NÃO foi alterada" "$TOK_ADMIN" "os_executores?id=eq.$APONT_ID&select=id,usuario_id,observacao"
fi

echo
echo "############################################"
echo "# DOC-004 — termo de débito vinculado à liberação (fluxo novo e exclusivo)"
echo "############################################"
tbl_post "cria cliente inadimplente novo p/ DOC-004 (evita reaproveitar b...0003)" "$TOK_ENCARREGADO" "clientes" \
  '{"tipo":"externo","nome":"TESTE_E03_Cliente_DOC004","documento":"77777777000107"}'
CLI_DOC004=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "veículo novo" "$TOK_ENCARREGADO" "veiculos" \
  "{\"cliente_id\":\"$CLI_DOC004\",\"placa\":\"TSE0402\",\"prefixo\":\"E03D\",\"modelo\":\"TESTE_DOC004\",\"ano\":2021}"
VEI_DOC004=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "orçamento" "$TOK_ENCARREGADO" "orcamentos" \
  "{\"veiculo_id\":\"$VEI_DOC004\",\"cliente_id\":\"$CLI_DOC004\",\"status\":\"rascunho\",\"versao\":1,\"criado_por\":\"a0000000-0000-0000-0000-000000000002\"}"
ORC_DOC004=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item" "$TOK_ENCARREGADO" "orcamento_itens" "{\"orcamento_id\":\"$ORC_DOC004\",\"descricao\":\"TESTE_E03_DOC004\",\"quantidade\":1,\"valor_unitario\":150.00}"
rpc "envia" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_DOC004\"}"
rpc "autoriza" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento "{\"p_orcamento_id\":\"$ORC_DOC004\",\"p_autorizado_por_nome\":\"TESTE_Resp_DOC004\",\"p_comprovante_path\":\"comprovantes/e03-doc004.pdf\"}"
rpc "aprova" "$TOK_ENCARREGADO" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC_DOC004\"}"
rpc "converte" "$TOK_ENCARREGADO" rpc_criar_os "{\"p_veiculo_id\":\"$VEI_DOC004\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_DOC004\",\"p_checklist_template_id\":\"20000000-0000-0000-0000-000000000001\"}"
OS_DOC004=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_DOC004=$OS_DOC004"
rpc "diagnostico" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_DOC004\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "execucao" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_DOC004\",\"p_novo_status\":\"em_execucao\"}"
rpc "aguardando_teste" "$TOK_ENCARREGADO" rpc_transicionar_os "{\"p_os_id\":\"$OS_DOC004\",\"p_novo_status\":\"aguardando_teste\"}"
tbl_post "checklist ok" "$TOK_EXECUTOR" "os_checklist_respostas" \
  "{\"os_id\":\"$OS_DOC004\",\"template_item_id\":\"20000000-0000-0000-0000-000000000011\",\"ok\":true,\"respondido_por\":\"a0000000-0000-0000-0000-000000000001\",\"respondido_em\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
rpc "conclui" "$TOK_ENCARREGADO" rpc_concluir_os "{\"p_os_id\":\"$OS_DOC004\"}"
rpc "SUPORTE gera cobrança" "$TOK_SUPORTE" rpc_criar_cobranca "{\"p_cliente_id\":\"$CLI_DOC004\",\"p_os_ids\":[\"$OS_DOC004\"],\"p_venda_ids\":null}"
COB_DOC004=$(jf "print(d if isinstance(d,str) else '')")
echo "COB_DOC004=$COB_DOC004"
rpc "ENCARREGADO registra termo de ciência de débito (cliente não vai pagar agora)" "$TOK_ENCARREGADO" rpc_registrar_termo_ciencia \
  "{\"p_cobranca_id\":\"$COB_DOC004\",\"p_arquivo_path\":\"comprovantes/e03-termo-doc004.pdf\"}"
rpc "ENCARREGADO libera a OS (condição financeira satisfeita pelo termo)" "$TOK_ENCARREGADO" rpc_liberar_os "{\"p_os_id\":\"$OS_DOC004\"}"
tbl_get "DOC-004: consulta a OS liberada + o termo vinculado via cobranca_origens/termos_ciencia_debito" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_DOC004&select=id,status,data_liberacao"
tbl_get "termo vinculado à cobrança desta OS" "$TOK_ADMIN" "termos_ciencia_debito?cobranca_id=eq.$COB_DOC004&select=id,cobranca_id,arquivo_path,assinado_em"

echo
echo "############################################"
echo "# NFR-001 — atomicidade: falha forçada em rpc_criar_os (orçamento não pertence ao veículo)"
echo "############################################"
tbl_get "contagem de OS ANTES da tentativa forçada a falhar" "$TOK_ADMIN" "ordens_servico?select=id" | grep -c '"id"' || true
COUNT_BEFORE=$(curl -s "$URL/rest/v1/ordens_servico?select=id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" -H "Prefer: count=exact" -I | grep -i content-range || true)
echo "content-range antes: $COUNT_BEFORE"
rpc "tenta converter e...0003 (aprovado, mas pertence a c...0001) informando um p_veiculo_id DIFERENTE (c...0002) -> falha no meio da RPC" "$TOK_ENCARREGADO" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"externa","p_orcamento_id":"e0000000-0000-0000-0000-000000000003"}'
COUNT_AFTER=$(curl -s "$URL/rest/v1/ordens_servico?select=id" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" -H "Prefer: count=exact" -I | grep -i content-range || true)
echo "content-range depois: $COUNT_AFTER"
echo "(se os dois content-range forem iguais, nenhuma OS parcial foi criada pela tentativa que falhou no meio da função -> atomicidade confirmada)"

echo
echo "############################################"
echo "# NFR-002 — atomicidade no estorno: falha forçada (movimento inexistente)"
echo "############################################"
tbl_get "saldo da peça EST001 (lote 2) ANTES da tentativa de estorno inválido" "$TOK_ADMIN" "pecas?sku=eq.QA_PECA_EST001_E03&select=id,saldo_atual"
rpc "SUPORTE tenta estornar um movimento_id INEXISTENTE (força exceção 'não encontrado' no meio da função)" "$TOK_SUPORTE" rpc_estornar_saida_estoque \
  '{"p_movimento_id":"00000000-0000-0000-0000-000000000000"}'
tbl_get "saldo da peça EST001 DEPOIS (esperado: inalterado, nenhum efeito parcial)" "$TOK_ADMIN" "pecas?sku=eq.QA_PECA_EST001_E03&select=id,saldo_atual"

echo
echo "############################################"
echo "# NFR-010 — erro controlado de arquivo (download de objeto inexistente no Storage)"
echo "############################################"
curl -s -o /tmp/_nfr010.json -w "HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/comprovantes/arquivo-que-nao-existe-e03-$(date +%s).pdf" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE"
cat /tmp/_nfr010.json; echo

echo
echo "=== FIM LOTE 3 ==="
