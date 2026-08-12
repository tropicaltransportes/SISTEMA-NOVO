#!/usr/bin/env bash
# ETAPA 7 (RC1) — item 11: storage real (buckets comprovantes, os-fotos)
# com anon, executor, suporte, encarregado, administrador, diretoria,
# inativo, sem-perfil. Read/upload/delete/path manipulation/MIME/tamanho/
# arquivo inexistente.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() {
  local email="$1" tries=0 tok=""
  while [ $tries -lt 5 ] && [ -z "$tok" ]; do
    tok=$(curl -s --max-time 15 -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"$PASS\"}" | python -c "import sys,json
try:
  print(json.load(sys.stdin).get('access_token',''))
except Exception:
  print('')")
    tries=$((tries+1))
    [ -z "$tok" ] && sleep 2
  done
  echo "$tok"
}
TOK_EXE=$(login "teste.executor@qa.local")
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")
TOK_DIR=$(login "teste.diretoria@qa.local")
TOK_INATIVO=$(login "teste.inativo@qa.local")
TOK_SEMPERFIL=$(login "teste.semperfil@qa.local")
echo "logins: EXE=${#TOK_EXE} ENC=${#TOK_ENC} SUP=${#TOK_SUP} ADM=${#TOK_ADM} DIR=${#TOK_DIR} INATIVO=${#TOK_INATIVO} SEMPERFIL=${#TOK_SEMPERFIL} (tamanho do token, 0 = falhou)"

req() {
  local label="$1" method="$2" token="$3" url="$4" ctype="${5:-}" data="${6:-}"
  local authhdr=()
  if [ -n "$token" ]; then authhdr=(-H "Authorization: Bearer $token"); else authhdr=(-H "Authorization: Bearer $ANON"); fi
  local out; out=$(mktemp)
  echo; echo "--- $label ---"
  local code
  if [ -n "$data" ]; then
    code=$(curl -s --max-time 20 -o "$out" -w "%{http_code}" -X "$method" "$url" -H "apikey: $ANON" "${authhdr[@]}" -H "Content-Type: $ctype" --data-binary "$data")
  else
    code=$(curl -s --max-time 20 -o "$out" -w "%{http_code}" -X "$method" "$url" -H "apikey: $ANON" "${authhdr[@]}")
  fi
  echo "HTTP $code"
  head -c 300 "$out"; echo
  rm -f "$out"
}

TS=$(date +%s)
COMPROVANTE_PATH="rc1-teste/$TS-comprovante.pdf"
OSFOTO_OWNED_OS="f0000000-0000-0000-0000-000000000009"   # OS onde o executor de teste ESTA vinculado (seed)
OSFOTO_FOREIGN_OS="f0000000-0000-0000-0000-000000000002" # OS onde o executor de teste NAO esta vinculado

echo "############### UPLOAD (INSERT) — comprovantes ###############"
req "anon upload comprovantes -- esperado bloqueado" POST "" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"
req "executor upload comprovantes -- esperado bloqueado (RLS exclui executor)" POST "$TOK_EXE" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"
req "diretoria upload comprovantes -- esperado bloqueado (so encarregado/suporte/admin)" POST "$TOK_DIR" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"
req "inativo upload comprovantes -- esperado bloqueado" POST "$TOK_INATIVO" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"
req "sem-perfil upload comprovantes -- esperado bloqueado" POST "$TOK_SEMPERFIL" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"
req "suporte upload comprovantes -- esperado PERMITIDO" POST "$TOK_SUP" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH" "application/pdf" "%PDF-1.4 fake"

echo
echo "############### READ (SELECT/GET) — comprovantes ###############"
req "anon le comprovantes -- esperado bloqueado" GET "" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "executor le comprovantes -- esperado bloqueado (RLS exclui executor da leitura tambem)" GET "$TOK_EXE" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "diretoria le comprovantes -- esperado PERMITIDO (so nao pode e nao esta excluida da leitura)" GET "$TOK_DIR" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "suporte le comprovantes (proprio upload) -- esperado PERMITIDO" GET "$TOK_SUP" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "inativo le comprovantes -- esperado bloqueado" GET "$TOK_INATIVO" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "arquivo inexistente (suporte) -- esperado 404" GET "$TOK_SUP" "$URL/storage/v1/object/comprovantes/rc1-teste/nao-existe-$TS.pdf"

echo
echo "############### DELETE — comprovantes (esperado bloqueado para TODOS -- sem policy DELETE = deny) ###############"
req "admin tenta apagar comprovante -- esperado bloqueado (sem policy DELETE)" DELETE "$TOK_ADM" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"
req "suporte (dono do upload) tenta apagar -- esperado bloqueado" DELETE "$TOK_SUP" "$URL/storage/v1/object/comprovantes/$COMPROVANTE_PATH"

echo
echo "############### UPLOAD (INSERT) — os-fotos, incluindo manipulacao de path ###############"
req "anon upload os-fotos -- esperado bloqueado" POST "" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/teste/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'
req "executor upload em OS onde ESTA vinculado -- esperado PERMITIDO" POST "$TOK_EXE" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/teste/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'
req "executor upload em OS onde NAO esta vinculado (path manipulation) -- esperado bloqueado" POST "$TOK_EXE" "$URL/storage/v1/object/os-fotos/$OSFOTO_FOREIGN_OS/teste/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'
req "diretoria upload os-fotos -- esperado bloqueado (nao esta na lista de perfis autorizados)" POST "$TOK_DIR" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/dir/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'
req "encarregado upload os-fotos -- esperado PERMITIDO" POST "$TOK_ENC" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'
req "inativo upload os-fotos -- esperado bloqueado" POST "$TOK_INATIVO" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/inativo/$TS.jpg" "image/jpeg" $'\xff\xd8\xff\xe0fake'

echo
echo "############### READ — os-fotos ###############"
req "anon le os-fotos -- esperado bloqueado" GET "" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/teste/$TS.jpg"
req "executor le a propria foto -- esperado PERMITIDO" GET "$TOK_EXE" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/teste/$TS.jpg"
req "diretoria le foto de OS (nao fez upload, so leitura) -- esperado PERMITIDO (select autenticado+ativo, sem restricao de perfil)" GET "$TOK_DIR" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg"
req "inativo le os-fotos -- esperado bloqueado" GET "$TOK_INATIVO" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg"
req "sem-perfil le os-fotos -- esperado bloqueado" GET "$TOK_SEMPERFIL" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg"
req "arquivo inexistente os-fotos -- esperado 404" GET "$TOK_ENC" "$URL/storage/v1/object/os-fotos/00000000-0000-0000-0000-000000000000/x/nao-existe.jpg"

echo
echo "############### DELETE — os-fotos (esperado bloqueado para TODOS) ###############"
req "encarregado (dono do upload) tenta apagar foto -- esperado bloqueado" DELETE "$TOK_ENC" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg"
req "admin tenta apagar foto -- esperado bloqueado" DELETE "$TOK_ADM" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/enc/$TS.jpg"

echo
echo "############### MIME e tamanho -- validados pela RPC rpc_registrar_foto_os (nao pelo Storage bruto), ja cobertos em EXE-007/etapa6_complementos_exe007_doc002.sh -- aqui so confirma que o Storage aceita o upload bruto (validacao de negocio fica na RPC de registro) ###############"
req "upload MIME nao tipico (text/plain) direto no Storage -- Storage por si so nao bloqueia extensao/MIME de negocio" POST "$TOK_ENC" "$URL/storage/v1/object/os-fotos/$OSFOTO_OWNED_OS/mime/$TS.txt" "text/plain" "isto nao e uma imagem"
