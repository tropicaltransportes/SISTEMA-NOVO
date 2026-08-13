#!/usr/bin/env bash
# ETAPA PROD-01 — versão de PRODUÇÃO do safe_anon_rpc_checks.sh (DEV/QA).
# Mesma suíte não-destrutiva, mesmos UUIDs falsos, mesma lógica de segurança
# (todo RPC de escrita testado faz "select ... for update" ou validação de
# payload ANTES de qualquer gravação — com ID falso, a exceção de "não
# encontrado"/validação dispara antes de tocar em qualquer linha real).
#
# Aponta para o projeto de PRODUÇÃO (wtxbodhqyasdlmyoyjur, "SISTEMA NOVO -
# PROD"). A ANON_KEY não é secreta (fica embutida em qualquer build do
# frontend) — pode estar neste script versionado.
#
# Uso: bash safe_anon_rpc_checks_prod.sh
set -euo pipefail

URL="https://wtxbodhqyasdlmyoyjur.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0eGJvZGhxeWFzZGxteW95anVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NjQ3MTcsImV4cCI6MjEwMjE0MDcxN30.obctUQURNMloHmUJ6gREKOGvnpK9J2CylmPBw4kLBUk"
FAKE="00000000-0000-0000-0000-000000000000"

call() {
  local name="$1" fn="$2" body="$3"
  echo
  echo "--- $name (RPC: $fn) ---"
  curl -s -o /tmp/_check_prod.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $ANON" -H "Content-Type: application/json" -d "$body"
  cat /tmp/_check_prod.json
}

echo "=== PRODUÇÃO — Checagem de bypass de permissão (chamador anônimo, sem login) ==="
echo "Esperado seguro: 'Perfil sem permissão...' em toda RPC de escrita."
echo "Achado crítico: qualquer mensagem de negócio (ex: '... não encontrado')"
echo "significa que o check de permissão foi pulado."

echo
echo "--- SELECT profiles (esperado: [] vazio, RLS bloqueia anon) ---"
curl -s -o /tmp/_check_prod.json -w "HTTP %{http_code}\n" "$URL/rest/v1/profiles?select=id,nome,perfil&limit=5" -H "apikey: $ANON"; cat /tmp/_check_prod.json

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
call "rpc_registrar_termo_ciencia" "rpc_registrar_termo_ciencia" "{\"p_cobranca_id\":\"$FAKE\",\"p_arquivo_path\":\"x\",\"p_responsavel_nome\":\"x\"}"
call "rpc_cancelar_cobranca" "rpc_cancelar_cobranca" "{\"p_cobranca_id\":\"$FAKE\"}"
call "rpc_confirmar_nf_entrada" "rpc_confirmar_nf_entrada" "{\"p_nf_id\":\"$FAKE\"}"
call "rpc_estornar_nf_entrada" "rpc_estornar_nf_entrada" "{\"p_nf_id\":\"$FAKE\"}"
call "rpc_criar_venda_avulsa (itens vazio, evita insert)" "rpc_criar_venda_avulsa" "{\"p_cliente_id\":\"$FAKE\",\"p_itens\":[]}"
call "rpc_definir_custo_hora" "rpc_definir_custo_hora" "{\"p_valor_hora\":999}"
call "rpc_definir_teto_desconto" "rpc_definir_teto_desconto" "{\"p_habilitado\":true,\"p_percentual_maximo\":99}"
call "rpc_definir_anexos_config" "rpc_definir_anexos_config" "{\"p_tamanho_maximo_bytes\":1,\"p_mime_permitidos\":[\"text/plain\"]}"
call "rpc_criar_centro_custo" "rpc_criar_centro_custo" "{\"p_nome\":\"ANON_TENTATIVA\"}"
call "rpc_status_configuracao_sistema (leitura restrita)" "rpc_status_configuracao_sistema" "{}"

echo
echo "--- [SEGURANÇA] rpc_registrar_saida_estoque, peça FAKE (sem check de perfil próprio, REVOKE) ---"
curl -s -o /tmp/_check_prod.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_registrar_saida_estoque" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"p_peca_id\":\"$FAKE\",\"p_quantidade\":1,\"p_origem_tipo\":\"os\",\"p_origem_id\":\"$FAKE\"}"
cat /tmp/_check_prod.json

echo
echo "--- [SEGURANÇA] rpc_registrar_entrada_estoque, peça FAKE (sem check de perfil próprio, REVOKE) ---"
curl -s -o /tmp/_check_prod.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_registrar_entrada_estoque" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"p_peca_id\":\"$FAKE\",\"p_quantidade\":1,\"p_custo_unitario\":1,\"p_origem_tipo\":\"os\",\"p_origem_id\":\"$FAKE\"}"
cat /tmp/_check_prod.json

echo
echo "--- Autorização inválida: Bearer JWT malformado numa RPC protegida (esperado: 401) ---"
curl -s -o /tmp/_check_prod.json -w "HTTP %{http_code}\n" -X POST "$URL/rest/v1/rpc/rpc_liberar_os" \
  -H "apikey: $ANON" -H "Authorization: Bearer token.invalido.aqui" -H "Content-Type: application/json" \
  -d "{\"p_os_id\":\"$FAKE\"}"
cat /tmp/_check_prod.json

echo
echo "=== FIM ==="
