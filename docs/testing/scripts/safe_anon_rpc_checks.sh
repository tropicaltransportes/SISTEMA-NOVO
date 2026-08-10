#!/usr/bin/env bash
# Suíte de checagem NÃO DESTRUTIVA — roda como papel "anon" (sem login algum),
# só com a chave pública (anon key, já embutida em qualquer build do frontend,
# não é segredo). Todas as chamadas usam UUIDs falsos (00000000-...-000000000000)
# e argumentos escolhidos para nunca alcançar um INSERT/UPDATE real:
#   - toda RPC de escrita aqui testada faz "select ... for update" ou uma
#     validação de payload (array vazio, item ausente) ANTES de qualquer
#     gravação; com ID falso, a exceção de "não encontrado" (ou de validação)
#     sempre dispara antes de tocar em qualquer linha real.
#   - a única exceção (rpc_registrar_ajuste_estoque / marcar_solicitacao_convertida)
#     está documentada inline abaixo.
#
# Por que isso existe: não há Docker disponível neste ambiente (logo, não dá
# pra rodar `supabase start` local) e o único projeto Supabase configurado é o
# projeto real de desenvolvimento (já usado por dados de clientes reais,
# mesmo que hoje só com dados de teste explicitamente marcados como tal).
# CLAUDE.md exige banco exclusivo de teste para testes destrutivos; como não
# existe um aqui, este script cobre apenas o subconjunto que é comprovadamente
# não-destrutivo mesmo rodando direto contra o projeto real — nenhuma
# credencial de usuário é usada ou necessária.
#
# Resultado obtido na auditoria de 2026-08-10 (ver docs/testing/TEST_REPORT.md):
# TODAS as RPCs de escrita testadas aqui pularam o próprio check de permissão
# (`if current_perfil() not in (...) then raise exception`) quando chamadas
# sem nenhuma sessão — porque current_perfil() retorna NULL para um chamador
# anônimo, e `NULL NOT IN (...)` avalia como NULL, que o `IF` do plpgsql trata
# como falso (não dispara a exceção). Achado crítico — ver relatório.
#
# Uso: bash safe_anon_rpc_checks.sh
set -euo pipefail

URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
FAKE="00000000-0000-0000-0000-000000000000"

call() {
  local name="$1" fn="$2" body="$3"
  echo
  echo "--- $name (RPC: $fn) ---"
  curl -s -o /tmp/_check.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $ANON" -H "Content-Type: application/json" -d "$body"
  cat /tmp/_check.json
}

echo "=== Checagem de bypass de permissão (chamador anônimo, sem login) ==="
echo "Esperado seguro: 'Perfil sem permissão...' em toda RPC de escrita."
echo "Achado crítico: qualquer mensagem de negócio (ex: '... não encontrado')"
echo "significa que o check de permissão foi pulado."

echo
echo "--- SELECT profiles (esperado: [] vazio) ---"
curl -s -o /tmp/_check.json -w "HTTP %{http_code}\n" "$URL/rest/v1/profiles?select=id,nome,perfil&limit=5" -H "apikey: $ANON"; cat /tmp/_check.json

call "rpc_criar_os" "rpc_criar_os" "{\"p_veiculo_id\":\"$FAKE\",\"p_tipo\":\"interna\"}"
call "rpc_enviar_orcamento" "rpc_enviar_orcamento" "{\"p_orcamento_id\":\"$FAKE\"}"
call "rpc_aprovar_orcamento" "rpc_aprovar_orcamento" "{\"p_orcamento_id\":\"$FAKE\"}"
call "rpc_rejeitar_orcamento" "rpc_rejeitar_orcamento" "{\"p_orcamento_id\":\"$FAKE\"}"
call "rpc_registrar_autorizacao_orcamento" "rpc_registrar_autorizacao_orcamento" "{\"p_orcamento_id\":\"$FAKE\",\"p_autorizado_por_nome\":\"x\",\"p_comprovante_path\":\"x\"}"
call "rpc_criar_versao_orcamento" "rpc_criar_versao_orcamento" "{\"p_orcamento_id\":\"$FAKE\"}"
call "rpc_registrar_acrescimo" "rpc_registrar_acrescimo" "{\"p_orcamento_id\":\"$FAKE\",\"p_valor_acrescimo\":1,\"p_justificativa\":\"teste\"}"
call "rpc_transicionar_os" "rpc_transicionar_os" "{\"p_os_id\":\"$FAKE\",\"p_novo_status\":\"em_diagnostico\"}"
call "rpc_concluir_os" "rpc_concluir_os" "{\"p_os_id\":\"$FAKE\"}"
call "rpc_liberar_os" "rpc_liberar_os" "{\"p_os_id\":\"$FAKE\"}"
call "rpc_criar_os_garantia" "rpc_criar_os_garantia" "{\"p_os_origem_id\":\"$FAKE\"}"
call "rpc_definir_checklist_os" "rpc_definir_checklist_os" "{\"p_os_id\":\"$FAKE\",\"p_checklist_template_id\":\"$FAKE\"}"
call "rpc_baixar_peca_os" "rpc_baixar_peca_os" "{\"p_os_id\":\"$FAKE\",\"p_peca_id\":\"$FAKE\",\"p_quantidade\":1}"
call "rpc_criar_cobranca (arrays vazios)" "rpc_criar_cobranca" "{\"p_cliente_id\":\"$FAKE\",\"p_os_ids\":[],\"p_venda_ids\":[]}"
call "rpc_parcelar_cobranca" "rpc_parcelar_cobranca" "{\"p_cobranca_id\":\"$FAKE\",\"p_parcelas\":[]}"
call "rpc_registrar_recebimento" "rpc_registrar_recebimento" "{\"p_parcela_id\":\"$FAKE\",\"p_valor_recebido\":1,\"p_forma_pagamento\":\"pix\",\"p_data_recebimento\":\"2020-01-01\"}"
call "rpc_registrar_termo_ciencia" "rpc_registrar_termo_ciencia" "{\"p_cobranca_id\":\"$FAKE\",\"p_arquivo_path\":\"x\"}"
call "rpc_cancelar_cobranca" "rpc_cancelar_cobranca" "{\"p_cobranca_id\":\"$FAKE\"}"
call "rpc_confirmar_nf_entrada" "rpc_confirmar_nf_entrada" "{\"p_nf_id\":\"$FAKE\"}"
call "rpc_estornar_nf_entrada" "rpc_estornar_nf_entrada" "{\"p_nf_id\":\"$FAKE\"}"
call "rpc_criar_venda_avulsa (itens vazio, evita insert)" "rpc_criar_venda_avulsa" "{\"p_cliente_id\":\"$FAKE\",\"p_itens\":[]}"

echo
echo "--- [SEGURANÇA] rpc_registrar_saida_estoque, peça FAKE (sem check de perfil próprio) ---"
curl -s -o /tmp/_check.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_registrar_saida_estoque" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"p_peca_id\":\"$FAKE\",\"p_quantidade\":1,\"p_origem_tipo\":\"os\",\"p_origem_id\":\"$FAKE\"}"
cat /tmp/_check.json

echo
echo "--- [SEGURANÇA] rpc_registrar_entrada_estoque, peça FAKE (sem check de perfil próprio) ---"
curl -s -o /tmp/_check.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_registrar_entrada_estoque" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"p_peca_id\":\"$FAKE\",\"p_quantidade\":1,\"p_custo_unitario\":1,\"p_origem_tipo\":\"os\",\"p_origem_id\":\"$FAKE\"}"
cat /tmp/_check.json

echo
echo "--- Autorização inválida: Bearer JWT malformado numa RPC protegida (esperado: 401) ---"
curl -s -o /tmp/_check.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_liberar_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer token.invalido.aqui" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$FAKE\"}"
cat /tmp/_check.json

echo
echo "=== FIM ==="
