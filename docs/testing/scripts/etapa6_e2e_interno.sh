#!/usr/bin/env bash
# ETAPA 6 (P1-C) — item 16: E2E cliente interno / custo interno.
# cliente interno -> veiculo da frota -> OS interna -> 2 executores -> 3h
# apontadas -> custo/hora configurado -> pecas utilizadas -> adicional
# tecnico -> checklist -> fotos conforme configuracao -> conclusao -> custo
# interno calculado -> relatorio de encerramento. Confirma: NENHUMA cobranca
# criada.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
TOK_EXE2=$(login "teste.executor2.p1c@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")
ENC_ID="a0000000-0000-0000-0000-000000000002"
EXE_ID="a0000000-0000-0000-0000-000000000001"
EXE2_ID="a0000000-0000-0000-0000-0000000000f2"
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
tbl_patch() { call "$1" PATCH "$2" "$URL/rest/v1/$3" "$4"; }
tbl_get() { call "$1" GET "$2" "$URL/rest/v1/$3"; }
jf() { echo "$BODY" | python -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit()
$1"; }
rawid() { echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '\"'; }

echo "############################################"
echo "# SETUP: custo/hora = R\$40,00, cliente interno _p1c, veiculo da frota, peca, checklist COM foto obrigatoria"
echo "############################################"
rpc "ADMIN define custo/hora = 40.00" "$TOK_ADM" rpc_definir_custo_hora '{"p_valor_hora":40.00}'
rpc "ADMIN define teto de desconto 15% (bootstrap ja existia 10%, so confirma reconfiguracao)" "$TOK_ADM" rpc_definir_teto_desconto '{"p_habilitado":true,"p_percentual_maximo":15}'

tbl_post "cria cliente INTERNO _p1c" "$TOK_SUP" "clientes" \
  '{"tipo":"interno","nome":"TESTE_P1C_Cliente_Interno","telefone":"(11) 90000-9001"}'
CLIENTE_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "cria veiculo da frota _p1c" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLIENTE_ID\",\"placa\":\"P1C$TS\",\"modelo\":\"TESTE_P1C_Frota\"}"
VEICULO_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLIENTE_ID=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"

rpc "ENCARREGADO cria centro de custo _p1c" "$TOK_ENC" rpc_criar_centro_custo "{\"p_nome\":\"TESTE_P1C_Centro_Custo_Manutencao_$TS\"}"
CENTRO=$(rawid)

tbl_post "peca interna _p1c (custo real R\$25)" "$TOK_SUP" "pecas" \
  "{\"sku\":\"QA_PECA_P1C_INT_$TS\",\"descricao\":\"TESTE_P1C_Peca_Interna\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":25.00,\"estoque_minimo\":1}"
PECA_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "NF rascunho _p1c" "$TOK_SUP" "notas_fiscais_entrada" \
  "{\"numero\":\"NF-P1C-INT-$TS\",\"fornecedor\":\"TESTE_Fornecedor_P1C\",\"status\":\"rascunho\",\"data_emissao\":\"2026-08-14\",\"criado_por\":\"a0000000-0000-0000-0000-000000000003\"}"
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item NF peca interna (10un a R\$25)" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_ID\",\"quantidade\":10,\"valor_unitario\":25.00}"
rpc "confirma NF" "$TOK_SUP" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

tbl_post "checklist template _p1c COM foto antes E depois obrigatorias" "$TOK_ENC" "checklist_templates" \
  '{"nome":"TESTE_P1C_Checklist_Interno","ativo":true}'
CHK_TPL=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item obrigatorio do checklist" "$TOK_ENC" "checklist_template_itens" "{\"template_id\":\"$CHK_TPL\",\"descricao\":\"TESTE Verificacao geral\",\"obrigatorio\":true}"
CHK_ITEM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "ENCARREGADO define foto antes E depois OBRIGATORIAS neste checklist" "$TOK_ENC" rpc_definir_obrigatoriedade_fotos \
  "{\"p_template_id\":\"$CHK_TPL\",\"p_foto_antes_obrigatoria\":true,\"p_foto_depois_obrigatoria\":true}"

echo
echo "############################################"
echo "# OS INTERNA direto (sem orcamento -- cliente interno nao gera orcamento comercial)"
echo "############################################"
rpc "ENCARREGADO cria OS interna" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO_ID\",\"p_tipo\":\"interna\",\"p_checklist_template_id\":\"$CHK_TPL\"}"
OS=$(rawid)
echo "OS=$OS"
rpc "ENCARREGADO define centro de custo da OS" "$TOK_ENC" rpc_definir_centro_custo_os "{\"p_os_id\":\"$OS\",\"p_centro_custo_id\":\"$CENTRO\"}"
rpc "ENCARREGADO define previsao de conclusao" "$TOK_ENC" rpc_definir_previsao_conclusao "{\"p_os_id\":\"$OS\",\"p_previsao_conclusao\":\"2026-08-16T18:00:00Z\"}"
rpc "transiciona aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "transiciona em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# 2 EXECUTORES, total 3 horas apontadas (2h + 1h) -- custo mao de obra esperado 3 x 40 = 120.00"
echo "############################################"
tbl_post "EXECUTOR 1 aponta 2h (10:00-12:00)" "$TOK_EXE" "os_executores" \
  "{\"os_id\":\"$OS\",\"usuario_id\":\"$EXE_ID\",\"etapa\":\"execucao\",\"inicio\":\"2026-08-14T10:00:00Z\",\"fim\":\"2026-08-14T12:00:00Z\",\"observacao\":\"TESTE P1C exec1\"}"
tbl_post "EXECUTOR 2 aponta 1h (10:00-11:00)" "$TOK_EXE2" "os_executores" \
  "{\"os_id\":\"$OS\",\"usuario_id\":\"$EXE2_ID\",\"etapa\":\"execucao\",\"inicio\":\"2026-08-14T10:00:00Z\",\"fim\":\"2026-08-14T11:00:00Z\",\"observacao\":\"TESTE P1C exec2\"}"
tbl_get "apontamentos da OS (esperado soma 3h)" "$TOK_ENC" "os_executores?os_id=eq.$OS&select=usuario_id,inicio,fim,ativo"

echo
echo "############################################"
echo "# item 8 (EXE-003): remove formalmente executor 2 DEPOIS do apontamento -- historico deve permanecer"
echo "############################################"
tbl_get "id do vinculo do executor2" "$TOK_ENC" "os_executores?os_id=eq.$OS&usuario_id=eq.$EXE2_ID&select=id"
EXEC2_VINCULO=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "ENCARREGADO remove formalmente executor2 (motivo)" "$TOK_ENC" rpc_remover_executor_os \
  "{\"p_os_executor_id\":\"$EXEC2_VINCULO\",\"p_motivo\":\"TESTE P1C: encerrando participacao do executor2 nesta OS, tarefa concluida\"}"
tbl_get "vinculo do executor2 apos remocao (esperado ativo=false, inicio/fim preservados)" "$TOK_ENC" "os_executores?id=eq.$EXEC2_VINCULO&select=ativo,inicio,fim,removido_por,motivo_remocao"

echo
echo "############################################"
echo "# Baixa de peca (venda avulsa NAO -- baixa direta via peca fora de orcamento nao existe nesta OS; interna sem orcamento usa fluxo de ADICIONAL para peca precificada=0/custo)"
echo "# Para OS interna sem orcamento, o fluxo de consumo de peca formal e via Adicional tecnico (ADC), com valor_unitario = custo (nao ha faturamento, mas o valor serve de referencia de custo)"
echo "############################################"
rpc "EXECUTOR identifica necessidade de peca (adicional tecnico)" "$TOK_EXE" rpc_criar_os_adicional \
  "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE P1C: necessidade de peca identificada durante manutencao interna\"}"
ADIC=$(rawid)
rpc "ENCARREGADO inclui item do adicional (peca, custo real 25.00, 2un)" "$TOK_ENC" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":\"$PECA_ID\",\"p_descricao\":\"TESTE P1C peca interna consumida\",\"p_quantidade\":2,\"p_valor_unitario\":25.00,\"p_justificativa\":\"Custo de referencia (OS interna nao fatura)\"}"
ITEM_AD=$(rawid)
rpc "ENCARREGADO decide (aprova) o item, meio sistema" "$TOK_ENC" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Encarregado (OS interna, sem cliente externo para autorizar)\"}"
rpc "EXECUTOR baixa 2un da peca (item de adicional aprovado)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_ID\",\"p_quantidade\":2,\"p_os_adicional_item_id\":\"$ITEM_AD\"}"
tbl_get "execucao_status do item de adicional (esperado executado)" "$TOK_ENC" "os_adicional_itens?id=eq.$ITEM_AD&select=execucao_status,valor_total"

echo
echo "############################################"
echo "# Fotos: checklist exige antes E depois -- tenta concluir SEM foto (deve BLOQUEAR), sobe foto antes, tenta de novo (ainda bloqueia por falta de depois), sobe depois, conclui"
echo "############################################"
rpc "responde item obrigatorio do checklist" "$TOK_ENC" rpc_marcar_item_os_adicional_execucao "{\"p_item_id\":\"$ITEM_AD\",\"p_status\":\"executado\"}"
tbl_post "responde checklist (ok=true)" "$TOK_ENC" "os_checklist_respostas" \
  "{\"os_id\":\"$OS\",\"template_item_id\":\"$CHK_ITEM\",\"ok\":true,\"respondido_por\":\"$ENC_ID\",\"respondido_em\":\"2026-08-14T12:30:00Z\"}"
rpc "transiciona em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"

rpc "tenta CONCLUIR sem nenhuma foto -- deve BLOQUEAR (foto antes obrigatoria)" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo "--- upload foto ANTES no bucket os-fotos ---"
FOTO_ANTES_PATH="$OS/antes/$(date +%s)-antes.jpg"
curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/storage/v1/object/os-fotos/$FOTO_ANTES_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXE" -H "Content-Type: image/jpeg" \
  --data-binary $'\xff\xd8\xff\xe0TESTE_P1C_FOTO_ANTES_JPEG_FAKE_BYTES'
rpc "EXECUTOR registra foto ANTES" "$TOK_EXE" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"antes\",\"p_arquivo_path\":\"$FOTO_ANTES_PATH\",\"p_observacao\":\"TESTE P1C foto antes\"}"

rpc "tenta CONCLUIR so com foto antes -- deve BLOQUEAR (falta foto depois)" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo "--- upload foto DEPOIS no bucket os-fotos ---"
FOTO_DEPOIS_PATH="$OS/depois/$(date +%s)-depois.jpg"
curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/storage/v1/object/os-fotos/$FOTO_DEPOIS_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_EXE" -H "Content-Type: image/jpeg" \
  --data-binary $'\xff\xd8\xff\xe0TESTE_P1C_FOTO_DEPOIS_JPEG_FAKE_BYTES'
rpc "EXECUTOR registra foto DEPOIS" "$TOK_EXE" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"depois\",\"p_arquivo_path\":\"$FOTO_DEPOIS_PATH\",\"p_observacao\":\"TESTE P1C foto depois\"}"

echo
echo "############################################"
echo "# tentativa de vincular foto de OUTRA OS -- deve BLOQUEAR (path fora da pasta desta OS)"
echo "############################################"
rpc "tenta registrar foto com path de outra OS -- deve falhar" "$TOK_EXE" rpc_registrar_foto_os \
  "{\"p_os_id\":\"$OS\",\"p_tipo\":\"outro\",\"p_arquivo_path\":\"00000000-0000-0000-0000-000000000000/outro/fake.jpg\",\"p_observacao\":\"TESTE deve bloquear\"}"

echo
echo "############################################"
echo "# CONCLUI a OS (fotos antes+depois presentes, checklist ok, item de adicional executado)"
echo "############################################"
rpc "CONCLUI a OS interna" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"
tbl_get "status da OS + custo calculado" "$TOK_ENC" "ordens_servico?id=eq.$OS&select=status,custo_pecas,custo_mao_obra,custo_total,custo_hora_aplicado,horas_apontadas_total,custo_calculado_em"

echo
echo "############################################"
echo "# CONFIRMA: NENHUMA cobranca foi criada para esta OS (interna nunca fatura)"
echo "############################################"
tbl_get "tenta achar cobranca vinculada a esta OS (esperado vazio)" "$TOK_SUP" "cobranca_origens?os_id=eq.$OS&select=id"
rpc "tenta CRIAR cobranca para OS interna -- deve BLOQUEAR (so externa)" "$TOK_SUP" rpc_criar_cobranca "{\"p_cliente_id\":\"$CLIENTE_ID\",\"p_os_ids\":[\"$OS\"],\"p_venda_ids\":null}"

echo
echo "############################################"
echo "# item 4: relatorio de encerramento"
echo "############################################"
rpc "relatorio de encerramento da OS interna" "$TOK_ENC" rpc_relatorio_encerramento_os "{\"p_os_id\":\"$OS\"}"

echo
echo "############################################"
echo "# item 7: historico do veiculo"
echo "############################################"
rpc "historico do veiculo da frota" "$TOK_ENC" rpc_historico_veiculo "{\"p_veiculo_id\":\"$VEICULO_ID\"}"

echo
echo "############################################"
echo "# RESUMO FINAL E2E INTERNO"
echo "############################################"
echo "OS=$OS CLIENTE_ID(interno)=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"
echo "ESPERADO: custo_pecas=50.00 (2un x 25.00), custo_mao_obra=120.00 (3h x 40.00), custo_total=170.00"
echo "ESPERADO: nenhuma cobranca criada, nenhum registro em cobranca_origens para esta OS"
echo "=== FIM E2E INTERNO ==="
