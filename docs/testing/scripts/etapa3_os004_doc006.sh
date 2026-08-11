#!/usr/bin/env bash
# ETAPA 3 — OS-004 (reconversão de orçamento após cancelamento da OS) e
# DOC-006 (modelo real de autorização por documento no bucket comprovantes).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_DIRETORIA=$(login "teste.diretoria@qa.local")

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
tbl_get() { call "$1" GET "$2" "$URL/rest/v1/$3"; }
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }

echo "############################################"
echo "# OS-004 — orçamento aprovado -> OS -> cancelar OS -> reconverter o MESMO orçamento"
echo "############################################"
tbl_post "ENCARREGADO cria orçamento rascunho (cliente/veículo externo b...0001/c...0001)" "$TOK_ENCARREGADO" "orcamentos" \
  '{"veiculo_id":"c0000000-0000-0000-0000-000000000001","cliente_id":"b0000000-0000-0000-0000-000000000001","status":"rascunho","versao":1,"criado_por":"a0000000-0000-0000-0000-000000000002"}'
ORC_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC_ID=$ORC_ID"
tbl_post "ENCARREGADO adiciona item (1un x R\$90, mão de obra)" "$TOK_ENCARREGADO" "orcamento_itens" \
  "{\"orcamento_id\":\"$ORC_ID\",\"descricao\":\"TESTE_E03_OS004_Servico\",\"quantidade\":1,\"valor_unitario\":90.00}"
rpc "ENCARREGADO envia orçamento" "$TOK_ENCARREGADO" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"
rpc "SUPORTE registra autorização do cliente externo" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento \
  "{\"p_orcamento_id\":\"$ORC_ID\",\"p_autorizado_por_nome\":\"TESTE_Responsavel_OS004\",\"p_comprovante_path\":\"comprovantes/e03-os004.pdf\"}"
rpc "ENCARREGADO aprova orçamento" "$TOK_ENCARREGADO" rpc_aprovar_orcamento "{\"p_orcamento_id\":\"$ORC_ID\"}"

rpc "1) ENCARREGADO converte em OS externa (1ª conversão, esperado: sucesso)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\"}"
OS_ID=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_ID=$OS_ID"

rpc "2) tentativa de reconverter ENQUANTO a OS ainda está ativa (controle — esperado: bloqueado, já confirmado na rodada 2)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\"}"

rpc "3) ENCARREGADO cancela a OS (aberta -> cancelada)" "$TOK_ENCARREGADO" rpc_transicionar_os \
  "{\"p_os_id\":\"$OS_ID\",\"p_novo_status\":\"cancelada\"}"

tbl_get "confirma status da OS após cancelamento" "$TOK_ADMIN" "ordens_servico?id=eq.$OS_ID&select=id,status"

echo
echo "4) ENCARREGADO tenta CONVERTER O MESMO ORÇAMENTO DE NOVO, agora que a OS está cancelada"
rpc "reconversão do MESMO orçamento pós-cancelamento (comportamento a REGISTRAR, não alterar)" "$TOK_ENCARREGADO" rpc_criar_os \
  "{\"p_veiculo_id\":\"c0000000-0000-0000-0000-000000000001\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC_ID\"}"
OS_ID_2=$(jf "print(d if isinstance(d,str) else '')")
echo "OS_ID_2 (se criada)=$OS_ID_2"

tbl_get "quantas OS existem para este orcamento_id agora?" "$TOK_ADMIN" "ordens_servico?orcamento_id=eq.$ORC_ID&select=id,status"

echo
echo "############################################"
echo "# DOC-006 — modelo real de autorização por documento no bucket 'comprovantes'"
echo "# Documento A: comprovante do orçamento X (cliente A). Documento B: comprovante"
echo "# de um orçamento Y TOTALMENTE diferente (cliente diferente). Teste de acesso"
echo "# cruzado: ENCARREGADO (que só participou do fluxo do doc A) lê o doc B; e"
echo "# SUPORTE (que só participou do fluxo do doc B) lê o doc A."
echo "############################################"

# Documento A: sobe via SUPORTE, ligado ao orçamento OS-004 acima (ORC_ID / cliente b...0001)
DOC_A_PATH="comprovantes/e03-doc006-A-$(date +%s).txt"
echo "DOC_A_PATH=$DOC_A_PATH"
echo; echo "--- SUPORTE faz upload do Documento A ---"
curl -s -o /tmp/_docA.json -w "HTTP %{http_code}\n" -X POST "$URL/storage/v1/object/$DOC_A_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE" -H "Content-Type: text/plain" \
  --data-binary "TESTE_E03_DOC_A conteudo exclusivo A $(date)"
cat /tmp/_docA.json; echo

# Documento B: sobe via ENCARREGADO, ligado a um cliente/orçamento DIFERENTE (cliente garantia b...0004)
DOC_B_PATH="comprovantes/e03-doc006-B-$(date +%s).txt"
echo "DOC_B_PATH=$DOC_B_PATH"
echo; echo "--- ENCARREGADO faz upload do Documento B ---"
curl -s -o /tmp/_docB.json -w "HTTP %{http_code}\n" -X POST "$URL/storage/v1/object/$DOC_B_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENCARREGADO" -H "Content-Type: text/plain" \
  --data-binary "TESTE_E03_DOC_B conteudo exclusivo B $(date)"
cat /tmp/_docB.json; echo

echo
echo "-- ENCARREGADO (nunca fez upload/participou do doc A) tenta LER o Documento A --"
curl -s -o /tmp/_readA_by_enc.json -w "HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/$DOC_A_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENCARREGADO"
cat /tmp/_readA_by_enc.json; echo

echo
echo "-- SUPORTE (nunca fez upload/participou do doc B) tenta LER o Documento B --"
curl -s -o /tmp/_readB_by_sup.json -w "HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/$DOC_B_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUPORTE"
cat /tmp/_readB_by_sup.json; echo

echo
echo "-- DIRETORIA (nunca participou de NENHUM dos dois) tenta ler A e B --"
curl -s -o /tmp/_readA_by_dir.json -w "Doc A HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/$DOC_A_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_DIRETORIA"
cat /tmp/_readA_by_dir.json; echo
curl -s -o /tmp/_readB_by_dir.json -w "Doc B HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/$DOC_B_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_DIRETORIA"
cat /tmp/_readB_by_dir.json; echo

echo
echo "-- EXECUTOR (perfil bloqueado por completo no fix P0-02) tenta ler A --"
curl -s -o /tmp/_readA_by_exec.json -w "HTTP %{http_code}\n" "$URL/storage/v1/object/authenticated/$DOC_A_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXECUTOR"
cat /tmp/_readA_by_exec.json; echo

echo
echo "CONCLUSAO ESPERADA: se ENCARREGADO le B e SUPORTE le A (documentos aos quais NUNCA tiveram"
echo "vinculo/participacao) com HTTP 200, e DIRETORIA (fora de qualquer um dos 2 fluxos) tambem le"
echo "ambos com 200, o modelo é (A) SOMENTE POR PERFIL (qualquer perfil <> executor lê QUALQUER"
echo "documento do bucket, independente de vínculo com o registro). Se desse erro, seria (B) por vínculo."
echo "=== FIM OS-004 / DOC-006 ==="
