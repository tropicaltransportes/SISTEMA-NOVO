#!/usr/bin/env bash
# Retry via curl (mais confiavel neste ambiente que urllib.Python) dos 14
# RPCs que deram timeout de rede no enumerador python -- nao sao bypass,
# sao timeout de conexao. Confirma bloqueio real com curl.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
ZERO="00000000-0000-0000-0000-000000000000"

anon_call() {
  local name="$1" body="$2"
  echo; echo "--- $name ---"
  curl -s --max-time 15 -w '\nHTTP %{http_code}\n' -X POST "$URL/rest/v1/rpc/$name" \
    -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d "$body"
}

anon_call rpc_cancelar_cobranca "{\"p_cobranca_id\":\"$ZERO\"}"
anon_call rpc_cancelar_os_adicional "{\"p_adicional_id\":\"$ZERO\",\"p_motivo\":\"x\"}"
anon_call rpc_concluir_os "{\"p_os_id\":\"$ZERO\"}"
anon_call rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$ZERO\"}"
anon_call rpc_criar_os "{\"p_veiculo_id\":\"$ZERO\",\"p_tipo\":\"interna\"}"
anon_call rpc_criar_os_adicional "{\"p_os_id\":\"$ZERO\",\"p_motivo\":\"x\"}"
anon_call rpc_criar_os_garantia "{\"p_os_origem_id\":\"$ZERO\"}"
anon_call rpc_criar_venda_avulsa "{\"p_cliente_id\":\"$ZERO\",\"p_itens\":[]}"
anon_call rpc_criar_versao_orcamento "{\"p_orcamento_id\":\"$ZERO\"}"
anon_call rpc_liberar_os "{\"p_os_id\":\"$ZERO\"}"
anon_call rpc_marcar_item_orcamento_execucao "{\"p_orcamento_item_id\":\"$ZERO\",\"p_status\":\"executado\"}"
anon_call rpc_parcelar_cobranca "{\"p_cobranca_id\":\"$ZERO\",\"p_parcelas\":[]}"
anon_call rpc_registrar_acrescimo "{\"p_orcamento_id\":\"$ZERO\",\"p_valor_acrescimo\":1,\"p_justificativa\":\"x\"}"
anon_call rpc_registrar_ajuste_estoque "{\"p_peca_id\":\"$ZERO\",\"p_tipo\":\"x\",\"p_quantidade\":1,\"p_custo_unitario\":1,\"p_motivo\":\"x\"}"
