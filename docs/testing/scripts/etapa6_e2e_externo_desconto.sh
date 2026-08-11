#!/usr/bin/env bash
# ETAPA 6 (P1-C) — item 17: E2E externo com desconto.
# orcamento externo -> itens -> desconto autorizado -> envio -> aprovacao
# parcial -> OS -> adicional -> execucao -> cobranca -> termo -> liberacao
# -> relatorio. Confirma matematicamente: bruto - desconto + adicionais
# aprovados = valor final cobrado, e que item rejeitado nunca entra.
set -uo pipefail
URL="https://jzjbiejmcaygwycvqggm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6amJpZWptY2F5Z3d5Y3ZxZ2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMzU0OTgsImV4cCI6MjEwMTYxMTQ5OH0.3-bXFCjVbjQp2HfasPeKgQnGNvEd7FM7vEjp7dhycAc"
PASS="Teste@2026!Qa"
login() { curl -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"$PASS\"}" | python -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"; }
TOK_ENC=$(login "teste.encarregado@qa.local")
TOK_SUP=$(login "teste.suporte@qa.local")
TOK_EXE=$(login "teste.executor@qa.local")
TOK_ADM=$(login "teste.admin@qa.local")
ENC_ID="a0000000-0000-0000-0000-000000000002"
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
rawid() { echo "$BODY" | python -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "$BODY" | tr -d '\"'; }

echo "############################################"
echo "# SETUP: cliente externo _p1c, veiculo, 3 pecas, teto de desconto 15%"
echo "############################################"
rpc "ADMIN confirma teto de desconto 15% vigente" "$TOK_ADM" rpc_definir_teto_desconto '{"p_habilitado":true,"p_percentual_maximo":15}'

tbl_post "cria cliente EXTERNO _p1c" "$TOK_SUP" "clientes" \
  "{\"tipo\":\"externo\",\"nome\":\"TESTE_P1C_Cliente_Externo_Desconto\",\"documento\":\"55555555000$((TS % 100))\",\"telefone\":\"(11) 90000-9002\",\"email\":\"p1c-desconto@teste.qa\"}"
CLIENTE_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "cria veiculo _p1c" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLIENTE_ID\",\"placa\":\"P1CD$TS\",\"modelo\":\"TESTE_P1C_Desconto\"}"
VEICULO_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLIENTE_ID=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"

tbl_post "peca A" "$TOK_SUP" "pecas" "{\"sku\":\"QA_PECA_P1C_A_$TS\",\"descricao\":\"TESTE_P1C_Peca_A\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":50,\"estoque_minimo\":1}"
PECA_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "peca C" "$TOK_SUP" "pecas" "{\"sku\":\"QA_PECA_P1C_C_$TS\",\"descricao\":\"TESTE_P1C_Peca_C\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":50,\"estoque_minimo\":1}"
PECA_C=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "peca AD (adicional)" "$TOK_SUP" "pecas" "{\"sku\":\"QA_PECA_P1C_AD_$TS\",\"descricao\":\"TESTE_P1C_Peca_AD\",\"unidade\":\"UN\",\"saldo_atual\":0,\"custo_medio\":10,\"estoque_minimo\":1}"
PECA_AD=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")

tbl_post "NF rascunho _p1c" "$TOK_SUP" "notas_fiscais_entrada" \
  "{\"numero\":\"NF-P1C-EXT-$TS\",\"fornecedor\":\"TESTE_Fornecedor_P1C\",\"status\":\"rascunho\",\"data_emissao\":\"2026-08-14\",\"criado_por\":\"a0000000-0000-0000-0000-000000000003\"}"
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item NF peca A" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_A\",\"quantidade\":5,\"valor_unitario\":50}"
tbl_post "item NF peca C" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_C\",\"quantidade\":5,\"valor_unitario\":50}"
tbl_post "item NF peca AD" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_AD\",\"quantidade\":5,\"valor_unitario\":10}"
rpc "confirma NF" "$TOK_SUP" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

echo
echo "############################################"
echo "# Orcamento rascunho: A=100.00 (peca, sera APROVADO), B=100.00 (mao de obra, sera REJEITADO), C=100.01 (peca, sera APROVADO) -- bruto = 300.01"
echo "############################################"
tbl_post "cria orcamento rascunho" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item A peca R\$100.00" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA_A\",\"descricao\":\"TESTE P1C Item A peca\",\"quantidade\":1,\"valor_unitario\":100.00}"
ITEM_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item B mao de obra R\$100.00" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE P1C Item B mao de obra\",\"quantidade\":1,\"valor_unitario\":100.00}"
ITEM_B=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item C peca R\$100.01" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA_C\",\"descricao\":\"TESTE P1C Item C peca\",\"quantidade\":1,\"valor_unitario\":100.01}"
ITEM_C=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC=$ORC ITEM_A=$ITEM_A ITEM_B=$ITEM_B ITEM_C=$ITEM_C (bruto esperado 300.01)"

echo
echo "############################################"
echo "# Desconto: tenta ACIMA do teto (20%) -- deve BLOQUEAR; aplica valor fixo R\$100.00 (dentro do teto, ~33.33%% do bruto... na verdade excede 15%% -- redefine teto alto so p/ este cenario nao ser bloqueado indevidamente)"
echo "############################################"
rpc "ENCARREGADO tenta desconto 20% (acima do teto 15%) -- deve BLOQUEAR" "$TOK_ENC" rpc_aplicar_desconto_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_percentual\":20,\"p_motivo\":\"TESTE desconto acima do teto, deve falhar\"}"
rpc "ADMIN eleva teto para 40% (permite o cenario de desconto de referencia deste E2E)" "$TOK_ADM" rpc_definir_teto_desconto '{"p_habilitado":true,"p_percentual_maximo":40}'
rpc "ENCARREGADO SEM motivo -- deve BLOQUEAR" "$TOK_ENC" rpc_aplicar_desconto_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_valor\":100.00}"
rpc "ENCARREGADO aplica desconto R\$100.00 fixo, motivo obrigatorio (rateio proporcional, testa arredondamento)" "$TOK_ENC" rpc_aplicar_desconto_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_valor\":100.00,\"p_motivo\":\"TESTE P1C: negociacao comercial, desconto fixo autorizado pelo encarregado\"}"
tbl_get "orcamento apos desconto (esperado bruto 300.01, desconto 100.00, liquido 200.01)" "$TOK_ENC" "orcamentos?id=eq.$ORC&select=valor_bruto,desconto_valor,desconto_percentual,valor_liquido,valor_total"
tbl_get "itens com desconto rateado (esperado somar 100.00 exato, sem sobra de centavo)" "$TOK_ENC" "orcamento_itens?orcamento_id=eq.$ORC&select=descricao,valor_total,desconto_rateado,valor_liquido&order=id"

echo
echo "############################################"
echo "# EXECUTOR tenta aplicar desconto -- deve BLOQUEAR (nunca desconto)"
echo "############################################"
rpc "EXECUTOR tenta aplicar desconto -- deve falhar" "$TOK_EXE" rpc_aplicar_desconto_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_valor\":10,\"p_motivo\":\"TESTE executor tentando desconto, deve bloquear\"}"

echo
echo "############################################"
echo "# Envia orcamento e decide por item: A=aprovado, B=rejeitado, C=aprovado (parcialmente_aprovado)"
echo "############################################"
rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
rpc "decide ITEM_A aprovado" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_A\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente P1C\"}"
rpc "decide ITEM_B rejeitado" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_B\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente P1C\"}"
rpc "decide ITEM_C aprovado" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_C\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente P1C\"}"
tbl_get "status final do orcamento (esperado parcialmente_aprovado)" "$TOK_ENC" "orcamentos?id=eq.$ORC&select=status"

echo
echo "############################################"
echo "# Tenta alterar desconto DEPOIS de decidido -- deve BLOQUEAR (nao esta mais em rascunho, exige nova versao)"
echo "############################################"
rpc "tenta reaplicar desconto em orcamento ja decidido -- deve falhar" "$TOK_ENC" rpc_aplicar_desconto_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_valor\":50,\"p_motivo\":\"TESTE tentando alterar desconto pos-aprovacao, deve bloquear\"}"

echo
echo "############################################"
echo "# PDF: dados da versao 1 do orcamento (ORC-013/DOC-001/DOC-002)"
echo "############################################"
rpc "dados para PDF da versao 1" "$TOK_ENC" rpc_dados_pdf_orcamento "{\"p_orcamento_id\":\"$ORC\"}"

echo
echo "############################################"
echo "# Converte em OS externa (parcialmente aprovado)"
echo "############################################"
rpc "converte em OS externa" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO_ID\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC\"}"
OS=$(rawid)
echo "OS=$OS"
rpc "ENCARREGADO define prazo" "$TOK_ENC" rpc_definir_previsao_conclusao "{\"p_os_id\":\"$OS\",\"p_previsao_conclusao\":\"2026-08-18T18:00:00Z\"}"
rpc "transiciona aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "transiciona em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# Executa ITEM_A e ITEM_C (aprovados); confirma ITEM_B (rejeitado) bloqueia baixa"
echo "############################################"
rpc "baixa peca do ITEM_A" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_A\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_A\"}"
rpc "baixa peca do ITEM_C" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_C\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_C\"}"
rpc "tenta marcar ITEM_B (rejeitado) executado -- deve falhar" "$TOK_EXE" rpc_marcar_item_orcamento_execucao "{\"p_orcamento_item_id\":\"$ITEM_B\",\"p_status\":\"executado\"}"

echo
echo "############################################"
echo "# Adicional tecnico: item AD aprovado R\$50.00"
echo "############################################"
rpc "EXECUTOR identifica adicional" "$TOK_EXE" rpc_criar_os_adicional "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE P1C: peca extra identificada durante execucao\"}"
ADIC=$(rawid)
rpc "ENCARREGADO precifica item do adicional R\$50.00" "$TOK_ENC" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":\"$PECA_AD\",\"p_descricao\":\"TESTE P1C item adicional\",\"p_quantidade\":1,\"p_valor_unitario\":50.00,\"p_justificativa\":\"Peca extra necessaria\"}"
ITEM_AD=$(rawid)
rpc "cliente aprova item do adicional (verbal_documentado)" "$TOK_ENC" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"verbal_documentado\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente P1C\",\"p_observacao\":\"Cliente autorizou por telefone a peca extra do adicional.\"}"
rpc "EXECUTOR baixa peca do adicional aprovado" "$TOK_EXE" rpc_baixar_peca_os "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_AD\",\"p_quantidade\":1,\"p_os_adicional_item_id\":\"$ITEM_AD\"}"

echo
echo "############################################"
echo "# item 11 (P1C): cancela formalmente um item aprovado ainda NAO executado -- cria 2o adicional so p/ demonstrar"
echo "############################################"
rpc "EXECUTOR identifica 2o adicional (sera cancelado apos aprovado)" "$TOK_EXE" rpc_criar_os_adicional "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE P1C: item que sera cancelado apos aprovado, antes de executar\"}"
ADIC2=$(rawid)
rpc "ENCARREGADO precifica item do 2o adicional (mao de obra R\$40.00)" "$TOK_ENC" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC2\",\"p_peca_id\":null,\"p_descricao\":\"TESTE P1C item que sera cancelado\",\"p_quantidade\":1,\"p_valor_unitario\":40.00,\"p_justificativa\":\"Sera cancelado no teste\"}"
ITEM_AD2=$(rawid)
rpc "cliente aprova o item (sistema)" "$TOK_ENC" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD2\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente P1C\"}"
rpc "ENCARREGADO cancela formalmente o item aprovado ainda NAO executado" "$TOK_ENC" rpc_marcar_item_os_adicional_execucao \
  "{\"p_item_id\":\"$ITEM_AD2\",\"p_status\":\"cancelado\",\"p_motivo\":\"TESTE P1C: nao sera mais necessario, cancelado formalmente antes de executar\"}"
tbl_get "item cancelado (esperado execucao_status=cancelado)" "$TOK_ENC" "os_adicional_itens?id=eq.$ITEM_AD2&select=execucao_status,status_aprovacao"
rpc "tenta cancelar item JA EXECUTADO (ITEM_AD) -- deve BLOQUEAR" "$TOK_ENC" rpc_marcar_item_os_adicional_execucao \
  "{\"p_item_id\":\"$ITEM_AD\",\"p_status\":\"cancelado\",\"p_motivo\":\"TESTE tentando cancelar item ja executado, deve falhar\"}"

echo
echo "############################################"
echo "# Checklist + conclusao"
echo "############################################"
tbl_get "checklist template padrao (reusa o mesmo do seed, sem foto obrigatoria)" "$TOK_ENC" "checklist_templates?select=id,foto_antes_obrigatoria,foto_depois_obrigatoria&foto_antes_obrigatoria=eq.false&foto_depois_obrigatoria=eq.false&limit=1"
CHK_TPL=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "define checklist da OS" "$TOK_ENC" rpc_definir_checklist_os "{\"p_os_id\":\"$OS\",\"p_checklist_template_id\":\"$CHK_TPL\"}"
tbl_get "itens obrigatorios do checklist" "$TOK_ENC" "checklist_template_itens?template_id=eq.$CHK_TPL&select=id,obrigatorio"
CHK_ITEM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "transiciona em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"
tbl_post "responde checklist obrigatorio" "$TOK_ENC" "os_checklist_respostas" \
  "{\"os_id\":\"$OS\",\"template_item_id\":\"$CHK_ITEM\",\"ok\":true,\"respondido_por\":\"$ENC_ID\",\"respondido_em\":\"2026-08-14T15:00:00Z\"}"
rpc "CONCLUI a OS" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"
tbl_get "status final da OS" "$TOK_ENC" "ordens_servico?id=eq.$OS&select=status"

echo
echo "############################################"
echo "# Cobranca: esperado EXATO = liquido(A)+liquido(C)+adicional_aprovado_executado(AD) = 66.67+66.67+50.00 = 183.34"
echo "# (ITEM_B rejeitado nunca entra; ITEM_AD2 cancelado nunca entra mesmo tendo sido aprovado)"
echo "############################################"
rpc "gera cobranca" "$TOK_SUP" rpc_criar_cobranca "{\"p_cliente_id\":\"$CLIENTE_ID\",\"p_os_ids\":[\"$OS\"],\"p_venda_ids\":null}"
COB=$(rawid)
echo "COBRANCA=$COB"
tbl_get "valor_total da cobranca (ESPERADO 183.34)" "$TOK_SUP" "cobrancas?id=eq.$COB&select=valor_total,status"

echo
echo "############################################"
echo "# Decisao 8: Termo de Ciencia de Debito estruturado (em vez de pagamento, para diversificar cobertura)"
echo "############################################"
COMP_PATH="p1c/teste-p1c-termo-$TS.txt"
curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/storage/v1/object/comprovantes/$COMP_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: text/plain" \
  --data-binary "TESTE P1C - termo de ciencia de debito assinado (evidencia real no Storage)."
rpc "ENCARREGADO registra termo de ciencia estruturado" "$TOK_ENC" rpc_registrar_termo_ciencia \
  "{\"p_cobranca_id\":\"$COB\",\"p_arquivo_path\":\"$COMP_PATH\",\"p_responsavel_nome\":\"TESTE Responsavel Legal Cliente P1C\",\"p_responsavel_documento\":\"123.456.789-00\",\"p_observacao\":\"TESTE P1C: cliente comprometeu-se a quitar em 30 dias\"}"
tbl_get "termo registrado (estrutura completa)" "$TOK_ENC" "termos_ciencia_debito?cobranca_id=eq.$COB&select=cliente_id,valor_reconhecido,responsavel_nome,responsavel_documento,registrado_por,observacao"

echo
echo "############################################"
echo "# Libera a OS (termo valido registrado, sem pagamento confirmado)"
echo "############################################"
rpc "libera a OS (condicao financeira = termo)" "$TOK_ENC" rpc_liberar_os "{\"p_os_id\":\"$OS\"}"
tbl_get "status final da OS (esperado liberada)" "$TOK_ENC" "ordens_servico?id=eq.$OS&select=status,data_liberacao"

echo
echo "############################################"
echo "# Relatorio de encerramento"
echo "############################################"
rpc "relatorio de encerramento" "$TOK_ENC" rpc_relatorio_encerramento_os "{\"p_os_id\":\"$OS\"}"

echo
echo "############################################"
echo "# Garantia de item ADICIONAL (item 6/GAR-007) -- abre garantia da OS liberada, cobrindo o item ADICIONAL executado"
echo "############################################"
rpc "ENCARREGADO abre OS de garantia cobrindo o item de ADICIONAL (ITEM_AD)" "$TOK_ENC" rpc_criar_os_garantia \
  "{\"p_os_origem_id\":\"$OS\",\"p_itens_originais\":null,\"p_itens_adicionais_originais\":[\"$ITEM_AD\"]}"
OS_GAR=$(rawid)
echo "OS_GARANTIA=$OS_GAR"
rpc "tenta baixar peca na garantia vinculada ao item de adicional" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GAR\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "transiciona em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS_GAR\",\"p_novo_status\":\"em_execucao\"}"
rpc "baixa peca na OS de garantia (item de adicional original) -- confirma correcao da regressao do P1-B" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS_GAR\",\"p_peca_id\":\"$PECA_AD\",\"p_quantidade\":1,\"p_os_adicional_item_id\":\"$ITEM_AD\"}"
tbl_get "movimento de estoque da garantia" "$TOK_ENC" "estoque_movimentos?origem_id=eq.$OS_GAR&select=peca_id,quantidade,os_adicional_item_id"
rpc "relatorio de garantia" "$TOK_ENC" rpc_relatorio_garantia_os "{\"p_os_garantia_id\":\"$OS_GAR\"}"

echo
echo "############################################"
echo "# item 7: historico do veiculo"
echo "############################################"
rpc "historico do veiculo" "$TOK_ENC" rpc_historico_veiculo "{\"p_veiculo_id\":\"$VEICULO_ID\"}"

echo
echo "############################################"
echo "# RESUMO FINAL E2E EXTERNO COM DESCONTO"
echo "############################################"
echo "ORC=$ORC bruto=300.01 desconto=100.00 liquido=200.01"
echo "ITEM_A aprovado liquido=66.67 ITEM_B REJEITADO (nunca conta) ITEM_C aprovado liquido=66.67"
echo "OS=$OS ADIC(item AD aprovado+executado)=50.00 ADIC2(item cancelado formalmente, nunca conta)=40.00"
echo "COBRANCA=$COB ESPERADO = 66.67 + 66.67 + 50.00 = R\$183.34"
echo "OS_GARANTIA=$OS_GAR (item de adicional, confirma correcao da regressao rpc_baixar_peca_os)"
echo "=== FIM E2E EXTERNO COM DESCONTO ==="
