#!/usr/bin/env bash
# ETAPA 3 - PRÉ-FIX: reproduz de forma limpa e isolada os dois gaps que a
# ETAPA 3 pediu para revalidar antes de qualquer correção nova:
#   - AUT-004: profiles.ativo=false não bloqueia operação (cenário 100% novo,
#     sem reaproveitar OS/peça de rodadas anteriores, para não cair no
#     bloqueio de dedup do EST-009 por engano).
#   - EST-009: a janela de 5s de dedup não é idempotência persistente —
#     repetir a MESMA operação lógica depois de >5s duplica a baixa.
# Rodado ANTES de aplicar a migration nova (20260811170000_correcoes_etapa3.sql).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_INATIVO=$(login "teste.inativo@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")

call() {
  local label="$1" method="$2" token="$3" url="$4" body="${5:-}"
  echo; echo "--- $label ---"
  local resp
  if [ -n "$body" ]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Prefer: return=representation" -d "$body")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
  fi
  HTTP_CODE=$(echo "$resp" | tail -n1)
  BODY=$(echo "$resp" | sed '$d')
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
echo "# SETUP: peça e OS EXCLUSIVAS desta rodada (sufixo _E03), nunca tocadas antes"
echo "############################################"
tbl_post "SUPORTE cria peça exclusiva QA_PECA_AUT004_E03" "$TOK_SUPORTE" "pecas" \
  '{"sku":"QA_PECA_AUT004_E03","descricao":"TESTE_E03_Peca_AUT004","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA_AUT004=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "PECA_AUT004=$PECA_AUT004"

# entrada inicial via movimento direto não é permitido ao cliente (só RPC) -
# usamos NF de entrada real (EST-001) para dar saldo de forma 100% via API.
tbl_post "SUPORTE cria NF de entrada rascunho (peça AUT004)" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-AUT004","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF_AUT004=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "NF_AUT004=$NF_AUT004"
tbl_post "SUPORTE adiciona item à NF (20un x R\$10)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF_AUT004\",\"peca_id\":\"$PECA_AUT004\",\"quantidade\":20,\"valor_unitario\":10.00}"
rpc "SUPORTE confirma NF (EST-001 de brinde)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF_AUT004\"}"

rpc "ADMIN cria OS interna EXCLUSIVA (rpc_criar_os)" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS_AUT004=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_AUT004=$OS_AUT004"

rpc "ADMIN transiciona aberta->em_diagnostico" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_AUT004\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "ADMIN transiciona em_diagnostico->em_execucao" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_AUT004\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# AUT-004 (PRÉ-FIX) — cenário 100% limpo: usuário INATIVO, OS nova, peça nova,"
echo "# quantidade nunca usada antes (3un). Operação permitida ao perfil ORIGINAL"
echo "# do usuário (executor pode baixar peça em OS em_execucao)."
echo "############################################"
rpc "INATIVO (ativo=false, perfil real=executor) tenta baixar 3un da peça E03 na OS nova" "$TOK_INATIVO" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_AUT004\",\"p_peca_id\":\"$PECA_AUT004\",\"p_quantidade\":3}"
echo "^^^ Se HTTP 204 acima: AUT-004 = FALHOU CONFIRMADO (ativo=false não bloqueou operação real e nova)."

echo
echo "############################################"
echo "# EST-009 (PRÉ-FIX) — janela de 5s não é idempotência persistente"
echo "############################################"
tbl_post "SUPORTE cria 2ª peça exclusiva QA_PECA_EST009_E03" "$TOK_SUPORTE" "pecas" \
  '{"sku":"QA_PECA_EST009_E03","descricao":"TESTE_E03_Peca_EST009","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA_EST009=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "PECA_EST009=$PECA_EST009"
tbl_post "SUPORTE cria NF de entrada rascunho (peça EST009)" "$TOK_SUPORTE" "notas_fiscais_entrada" \
  '{"numero":"NF-E03-EST009","fornecedor":"TESTE_Fornecedor_E03","status":"rascunho","data_emissao":"2026-08-11","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF_EST009=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "SUPORTE adiciona item à NF (30un x R\$10)" "$TOK_SUPORTE" "nf_entrada_itens" \
  "{\"nf_id\":\"$NF_EST009\",\"peca_id\":\"$PECA_EST009\",\"quantidade\":30,\"valor_unitario\":10.00}"
rpc "SUPORTE confirma NF (saldo inicial 30)" "$TOK_SUPORTE" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF_EST009\"}"

rpc "ADMIN cria 2ª OS interna EXCLUSIVA p/ EST-009" "$TOK_ADMIN" rpc_criar_os \
  '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
OS_EST009=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_EST009=$OS_EST009"
rpc "ADMIN transiciona aberta->em_diagnostico" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_EST009\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "ADMIN transiciona em_diagnostico->em_execucao" "$TOK_ADMIN" rpc_transicionar_os "{\"p_os_id\":\"$OS_EST009\",\"p_novo_status\":\"em_execucao\"}"

saldo() {
  echo; echo "--- saldo atual peça EST009 ---"
  curl -s "$URL/rest/v1/pecas?id=eq.$PECA_EST009&select=sku,saldo_atual" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN"; echo
}

saldo
rpc "(A) EXECUTOR baixa 4un (operação original)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_EST009\",\"p_peca_id\":\"$PECA_EST009\",\"p_quantidade\":4}"
saldo
rpc "(B) EXECUTOR repete IMEDIATAMENTE a mesma baixa (esperado: bloqueado pela janela de 5s)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_EST009\",\"p_peca_id\":\"$PECA_EST009\",\"p_quantidade\":4}"
saldo
echo "Aguardando 6 segundos para a janela de dedup expirar..."
sleep 6
rpc "(C) EXECUTOR repete a MESMA operação lógica após >5s (esperado se BUG: sucesso = duplicou)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_EST009\",\"p_peca_id\":\"$PECA_EST009\",\"p_quantidade\":4}"
saldo
echo "^^^ Se saldo caiu de novo (de 26 para 22) no passo (C): EST-009 NÃO está corrigido de forma completa — confirma o achado."
rpc "(D) EXECUTOR repete de novo, imediatamente após (C)" "$TOK_EXECUTOR" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_EST009\",\"p_peca_id\":\"$PECA_EST009\",\"p_quantidade\":4}"
saldo

echo
echo "OS_AUT004=$OS_AUT004"
echo "PECA_AUT004=$PECA_AUT004"
echo "OS_EST009=$OS_EST009"
echo "PECA_EST009=$PECA_EST009"
echo "=== FIM PRÉ-FIX ==="
