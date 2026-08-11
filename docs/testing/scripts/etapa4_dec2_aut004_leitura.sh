#!/usr/bin/env bash
# ETAPA 4 (P1-A) — Decisão de negócio #2: usuário inativo = bloqueio TOTAL
# (não só RPC de escrita, também leitura de todas as áreas protegidas).
# Reproduz ANTES teria passado (leitura liberada) e confirma DEPOIS bloqueia.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_INATIVO=$(login "teste.inativo@qa.local")
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")

call() {
  local label="$1" token="$2" url="$3"
  echo; echo "--- $label ---"
  resp=$(curl -s -w '\n%{http_code}' "$url" -H "apikey: $ANON" -H "Authorization: Bearer $token")
  code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  echo "HTTP $code"
  echo "$body"
}

echo "############################################"
echo "# INATIVO (teste.inativo, ativo=false) deve ser BLOQUEADO em TODAS as áreas"
echo "############################################"
call "INATIVO le clientes" "$TOK_INATIVO" "$URL/rest/v1/clientes?select=id,nome&limit=3"
call "INATIVO le veiculos" "$TOK_INATIVO" "$URL/rest/v1/veiculos?select=id,placa&limit=3"
call "INATIVO le orcamentos" "$TOK_INATIVO" "$URL/rest/v1/orcamentos?select=id,status&limit=3"
call "INATIVO le ordens_servico" "$TOK_INATIVO" "$URL/rest/v1/ordens_servico?select=id,status&limit=3"
call "INATIVO le pecas (estoque)" "$TOK_INATIVO" "$URL/rest/v1/pecas?select=id,sku&limit=3"
call "INATIVO le estoque_movimentos" "$TOK_INATIVO" "$URL/rest/v1/estoque_movimentos?select=id&limit=3"
call "INATIVO le cobrancas (financeiro)" "$TOK_INATIVO" "$URL/rest/v1/cobrancas?select=id&limit=3"
call "INATIVO le proprio profile" "$TOK_INATIVO" "$URL/rest/v1/profiles?select=id,nome,ativo&limit=3"
call "INATIVO tenta inserir cliente (escrita)" "$TOK_INATIVO" "$URL/rest/v1/clientes?select=id"
echo "--- INATIVO tenta inserir cliente (POST real) ---"
resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/rest/v1/clientes" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_INATIVO" -H "Content-Type: application/json" -H "Prefer: return=representation" -d '{"tipo":"externo","nome":"TESTE_NAO_DEVE_CRIAR_INATIVO"}')
echo "HTTP $(echo "$resp" | tail -n1)"
echo "$resp" | sed '\$d'

echo
echo "############################################"
echo "# CONTROLE: EXECUTOR ativo continua lendo normalmente (não pode virar bloqueio geral por engano)"
echo "############################################"
call "EXECUTOR (ativo) le ordens_servico" "$TOK_EXECUTOR" "$URL/rest/v1/ordens_servico?select=id,status&limit=3"
call "EXECUTOR (ativo) le clientes" "$TOK_EXECUTOR" "$URL/rest/v1/clientes?select=id,nome&limit=3"
call "ENCARREGADO (ativo) le orcamentos" "$TOK_ENCARREGADO" "$URL/rest/v1/orcamentos?select=id,status&limit=3"

echo
echo "=== FIM — esperado: todas as chamadas de INATIVO retornam HTTP 200 com corpo [] (RLS filtra sem erro de rede, mas 0 linhas / insert bloqueado com erro); EXECUTOR/ENCARREGADO continuam com dados normais ==="
