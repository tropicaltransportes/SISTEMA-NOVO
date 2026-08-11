#!/usr/bin/env bash
# ETAPA 4 — testes reais de autenticação/autorização por perfil, usando os
# usuários seedados em supabase/seed.sql (senha: Teste@2026!Qa).
# Ambiente autorizado como dev/teste descartável (ver docs/testing/TEST_REPORT_EXECUTION_02.md).
# Cada chamada é rotulada com o ID da matriz que ela evidencia.
set -uo pipefail

URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"

login() {
  local email="$1"
  curl -s -X POST "$URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$PASS\"}" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null
}

call_rpc() {
  local label="$1" token="$2" fn="$3" body="$4"
  echo
  echo "--- $label ---"
  if [ "$token" = "__ANON__" ]; then
    curl -s -o /tmp/_r.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/$fn" \
      -H "apikey: $ANON" -H "Content-Type: application/json" -d "$body"
    cat /tmp/_r.json
    return
  fi
  if [ -z "$token" ]; then
    echo "[ERRO DE TESTE: login falhou, sem token]"
    return
  fi
  curl -s -o /tmp/_r.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $ANON" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$body"
  cat /tmp/_r.json
}

call_get() {
  local label="$1" token="$2" path="$3"
  echo
  echo "--- $label ---"
  if [ -z "$token" ]; then
    echo "[ERRO DE TESTE: login falhou, sem token]"
    return
  fi
  curl -s -o /tmp/_r.json -w "HTTP %{http_code}\n" "$URL/rest/v1/$path" \
    -H "apikey: $ANON" -H "Authorization: Bearer $token"
  cat /tmp/_r.json
}

echo "=== ETAPA 4 — login de cada persona semeada ==="
TOK_EXECUTOR=$(login "teste.executor@qa.local")
TOK_ENCARREGADO=$(login "teste.encarregado@qa.local")
TOK_SUPORTE=$(login "teste.suporte@qa.local")
TOK_ADMIN=$(login "teste.admin@qa.local")
TOK_DIRETORIA=$(login "teste.diretoria@qa.local")
TOK_INATIVO=$(login "teste.inativo@qa.local")
TOK_SEMPERFIL=$(login "teste.semperfil@qa.local")
for p in EXECUTOR ENCARREGADO SUPORTE ADMIN DIRETORIA INATIVO SEMPERFIL; do
  var="TOK_$p"
  if [ -n "${!var}" ]; then echo "$p: login OK"; else echo "$p: LOGIN FALHOU"; fi
done
echo "AUT-004 (usuário inativo): login acima de INATIVO 'OK' já é evidência — Supabase Auth não checa profiles.ativo."
echo "'Autenticado sem profile' (SEMPERFIL): login OK também esperado — Auth não depende de profiles."

echo
echo "=== APR-001 / APR-007 — aprovar orçamento e0000000-...-0002 (enviado) ==="
call_rpc "ANON tenta aprovar (AUT-005, alvo real)" "__ANON__" rpc_aprovar_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002"}'
call_rpc "SEM_PROFILE tenta aprovar (regressão do bug NULL — sessão válida, sem perfil)" "$TOK_SEMPERFIL" rpc_aprovar_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002"}'
call_rpc "EXECUTOR tenta aprovar (APR-007/EXE-009 — esperado: bloqueado)" "$TOK_EXECUTOR" rpc_aprovar_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002"}'
echo "(pré-condição p/ cliente externo: registrar autorização do cliente antes de aprovar)"
call_rpc "SUPORTE registra autorização do cliente em e...0002" "$TOK_SUPORTE" rpc_registrar_autorizacao_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002","p_autorizado_por_nome":"TESTE_Responsavel_Cliente","p_comprovante_path":"comprovantes/pgtap-autorizacao-0002.pdf"}'
call_rpc "ENCARREGADO aprova de verdade (APR-001 — esperado: sucesso, muda estado real)" "$TOK_ENCARREGADO" rpc_aprovar_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002"}'
call_rpc "ENCARREGADO tenta aprovar de novo (APR-012 — esperado: bloqueado, já aprovado)" "$TOK_ENCARREGADO" rpc_aprovar_orcamento '{"p_orcamento_id":"e0000000-0000-0000-0000-000000000002"}'

echo
echo "=== OS-001/PER-001 — criar OS ==="
call_rpc "EXECUTOR tenta criar OS (PER-001/EXE-008 espírito — esperado: bloqueado)" "$TOK_EXECUTOR" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
call_rpc "SUPORTE tenta criar OS (esperado: bloqueado — não está na lista)" "$TOK_SUPORTE" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
call_rpc "DIRETORIA tenta criar OS (esperado: bloqueado, só leitura)" "$TOK_DIRETORIA" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'
call_rpc "ADMIN cria OS de verdade (OS-001 — esperado: sucesso)" "$TOK_ADMIN" rpc_criar_os '{"p_veiculo_id":"c0000000-0000-0000-0000-000000000002","p_tipo":"interna"}'

echo
echo "=== LIB-004/005/006 — liberar OS f...0004 (concluída, sem cobrança ainda) ==="
call_rpc "EXECUTOR tenta liberar (LIB-004 — esperado: bloqueado por perfil)" "$TOK_EXECUTOR" rpc_liberar_os '{"p_os_id":"f0000000-0000-0000-0000-000000000004"}'
call_rpc "DIRETORIA tenta liberar (PER-004 — esperado: bloqueado por perfil)" "$TOK_DIRETORIA" rpc_liberar_os '{"p_os_id":"f0000000-0000-0000-0000-000000000004"}'
call_rpc "SUPORTE tenta liberar (LIB-006/P0-06 — esperado: passa do check de perfil, bloqueado por falta de cobrança)" "$TOK_SUPORTE" rpc_liberar_os '{"p_os_id":"f0000000-0000-0000-0000-000000000004"}'
call_rpc "ENCARREGADO tenta liberar (LIB-005 — esperado: passa do check de perfil, bloqueado por falta de cobrança)" "$TOK_ENCARREGADO" rpc_liberar_os '{"p_os_id":"f0000000-0000-0000-0000-000000000004"}'

echo
echo "=== E2E-005 / LIB-003 — OS f...0005 (concluída, cliente INADIMPLENTE, sem cobrança/termo) ==="
call_rpc "ADMIN tenta liberar sem cobrança nem termo (LIB-003/E2E-005 — esperado: bloqueado por condição financeira)" "$TOK_ADMIN" rpc_liberar_os '{"p_os_id":"f0000000-0000-0000-0000-000000000005"}'

echo
echo "=== Financeiro — permissões de rpc_criar_cobranca ==="
call_rpc "ENCARREGADO tenta gerar cobrança (esperado: bloqueado — não está na lista)" "$TOK_ENCARREGADO" rpc_criar_cobranca '{"p_cliente_id":"b0000000-0000-0000-0000-000000000001","p_os_ids":["f0000000-0000-0000-0000-000000000004"],"p_venda_ids":null}'
call_get "EXECUTOR SELECT cobrancas (esperado: [] vazio — RLS current_perfil()<>'executor')" "$TOK_EXECUTOR" "cobrancas?select=id,valor_total"
call_get "DIRETORIA SELECT cobrancas (esperado: retorna linhas — diretoria tem leitura financeira)" "$TOK_DIRETORIA" "cobrancas?select=id,valor_total&limit=5"
call_rpc "SUPORTE gera cobrança de verdade sobre f...0004 (fluxo real p/ ETAPA 7)" "$TOK_SUPORTE" rpc_criar_cobranca '{"p_cliente_id":"b0000000-0000-0000-0000-000000000001","p_os_ids":["f0000000-0000-0000-0000-000000000004"],"p_venda_ids":null}'

echo
echo "=== Estoque — baixa por executor (ação permitida) ==="
call_rpc "EXECUTOR baixa peça d...0001 na OS f...0002 (em_execucao) — ação permitida ao executor, esperado sucesso" "$TOK_EXECUTOR" rpc_baixar_peca_os '{"p_os_id":"f0000000-0000-0000-0000-000000000002","p_peca_id":"d0000000-0000-0000-0000-000000000001","p_quantidade":1}'

echo
echo "=== AUT-004 real: usuário INATIVO consegue executar ação de executor mesmo assim? ==="
call_rpc "INATIVO (ativo=false) tenta apontar/baixar peça (esperado hoje: SUCESSO — AUT-004 não estava no escopo P0, achado permanece)" "$TOK_INATIVO" rpc_baixar_peca_os '{"p_os_id":"f0000000-0000-0000-0000-000000000002","p_peca_id":"d0000000-0000-0000-0000-000000000001","p_quantidade":1}'

echo
echo "=== FIM ETAPA 4 ==="
