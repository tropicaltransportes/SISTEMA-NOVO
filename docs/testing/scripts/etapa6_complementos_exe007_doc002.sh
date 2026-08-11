#!/usr/bin/env bash
# ETAPA 6 (P1-C) — complementos: EXE-007 (tamanho excessivo, path inexistente,
# usuário sem permissão) e DOC-002 (PDF de V1 continua reproduzível depois de
# existir V2).
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")
TS=$(date +%s)

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
tbl_get() { call "$1" GET "$2" "$URL/rest/v1/$3"; }
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }
ENC_ID="a0000000-0000-0000-0000-000000000002"

echo "############################################"
echo "# Setup rapido: OS interna so p/ testar upload de foto (tamanho/path/permissao)"
echo "############################################"
tbl_post "cliente interno" "$TOK_SUP" "clientes" "{\"tipo\":\"interno\",\"nome\":\"TESTE_P1C_EXE007_$TS\",\"telefone\":\"1\"}"
CLI=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "veiculo" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLI\",\"placa\":\"EXE007$TS\",\"modelo\":\"TESTE\"}"
VEI=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "cria OS interna" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEI\",\"p_tipo\":\"interna\"}"
OS=$(echo "$BODY" | tr -d '"')
echo "OS=$OS"

echo
echo "############################################"
echo "# EXE-007a: path inexistente -- deve BLOQUEAR (objeto nunca foi enviado ao Storage)"
echo "############################################"
rpc "registra foto com path que nunca foi enviado -- deve falhar" "$TOK_ENC" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"antes\",\"p_arquivo_path\":\"$OS/antes/nunca-existiu-$TS.jpg\"}"

echo
echo "############################################"
echo "# EXE-007b: tamanho excessivo -- reduz limite para 10 bytes, envia arquivo maior, tenta registrar -- deve BLOQUEAR"
echo "############################################"
rpc "ADMIN reduz limite de anexos para 10 bytes (so p/ este teste)" "$TOK_ADM" rpc_definir_anexos_config '{"p_tamanho_maximo_bytes": 10, "p_mime_permitidos": ["image/jpeg","image/png","image/webp"]}'
PATH_GRANDE="$OS/antes/grande-$TS.jpg"
curl -s -o /dev/null -X POST "$URL/storage/v1/object/os-fotos/$PATH_GRANDE" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: image/jpeg" \
  --data-binary "ESTE_ARQUIVO_TEM_MAIS_DE_10_BYTES_DE_PROPOSITO_PARA_TESTAR_O_LIMITE"
rpc "registra foto maior que o limite -- deve falhar" "$TOK_ENC" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"antes\",\"p_arquivo_path\":\"$PATH_GRANDE\"}"
rpc "ADMIN restaura limite para 5MB" "$TOK_ADM" rpc_definir_anexos_config '{"p_tamanho_maximo_bytes": 5242880, "p_mime_permitidos": ["image/jpeg","image/png","image/webp"]}'

echo
echo "############################################"
echo "# EXE-007c: usuario sem permissao (executor NAO vinculado a esta OS) -- deve BLOQUEAR"
echo "############################################"
TOK_EXE2=$(login "teste.executor2.p1c@qa.local")
PATH_SEMPERM="$OS/antes/semperm-$TS.jpg"
curl -s -o /dev/null -X POST "$URL/storage/v1/object/os-fotos/$PATH_SEMPERM" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: image/jpeg" \
  --data-binary "conteudo"
rpc "executor NAO vinculado tenta registrar foto -- deve falhar" "$TOK_EXE2" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"antes\",\"p_arquivo_path\":\"$PATH_SEMPERM\"}"

echo
echo "############################################"
echo "# DOC-002: PDF da V1 continua reproduzivel depois de existir V2"
echo "############################################"
tbl_post "cliente externo p/ DOC-002" "$TOK_SUP" "clientes" "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1C_DOC002_$TS\",\"documento\":\"999$TS\",\"telefone\":\"1\"}"
CLI2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "veiculo p/ DOC-002" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLI2\",\"placa\":\"DOC002$TS\",\"modelo\":\"TESTE\"}"
VEI2=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "orcamento rascunho" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEI2\",\"cliente_id\":\"$CLI2\",\"criado_por\":\"$ENC_ID\"}"
ORC_V1=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item V1" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC_V1\",\"descricao\":\"TESTE item V1\",\"quantidade\":1,\"valor_unitario\":100}"
rpc "envia V1" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_V1\"}"
rpc "PDF da V1 (antes de existir V2)" "$TOK_ENC" rpc_dados_pdf_orcamento "{\"p_orcamento_id\":\"$ORC_V1\"}"
rpc "cria V2 a partir da V1" "$TOK_ENC" rpc_criar_versao_orcamento "{\"p_orcamento_id\":\"$ORC_V1\"}"
ORC_V2=$(echo "$BODY" | tr -d '"')
echo "ORC_V1=$ORC_V1 ORC_V2=$ORC_V2"
rpc "PDF da V1 DEPOIS de existir V2 -- deve continuar igual/reproduzivel" "$TOK_ENC" rpc_dados_pdf_orcamento "{\"p_orcamento_id\":\"$ORC_V1\"}"
rpc "PDF da V2 (nova versao)" "$TOK_ENC" rpc_dados_pdf_orcamento "{\"p_orcamento_id\":\"$ORC_V2\"}"

echo "=== FIM COMPLEMENTOS ==="
