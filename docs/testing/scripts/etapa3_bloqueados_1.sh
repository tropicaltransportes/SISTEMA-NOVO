#!/usr/bin/env bash
# ETAPA 3 — lote 1 dos BLOQUEADO: AUT-007/008/010, CAD-001/002/003/005/006/
# 007/008/009/011, ORC-002/003/006/015, APR-003/008/009/010/011.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))"; }
login_full() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}"; }
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_DIRETORIA=$(login "teste.diretoria@qa.local")

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  local resp
  if [ "$token" = "__ANON__" ]; then
    if [ -n "$body" ]; then resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$body")
    else resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON"); fi
  else
    if [ -n "$body" ]; then resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
    else resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token"); fi
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | sed '$d')
  echo "HTTP $HTTP_CODE"
  echo "$BODY"
}
call_patch() {
  local label="$1" token="$2" url="$3" body="$4"
  echo; echo "--- $label ---"
  local resp=$(curl -s -w '\n%{http_code}' -X PATCH "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  HTTP_CODE=$(echo "$resp" | tail -n1); BODY=$(echo "$resp" | sed '$d')
  echo "HTTP $HTTP_CODE"; echo "$BODY"
}
call_delete() {
  local label="$1" token="$2" url="$3"
  echo; echo "--- $label ---"
  local resp=$(curl -s -w '\n%{http_code}' -X DELETE "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Prefer: return=representation")
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
echo "# AUT-007 — Logout: sessão deixa de permitir operações protegidas?"
echo "############################################"
LOGIN_JSON=$(login_full "teste.executor@qa.local")
AT=$(echo "$LOGIN_JSON" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")
RT=$(echo "$LOGIN_JSON" | python -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))")
echo "access_token obtido, refresh_token obtido"
tbl_get "ANTES do logout: EXECUTOR lê ordens_servico (esperado: 200)" "$AT" "ordens_servico?limit=1&select=id"
echo; echo "--- chama /auth/v1/logout ---"
curl -s -o /tmp/_logout.json -w "HTTP %{http_code}\n" -X POST "$URL/auth/v1/logout?scope=global" -H "apikey: $ANON" -H "Authorization: Bearer $AT"
cat /tmp/_logout.json; echo
tbl_get "DEPOIS do logout: MESMO access_token tenta ler ordens_servico de novo" "$AT" "ordens_servico?limit=1&select=id"
echo; echo "--- tenta usar o refresh_token pós-logout (esperado: negado, pois scope=global revoga) ---"
curl -s -o /tmp/_refresh.json -w "HTTP %{http_code}\n" -X POST "$URL/auth/v1/token?grant_type=refresh_token" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"refresh_token\":\"$RT\"}"
cat /tmp/_refresh.json; echo

echo
echo "############################################"
echo "# AUT-008 — Elevação indevida de perfil (executor tenta virar administrador_tecnico)"
echo "############################################"
call_patch "EXECUTOR tenta alterar o PRÓPRIO perfil via PATCH direto em profiles" "$TOK_EXECUTOR" \
  "$URL/rest/v1/profiles?id=eq.a0000000-0000-0000-0000-000000000001" '{"perfil":"administrador_tecnico"}'
tbl_get "confirma perfil real após a tentativa" "$TOK_ADMIN" "profiles?id=eq.a0000000-0000-0000-0000-000000000001&select=id,perfil"

echo
echo "############################################"
echo "# AUT-010 — Credenciais em resposta (checagem de vazamento em claro)"
echo "############################################"
echo "$LOGIN_JSON" > /tmp/_login_body_aut010.json
echo "corpo da resposta de login (sem grep de senha abaixo, ver NFR-009 no relatório final)"
python -c "
import json
d = json.load(open('/tmp/_login_body_aut010.json'))
print('chaves top-level da resposta de login:', sorted(d.keys()))
leaked = 'Teste@2026' in json.dumps(d)
print('senha em claro encontrada na resposta?', leaked)
"

echo
echo "############################################"
echo "# CAD-001/002/003 — cadastro de cliente"
echo "############################################"
tbl_post "CAD-001: ENCARREGADO cria cliente EXTERNO válido" "$TOK_ENCARREGADO" "clientes" \
  '{"tipo":"externo","nome":"TESTE_E03_Cliente_Externo_CAD001","documento":"55555555000105","telefone":"(11) 90000-0101","email":"cad001@teste.qa"}'
CLI_EXT=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLI_EXT=$CLI_EXT"

tbl_post "CAD-002: ENCARREGADO cria cliente INTERNO válido" "$TOK_ENCARREGADO" "clientes" \
  '{"tipo":"interno","nome":"TESTE_E03_Cliente_Interno_CAD002","telefone":"(11) 90000-0102"}'
CLI_INT=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLI_INT=$CLI_INT"

tbl_post "CAD-003: ENCARREGADO tenta criar cliente SEM nome (campo obrigatório)" "$TOK_ENCARREGADO" "clientes" \
  '{"tipo":"externo","documento":"66666666000106"}'

echo
echo "############################################"
echo "# CAD-005/006/007 — cadastro de veículo"
echo "############################################"
if [ -n "$CLI_EXT" ]; then
tbl_post "CAD-005: ENCARREGADO cadastra veículo vinculado ao cliente novo" "$TOK_ENCARREGADO" "veiculos" \
  "{\"cliente_id\":\"$CLI_EXT\",\"placa\":\"TSE0301\",\"prefixo\":\"E03A\",\"modelo\":\"TESTE_Modelo_E03\",\"ano\":2023}"
fi

tbl_post "CAD-006: ENCARREGADO tenta cadastrar OUTRO veículo com a MESMA placa (TSE0301)" "$TOK_ENCARREGADO" "veiculos" \
  "{\"cliente_id\":\"$CLI_EXT\",\"placa\":\"TSE0301\",\"prefixo\":\"E03B\",\"modelo\":\"TESTE_Modelo_E03_Dup\",\"ano\":2024}"

tbl_post "CAD-007: ENCARREGADO tenta cadastrar veículo SEM cliente_id" "$TOK_ENCARREGADO" "veiculos" \
  '{"placa":"TSE0399","prefixo":"E03Z","modelo":"TESTE_Sem_Cliente","ano":2020}'

echo
echo "############################################"
echo "# CAD-008 — alterar dados do cliente (sem perder histórico transacional)"
echo "############################################"
if [ -n "$CLI_EXT" ]; then
call_patch "ENCARREGADO altera telefone/email do cliente novo" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/clientes?id=eq.$CLI_EXT" '{"telefone":"(11) 99999-0101","email":"cad001-novo@teste.qa"}'
fi

echo
echo "############################################"
echo "# CAD-009 — inativar cliente COM histórico (usa b...0001, que já tem OS/orçamento/cobrança reais)"
echo "############################################"
tbl_get "ANTES: cliente b...0001 tem quantas OS vinculadas?" "$TOK_ADMIN" "ordens_servico?cliente_id=eq.b0000000-0000-0000-0000-000000000001&select=id"
call_patch "SUPORTE inativa cliente b...0001 (soft delete via deleted_at)" "$TOK_SUPORTE" \
  "$URL/rest/v1/clientes?id=eq.b0000000-0000-0000-0000-000000000001" "{\"deleted_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
tbl_get "DEPOIS: histórico de OS deste cliente continua consultável?" "$TOK_ADMIN" "ordens_servico?cliente_id=eq.b0000000-0000-0000-0000-000000000001&select=id,status"
tbl_get "cliente aparece marcado como inativo (deleted_at preenchido)?" "$TOK_ADMIN" "clientes?id=eq.b0000000-0000-0000-0000-000000000001&select=id,nome,deleted_at"
echo "-- reverte a inativação para não afetar outros testes/relatórios anteriores que referenciam b...0001 --"
call_patch "SUPORTE reverte deleted_at do cliente b...0001 para null" "$TOK_SUPORTE" \
  "$URL/rest/v1/clientes?id=eq.b0000000-0000-0000-0000-000000000001" '{"deleted_at":null}'

echo
echo "############################################"
echo "# CAD-011 — troca de vínculo (proprietário) de veículo com histórico"
echo "############################################"
tbl_get "ANTES: veículo c...0001 pertence a qual cliente, e sua OS f...0004 (concluída) mostra qual cliente_id?" "$TOK_ADMIN" "veiculos?id=eq.c0000000-0000-0000-0000-000000000001&select=id,cliente_id"
tbl_get "OS f...0004 cliente_id ANTES da troca" "$TOK_ADMIN" "ordens_servico?id=eq.f0000000-0000-0000-0000-000000000004&select=id,cliente_id"
if [ -n "$CLI_INT" ]; then
call_patch "ENCARREGADO troca o cliente_id do veículo c...0001 para o cliente interno novo (simulação de troca de proprietário)" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/veiculos?id=eq.c0000000-0000-0000-0000-000000000001" "{\"cliente_id\":\"$CLI_INT\"}"
fi
tbl_get "DEPOIS: veículo c...0001 agora pertence a qual cliente?" "$TOK_ADMIN" "veiculos?id=eq.c0000000-0000-0000-0000-000000000001&select=id,cliente_id"
tbl_get "OS f...0004 cliente_id DEPOIS da troca (esperado: NÃO muda — histórico preservado)" "$TOK_ADMIN" "ordens_servico?id=eq.f0000000-0000-0000-0000-000000000004&select=id,cliente_id"
echo "-- reverte o vínculo do veículo para o cliente original b...0001 --"
call_patch "ENCARREGADO reverte cliente_id do veículo c...0001 para b...0001" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/veiculos?id=eq.c0000000-0000-0000-0000-000000000001" '{"cliente_id":"b0000000-0000-0000-0000-000000000001"}'

echo
echo "############################################"
echo "# ORC-002/003 — orçamento sem cliente / sem veículo"
echo "############################################"
tbl_post "ORC-002: ENCARREGADO tenta criar orçamento SEM cliente_id" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
tbl_post "ORC-003: ENCARREGADO tenta criar orçamento SEM veiculo_id" "$TOK_ENCARREGADO" "orcamentos" \
  '{"cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'

echo
echo "############################################"
echo "# ORC-006 — alterar quantidade de item (recálculo de subtotal/total)"
echo "############################################"
tbl_get "orçamento e...0001 (rascunho) ANTES: valor_total e itens" "$TOK_ADMIN" "orcamentos?id=eq.e0000000-0000-0000-0000-000000000001&select=id,valor_total"
tbl_get "item do e...0001" "$TOK_ADMIN" "orcamento_itens?orcamento_id=eq.e0000000-0000-0000-0000-000000000001&select=id,quantidade,valor_unitario,valor_total"
ITEM_ID=$(curl -s "$URL/rest/v1/orcamento_itens?orcamento_id=eq.e0000000-0000-0000-0000-000000000001&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "ITEM_ID=$ITEM_ID"
if [ -n "$ITEM_ID" ]; then
call_patch "ENCARREGADO altera quantidade do item de 1 para 5" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_ID" '{"quantidade":5}'
fi
tbl_get "orçamento e...0001 DEPOIS: valor_total deve ter recalculado (5x100=500)" "$TOK_ADMIN" "orcamentos?id=eq.e0000000-0000-0000-0000-000000000001&select=id,valor_total"
tbl_get "item DEPOIS" "$TOK_ADMIN" "orcamento_itens?orcamento_id=eq.e0000000-0000-0000-0000-000000000001&select=id,quantidade,valor_unitario,valor_total"
echo "-- reverte quantidade para 1 (estado original do seed) --"
if [ -n "$ITEM_ID" ]; then
call_patch "ENCARREGADO reverte quantidade para 1" "$TOK_ENCARREGADO" "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_ID" '{"quantidade":1}'
fi

echo
echo "############################################"
echo "# ORC-015 — editar orçamento ENVIADO (cenário novo, não reaproveita e...0002)"
echo "############################################"
tbl_post "ENCARREGADO cria orçamento novo p/ ORC-015" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC015_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC015_ID=$ORC015_ID"
tbl_post "adiciona item" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC015_ID\",\"descricao\":\"TESTE_E03_ORC015\",\"quantidade\":1,\"valor_unitario\":70.00}"
ORC015_ITEM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "ENCARREGADO envia o orçamento (rascunho -> enviado)" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC015_ID\"}"
call_patch "ENCARREGADO tenta EDITAR o item diretamente, agora que o orçamento está 'enviado' (esperado: bloqueado por RLS)" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamento_itens?id=eq.$ORC015_ITEM" '{"valor_unitario":999.00}'
tbl_get "confirma que o valor NÃO mudou" "$TOK_ADMIN" "orcamento_itens?id=eq.$ORC015_ITEM&select=id,valor_unitario"
echo "-- caminho controlado e correto: versionar o orçamento (preserva o original) --"
rpc "ENCARREGADO cria nova versão a partir do orçamento enviado" "$TOK_ENCARREGADO" rpc_criar_versao_orcamento "{\"p_orcamento_id\":\"$ORC015_ID\"}"
NOVA_VERSAO_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "NOVA_VERSAO_ID=$NOVA_VERSAO_ID"
tbl_get "orçamento ORIGINAL após versionar (esperado: status=substituido, preservado, NÃO apagado)" "$TOK_ADMIN" "orcamentos?id=eq.$ORC015_ID&select=id,status,versao"
tbl_get "NOVA versão (esperado: rascunho, versao=2, aponta orcamento_raiz_id pro original)" "$TOK_ADMIN" "orcamentos?id=eq.$NOVA_VERSAO_ID&select=id,status,versao,orcamento_raiz_id"

echo
echo "############################################"
echo "# APR-003 — reprovação integral bloqueia conversão em OS"
echo "############################################"
tbl_post "ENCARREGADO cria orçamento novo p/ APR-003" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
APR003_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "adiciona item" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$APR003_ID\",\"descricao\":\"TESTE_E03_APR003\",\"quantidade\":1,\"valor_unitario\":50.00}"
rpc "ENCARREGADO envia" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$APR003_ID\"}"
rpc "ENCARREGADO REPROVA o orçamento" "$TOK_ENCARREGADO" rpc_rejeitar_orcamento "{\"p_orcamento_id\":\"$APR003_ID\"}"
tbl_get "confirma status=rejeitado" "$TOK_ADMIN" "orcamentos?id=eq.$APR003_ID&select=id,status"
rpc "ENCARREGADO tenta converter o orçamento REJEITADO em OS (esperado: bloqueado)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$APR003_ID\"}"

echo
echo "############################################"
echo "# APR-008/009/010/011 — item aprovado é imutável fora de RPC (usa e...0006, aprovado, ainda não convertido em OS nesta rodada)"
echo "############################################"
tbl_get "orçamento e...0006 (aprovado) — item atual" "$TOK_ADMIN" "orcamento_itens?orcamento_id=eq.e0000000-0000-0000-0000-000000000006&select=id,valor_unitario,quantidade"
ITEM_0006=$(curl -s "$URL/rest/v1/orcamento_itens?orcamento_id=eq.e0000000-0000-0000-0000-000000000006&select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
echo "ITEM_0006=$ITEM_0006"
call_patch "APR-008: ENCARREGADO tenta ALTERAR PREÇO de item já aprovado (esperado: bloqueado, RLS exige rascunho)" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_0006" '{"valor_unitario":9999.00}'
call_patch "APR-009: ENCARREGADO tenta ALTERAR QUANTIDADE de item já aprovado (esperado: bloqueado)" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_0006" '{"quantidade":50}'
tbl_post "APR-010: ENCARREGADO tenta ADICIONAR NOVO item a orçamento já aprovado (esperado: bloqueado)" "$TOK_ENCARREGADO" "orcamento_itens" \
  '{"orcamento_id":"e0000000-0000-0000-0000-000000000006","descricao":"TESTE_E03_Item_Pos_Aprovacao","quantidade":1,"valor_unitario":10.00}'
tbl_get "confirma que o item NÃO mudou (preço/quantidade originais)" "$TOK_ADMIN" "orcamento_itens?id=eq.$ITEM_0006&select=id,valor_unitario,quantidade"
call_patch "APR-011: ENCARREGADO tenta APAGAR a evidência de aprovação (autorizado_por_nome/comprovante_path) do e...0006" "$TOK_ENCARREGADO" \
  "$URL/rest/v1/orcamentos?id=eq.e0000000-0000-0000-0000-000000000006" '{"autorizado_por_nome":null,"comprovante_path":null}'
tbl_get "confirma que a evidência de aprovação PERMANECE" "$TOK_ADMIN" "orcamentos?id=eq.e0000000-0000-0000-0000-000000000006&select=id,status,autorizado_por_nome,comprovante_path"

echo
echo "=== FIM LOTE 1 ==="
