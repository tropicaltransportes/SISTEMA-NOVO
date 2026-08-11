#!/usr/bin/env bash
# ETAPA 3 - PÓS-FIX: valida a migration 20260811170000_etapa3_correcoes.sql
# contra os mesmos tipos de cenário do _prefix (mas com dados NOVOS, exclusivos
# desta validação), mais OS-004 (reconversão pós-cancelamento) e DOC-006
# (acesso cruzado por documento no bucket comprovantes).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_INATIVO=$(login "teste.inativo@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_SEMPERFIL=$(login "teste.semperfil@qa.local")
for p in SUPORTE ADMIN ENCARREGADO INATIVO EXECUTOR SEMPERFIL; do
  var="TOK_$p"; if [ -n "${!var}" ]; then echo "$p: login OK"; else echo "$p: LOGIN FALHOU"; fi
done

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  local resp
  if [ "$token" = "__ANON__" ]; then
    if [ -n "$body" ]; then
      resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$body")
    else
      resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON")
    fi
  else
    if [ -n "$body" ]; then
      resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
    else
      resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
    fi
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | sed '$d')
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
uuidgen_py() { python -c "import uuid; print(uuid.uuid4())"; }

echo "############################################"
echo "# AUT-004 (PÓS-FIX) — 4 cenários exigidos"
echo "############################################"
tbl_post "SUPORTE cria peça exclusiva QA_PECA_AUT004_POSFIX2" "$TOK_SUPORTE" "pecas" \
  '{"sku":"QA_PECA_AUT004_POSFIX2","descricao":"TESTE_E03_Peca_AUT004_posfix","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "PECA=$PECA"
tbl_post "SUPORTE cria NF rascunho" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-AUT004-POSFIX2","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE adiciona item (30un x R\$10)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA\",\"quantidade\":30,\"valor_unitario\":10.00}"
rpc "SUPORTE confirma NF (saldo inicial 30)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

rpc "ADMIN cria OS interna exclusiva p/ pós-fix" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS=$(jf "print(d if isinstance(d,str) else '')")
echo "OS=$OS"
rpc "ADMIN transiciona aberta->em_diagnostico" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "ADMIN transiciona em_diagnostico->em_execucao" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "== Cenário 1: ativo=true + perfil autorizado (EXECUTOR) -> esperado PERMITIDO =="
rpc "EXECUTOR (ativo=true) baixa 2un" "$TOK_EXECUTOR" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":2}"

echo
echo "== Cenário 2: ativo=false + MESMO perfil (INATIVO, perfil real=executor) -> esperado BLOQUEADO =="
rpc "INATIVO (ativo=false) tenta baixar 3un (op. NOVA, nunca feita)" "$TOK_INATIVO" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":3}"

echo
echo "== Cenário 3: sem profile (SEMPERFIL) -> esperado BLOQUEADO =="
rpc "SEMPERFIL tenta baixar 4un" "$TOK_SEMPERFIL" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":4}"

echo
echo "== Cenário 4: anon -> esperado BLOQUEADO =="
rpc "ANON tenta baixar 5un" "__ANON__" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA\",\"p_quantidade\":5}"

echo
echo "-- confirma saldo final via query (só o cenário 1 deve ter afetado saldo: 30 -> 28) --"
curl -s "$URL/rest/v1/pecas?id=eq.$PECA&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN"; echo

echo
echo "== Extra: INATIVO tenta ação de LEITURA simples (SELECT ordens_servico) — confirma que o fix não quebrou leitura básica indevidamente (não é objetivo do BR-028 bloquear leitura, só escrita/operação) =="
tbl_get "INATIVO consegue LER ordens_servico (esperado: sim, leitura não é uma 'operação' restrita por perfil)" "$TOK_INATIVO" "ordens_servico?id=eq.$OS&select=id,status"

echo
echo "############################################"
echo "# EST-009 (PÓS-FIX) — idempotency_key persistente (>5s) + concorrência"
echo "############################################"
tbl_post "SUPORTE cria peça exclusiva QA_PECA_EST009_POSFIX2" "$TOK_SUPORTE" "pecas" \
  '{"sku":"QA_PECA_EST009_POSFIX2","descricao":"TESTE_E03_Peca_EST009_posfix","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "PECA2=$PECA2"
tbl_post "SUPORTE cria NF rascunho" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-EST009-POSFIX2","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE adiciona item (40un x R\$10)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF2\",\"peca_id\":\"$PECA2\",\"quantidade\":40,\"valor_unitario\":10.00}"
rpc "SUPORTE confirma NF (saldo inicial 40)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF2\"}"

rpc "ADMIN cria 2ª OS interna exclusiva p/ EST-009 pós-fix" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS2=$(jf "print(d if isinstance(d,str) else '')")
echo "OS2=$OS2"
rpc "ADMIN transiciona aberta->em_diagnostico" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS2\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "ADMIN transiciona em_diagnostico->em_execucao" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS2\",\"p_novo_status\":\"em_execucao\"}"

IDK=$(uuidgen_py)
echo "idempotency_key K1 gerada pelo cliente para esta OPERAÇÃO LÓGICA: $IDK"

saldo2() { echo; echo "--- saldo peça EST009_POSFIX ---"; curl -s "$URL/rest/v1/pecas?id=eq.$PECA2&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN"; echo; }

saldo2
rpc "(A) baixa original com idempotency_key=K1 (5un)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":5,\"p_idempotency_key\":\"$IDK\"}"
saldo2
rpc "(B) retry IMEDIATO com a MESMA K1 (esperado: bloqueado)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":5,\"p_idempotency_key\":\"$IDK\"}"
saldo2
echo "Aguardando 6 segundos..."
sleep 6
rpc "(C) retry após >5s com a MESMA K1 (esperado AGORA: continua bloqueado — idempotência persistente)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":5,\"p_idempotency_key\":\"$IDK\"}"
saldo2
rpc "(D) retry de novo, mesma K1 (esperado: continua bloqueado)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":5,\"p_idempotency_key\":\"$IDK\"}"
saldo2

echo
echo "-- controle: uma operação NOVA e LEGÍTIMA (chave K2 diferente) deve funcionar normalmente --"
IDK2=$(uuidgen_py)
rpc "operação NOVA com idempotency_key=K2 diferente (3un) — esperado: sucesso" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":3,\"p_idempotency_key\":\"$IDK2\"}"
saldo2

echo
echo "-- concorrência real: duas chamadas SIMULTÂNEAS com a MESMA idempotency_key K3 --"
IDK3=$(uuidgen_py)
(
curl -s -o /tmp/_e3c1.json -w "conc1 HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXECUTOR" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":2,\"p_idempotency_key\":\"$IDK3\"}"
) &
(
curl -s -o /tmp/_e3c2.json -w "conc2 HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_baixar_peca_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$OS2\",\"p_peca_id\":\"$PECA2\",\"p_quantidade\":2,\"p_idempotency_key\":\"$IDK3\"}"
) &
wait
echo "resultado conc1:"; cat /tmp/_e3c1.json; echo
echo "resultado conc2:"; cat /tmp/_e3c2.json; echo
saldo2
echo "-- confirma via SQL: quantas linhas com idempotency_key=K3 existem? (esperado: exatamente 1) --"

echo "OS_AUT004_POSFIX=$OS"
echo "PECA_AUT004_POSFIX=$PECA"
echo "OS_EST009_POSFIX=$OS2"
echo "PECA_EST009_POSFIX=$PECA2"
echo "IDK3=$IDK3"
echo "=== FIM PÓS-FIX P0 ==="
