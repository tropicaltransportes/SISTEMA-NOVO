#!/usr/bin/env bash
# ETAPA 5 (P1-B) — E2E principal + cenários obrigatórios A..P (ver instruções
# do dono do projeto, itens 15/16). Executa contra o Supabase real
# (jzjbiejmcaygwycvqggm) via REST/RPC, igual ao padrão dos scripts etapa3_*/
# etapa4_*.
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
SUP_ID="a0000000-0000-0000-0000-000000000003"

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
echo "# SETUP: cliente/veiculo/pecas exclusivos _p1b + NF de entrada"
echo "############################################"
tbl_post "cria cliente externo _p1b" "$TOK_SUP" "clientes" \
  '{"tipo":"externo","nome":"TESTE_P1B_Cliente_E2E","documento":"90000000000199","telefone":"(11) 99999-0000","email":"p1b@teste.qa"}'
CLIENTE_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "cria veiculo _p1b" "$TOK_SUP" "veiculos" "{\"cliente_id\":\"$CLIENTE_ID\",\"placa\":\"P1B0001\",\"modelo\":\"TESTE_P1B\"}"
VEICULO_ID=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "CLIENTE_ID=$CLIENTE_ID VEICULO_ID=$VEICULO_ID"

tbl_post "peca A (item original aprovado)" "$TOK_SUP" "pecas" \
  '{"sku":"QA_PECA_P1B_A","descricao":"TESTE_P1B_Peca_A","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "peca AD1 (item adicional aprovado)" "$TOK_SUP" "pecas" \
  '{"sku":"QA_PECA_P1B_AD1","descricao":"TESTE_P1B_Peca_AD1","unidade":"UN","saldo_atual":0,"custo_medio":10.00,"estoque_minimo":1}'
PECA_AD1=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")

tbl_post "NF rascunho" "$TOK_SUP" "notas_fiscais_entrada" \
  '{"numero":"NF-P1B-E2E","fornecedor":"TESTE_Fornecedor_P1B","status":"rascunho","data_emissao":"2026-08-13","criado_por":"a0000000-0000-0000-0000-000000000003"}'
NF=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item NF peca A (5un)" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_A\",\"quantidade\":5,\"valor_unitario\":10.00}"
tbl_post "item NF peca AD1 (5un)" "$TOK_SUP" "nf_entrada_itens" "{\"nf_id\":\"$NF\",\"peca_id\":\"$PECA_AD1\",\"quantidade\":5,\"valor_unitario\":10.00}"
rpc "confirma NF" "$TOK_SUP" rpc_confirmar_nf_entrada "{\"p_nf_id\":\"$NF\"}"

echo
echo "############################################"
echo "# E2E-002/APR-002: orcamento R\$1000 (item A peca R\$700 + item B mao de obra R\$300)"
echo "############################################"
tbl_post "cria orcamento rascunho" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item A: peca qtd1 R\$700 (sera APROVADO)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"peca_id\":\"$PECA_A\",\"descricao\":\"TESTE Item A peca\",\"quantidade\":1,\"valor_unitario\":700}"
ITEM_A=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item B: mao de obra R\$300 (sera REJEITADO)" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC\",\"descricao\":\"TESTE Item B mao de obra\",\"quantidade\":1,\"valor_unitario\":300}"
ITEM_B=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
echo "ORC=$ORC ITEM_A=$ITEM_A ITEM_B=$ITEM_B (valor_total esperado 1000)"
tbl_get "confere valor_total do orcamento (esperado 1000)" "$TOK_ENC" "orcamentos?id=eq.$ORC&select=valor_total,status"

rpc "envia orcamento" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC\"}"
COMP_PATH_ORC="p1b/teste-p1b-e2e-orc-$(date +%s).txt"
curl -s -o /dev/null -X POST "$URL/storage/v1/object/comprovantes/$COMP_PATH_ORC" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ENC" -H "Content-Type: text/plain" \
  --data-binary "TESTE P1B - evidencia orcamento nivel cabecalho (nao usado pela decisao por item, so demonstra rpc_registrar_autorizacao_orcamento continua funcionando)."
rpc "registra autorizacao no CABECALHO do orcamento (rpc legado, nao usado pela decisao por item -- so confirma que nao quebrou)" "$TOK_ENC" rpc_registrar_autorizacao_orcamento \
  "{\"p_orcamento_id\":\"$ORC\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\",\"p_comprovante_path\":\"$COMP_PATH_ORC\"}"

echo
echo "############################################"
echo "# APR-004: decide ITEM A = aprovado, meio=sistema"
echo "############################################"
rpc "ENCARREGADO decide ITEM_A aprovado (sistema)" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_A\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\"}"

echo
echo "############################################"
echo "# APR-006: decide ITEM B = rejeitado, meio=verbal_documentado (com observacao)"
echo "############################################"
rpc "ENCARREGADO decide ITEM_B rejeitado (verbal_documentado)" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_B\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"verbal_documentado\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\",\"p_observacao\":\"Cliente ligou e recusou o servico de mao de obra por telefone, confirmado pelo encarregado.\"}"

echo "--- status final do orcamento (esperado: parcialmente_aprovado) ---"
tbl_get "orcamento apos decisoes" "$TOK_ENC" "orcamentos?id=eq.$ORC&select=status,valor_total"
echo "--- itens com status_aprovacao/meio_aprovacao ---"
tbl_get "itens do orcamento" "$TOK_ENC" "orcamento_itens?orcamento_id=eq.$ORC&select=id,descricao,valor_total,status_aprovacao,meio_aprovacao,autorizado_por_nome,registrado_por"

echo
echo "############################################"
echo "# CENARIO M: retry da MESMA decisao (duplo clique) -- deve ser idempotente (sem erro, sem duplicar)"
echo "############################################"
rpc "retry: decide ITEM_A aprovado de novo (mesma decisao)" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_A\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\"}"

echo
echo "############################################"
echo "# CENARIO N: decisao CONFLITANTE (tenta rejeitar item ja aprovado) -- deve BLOQUEAR"
echo "############################################"
rpc "tenta rejeitar ITEM_A (ja aprovado) -- deve falhar" "$TOK_ENC" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_A\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\"}"

echo
echo "############################################"
echo "# APR-007: EXECUTOR tenta decidir item -- deve BLOQUEAR (nao pode aprovar)"
echo "############################################"
tbl_post "cria orcamento so p/ este teste de permissao" "$TOK_ENC" "orcamentos" "{\"veiculo_id\":\"$VEICULO_ID\",\"cliente_id\":\"$CLIENTE_ID\",\"criado_por\":\"$ENC_ID\"}"
ORC_PERM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "item p/ teste de permissao" "$TOK_ENC" "orcamento_itens" "{\"orcamento_id\":\"$ORC_PERM\",\"descricao\":\"TESTE item permissao\",\"quantidade\":1,\"valor_unitario\":100}"
ITEM_PERM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "envia" "$TOK_ENC" rpc_enviar_orcamento "{\"p_orcamento_id\":\"$ORC_PERM\"}"
rpc "EXECUTOR tenta decidir item -- deve HTTP 400" "$TOK_EXE" rpc_decidir_item_orcamento \
  "{\"p_orcamento_item_id\":\"$ITEM_PERM\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"sistema\",\"p_autorizado_por_nome\":\"X\"}"

echo
echo "############################################"
echo "# OS-002: converte orcamento PARCIALMENTE APROVADO em OS (so R\$700 elegivel)"
echo "############################################"
rpc "converte em OS externa" "$TOK_ENC" rpc_criar_os "{\"p_veiculo_id\":\"$VEICULO_ID\",\"p_tipo\":\"externa\",\"p_orcamento_id\":\"$ORC\"}"
OS=$(rawid)
echo "OS=$OS"
rpc "transiciona aberta->em_diagnostico" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_diagnostico\"}"
rpc "transiciona em_diagnostico->em_execucao" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"em_execucao\"}"

echo
echo "############################################"
echo "# CENARIO D/E: item B REJEITADO tentando executar/baixar estoque -- deve BLOQUEAR"
echo "############################################"
rpc "tenta marcar ITEM_B (rejeitado, mao de obra) como executado -- deve falhar" "$TOK_EXE" rpc_marcar_item_orcamento_execucao \
  "{\"p_orcamento_item_id\":\"$ITEM_B\",\"p_status\":\"executado\"}"

echo
echo "############################################"
echo "# Executa ITEM_A (aprovado, peca) -- baixa 1un"
echo "############################################"
rpc "EXECUTOR baixa peca do ITEM_A (aprovado)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_A\",\"p_quantidade\":1,\"p_orcamento_item_id\":\"$ITEM_A\"}"
tbl_get "execucao_status ITEM_A (esperado executado)" "$TOK_ENC" "orcamento_itens?id=eq.$ITEM_A&select=execucao_status"

echo
echo "############################################"
echo "# ADC-001: EXECUTOR identifica necessidade de adicional (motivo)"
echo "############################################"
rpc "EXECUTOR cria cabecalho do adicional AD-001" "$TOK_EXE" rpc_criar_os_adicional \
  "{\"p_os_id\":\"$OS\",\"p_motivo\":\"Durante a execucao foi identificado desgaste em peca nao prevista e servico extra necessario\"}"
ADIC=$(rawid)
echo "ADICIONAL=$ADIC"

echo
echo "############################################"
echo "# EXECUTOR tenta precificar/incluir item -- deve BLOQUEAR (nao define preco)"
echo "############################################"
rpc "EXECUTOR tenta incluir item precificado -- deve falhar" "$TOK_EXE" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":\"$PECA_AD1\",\"p_descricao\":\"TESTE item adicional AD1\",\"p_quantidade\":1,\"p_valor_unitario\":250}"

echo
echo "############################################"
echo "# ENCARREGADO precifica os 2 itens do adicional (total R\$400: AD1 peca R\$250 + AD2 mao de obra R\$150)"
echo "############################################"
rpc "ENCARREGADO inclui item AD1 (peca, R\$250)" "$TOK_ENC" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":\"$PECA_AD1\",\"p_descricao\":\"TESTE item adicional AD1 peca\",\"p_quantidade\":1,\"p_valor_unitario\":250,\"p_justificativa\":\"Peca extra necessaria identificada em execucao\"}"
ITEM_AD1=$(rawid)
rpc "ENCARREGADO inclui item AD2 (mao de obra, R\$150)" "$TOK_ENC" rpc_incluir_item_os_adicional \
  "{\"p_adicional_id\":\"$ADIC\",\"p_peca_id\":null,\"p_descricao\":\"TESTE item adicional AD2 mao de obra\",\"p_quantidade\":1,\"p_valor_unitario\":150,\"p_justificativa\":\"Servico extra de mao de obra\"}"
ITEM_AD2=$(rawid)
echo "ITEM_AD1=$ITEM_AD1 ITEM_AD2=$ITEM_AD2 (total esperado 400)"
tbl_get "cabecalho do adicional (esperado status aguardando_aprovacao)" "$TOK_ENC" "os_adicionais?id=eq.$ADIC&select=numero,status,motivo"

echo
echo "############################################"
echo "# ADC-002: tenta executar adicional AINDA sem aprovacao -- deve BLOQUEAR"
echo "############################################"
rpc "EXECUTOR tenta baixar peca do AD1 (ainda pendente) -- deve falhar" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_AD1\",\"p_quantidade\":1,\"p_os_adicional_item_id\":\"$ITEM_AD1\"}"

echo
echo "############################################"
echo "# ADC-003/APR-005: cliente aprova AD1 via e-mail (evidencia obrigatoria -- upload REAL no Storage)"
echo "############################################"
rpc "SUPORTE decide AD1 aprovado (email) SEM comprovante -- deve falhar (DOC-005)" "$TOK_SUP" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD1\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"email\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\"}"
COMP_PATH="p1b/teste-p1b-e2e-ad1-$(date +%s).txt"
echo "--- SUPORTE faz upload real do comprovante no bucket comprovantes ($COMP_PATH) ---"
curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL/storage/v1/object/comprovantes/$COMP_PATH" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK_SUP" -H "Content-Type: text/plain" \
  --data-binary "TESTE P1B - evidencia de aprovacao via e-mail do item adicional AD1 (ADC-003/APR-005)."
rpc "SUPORTE decide AD1 aprovado (email) COM comprovante real" "$TOK_SUP" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD1\",\"p_decisao\":\"aprovado\",\"p_meio_aprovacao\":\"email\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\",\"p_comprovante_path\":\"$COMP_PATH\"}"

echo
echo "############################################"
echo "# ADC-004: cliente rejeita AD2"
echo "############################################"
rpc "ENCARREGADO decide AD2 rejeitado (verbal_documentado)" "$TOK_ENC" rpc_decidir_item_os_adicional \
  "{\"p_item_id\":\"$ITEM_AD2\",\"p_decisao\":\"rejeitado\",\"p_meio_aprovacao\":\"verbal_documentado\",\"p_autorizado_por_nome\":\"TESTE Responsavel Cliente\",\"p_observacao\":\"Cliente recusou o servico extra de mao de obra por telefone.\"}"

echo "--- status do adicional apos decisoes (esperado parcialmente_aprovado) ---"
tbl_get "adicional" "$TOK_ENC" "os_adicionais?id=eq.$ADIC&select=status"
tbl_get "itens do adicional" "$TOK_ENC" "os_adicional_itens?adicional_id=eq.$ADIC&select=descricao,valor_total,status_aprovacao,meio_aprovacao"

echo
echo "############################################"
echo "# CENARIO K: item AD2 (rejeitado) tentando baixar estoque -- deve BLOQUEAR"
echo "############################################"
rpc "EXECUTOR tenta marcar AD2 (rejeitado) executado -- deve falhar" "$TOK_EXE" rpc_marcar_item_os_adicional_execucao \
  "{\"p_item_id\":\"$ITEM_AD2\",\"p_status\":\"executado\"}"

echo
echo "############################################"
echo "# Executa AD1 (aprovado, peca) -- baixa 1un"
echo "############################################"
rpc "EXECUTOR baixa peca do AD1 (aprovado)" "$TOK_EXE" rpc_baixar_peca_os \
  "{\"p_os_id\":\"$OS\",\"p_peca_id\":\"$PECA_AD1\",\"p_quantidade\":1,\"p_os_adicional_item_id\":\"$ITEM_AD1\"}"
tbl_get "execucao_status AD1 (esperado executado)" "$TOK_ENC" "os_adicional_itens?id=eq.$ITEM_AD1&select=execucao_status"

echo
echo "############################################"
echo "# ADC-005/APR-008/APR-009: tenta alterar item ja decidido via UPDATE direto -- deve BLOQUEAR (RLS sem policy de UPDATE)"
echo "############################################"
call "tenta UPDATE direto no valor_unitario do ITEM_A (ja aprovado)" PATCH "$TOK_ENC" "$URL/rest/v1/orcamento_itens?id=eq.$ITEM_A" '{"valor_unitario":999}'
call "tenta UPDATE direto no valor_unitario do ITEM_AD1 (ja aprovado)" PATCH "$TOK_ENC" "$URL/rest/v1/os_adicional_itens?id=eq.$ITEM_AD1" '{"valor_unitario":999}'

echo
echo "############################################"
echo "# ADC-008: dupla criacao de adicional por clique (mesma idempotency_key) -- nao duplica"
echo "############################################"
IDEMK="11111111-2222-3333-4444-p1badc008xx1"
IDEMK="11111111-2222-3333-4444-000000000ad8"
rpc "1a chamada com idempotency_key" "$TOK_EXE" rpc_criar_os_adicional \
  "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE ADC-008 duplo clique\",\"p_idempotency_key\":\"$IDEMK\"}"
ADIC_DUP1=$(rawid)
rpc "2a chamada (retry) com a MESMA idempotency_key" "$TOK_EXE" rpc_criar_os_adicional \
  "{\"p_os_id\":\"$OS\",\"p_motivo\":\"TESTE ADC-008 duplo clique\",\"p_idempotency_key\":\"$IDEMK\"}"
ADIC_DUP2=$(rawid)
echo "ADIC_DUP1=$ADIC_DUP1 ADIC_DUP2=$ADIC_DUP2 (esperado: iguais)"
tbl_get "conta quantos adicionais com esse motivo existem (esperado 1)" "$TOK_ENC" "os_adicionais?os_id=eq.$OS&motivo=eq.TESTE%20ADC-008%20duplo%20clique&select=id"

echo
echo "############################################"
echo "# Cancela formalmente o adicional vazio criado so p/ o teste ADC-008 (senao ficaria 'aguardando_aprovacao' bloqueando a conclusao da OS pra sempre -- achado real corrigido nesta rodada, ver migration 20260813100600)"
echo "############################################"
rpc "ENCARREGADO cancela o adicional de teste ADC-008 (motivo obrigatorio)" "$TOK_ENC" rpc_cancelar_os_adicional \
  "{\"p_adicional_id\":\"$ADIC_DUP1\",\"p_motivo\":\"Adicional criado apenas para o teste automatizado ADC-008 (duplo clique) -- cancelado, nao corresponde a necessidade real da OS.\"}"
tbl_get "status do adicional de teste apos cancelamento (esperado rejeitado)" "$TOK_ENC" "os_adicionais?id=eq.$ADIC_DUP1&select=status"

echo
echo "############################################"
echo "# Marca checklist e conclui a OS"
echo "############################################"
tbl_get "checklist template padrao" "$TOK_ENC" "checklist_templates?select=id,nome&limit=1"
CHK_TPL=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
rpc "define checklist da OS" "$TOK_ENC" rpc_definir_checklist_os "{\"p_os_id\":\"$OS\",\"p_checklist_template_id\":\"$CHK_TPL\"}"
tbl_get "itens obrigatorios do checklist" "$TOK_ENC" "checklist_template_itens?template_id=eq.$CHK_TPL&select=id,obrigatorio"
rpc "transiciona em_execucao->aguardando_teste" "$TOK_ENC" rpc_transicionar_os "{\"p_os_id\":\"$OS\",\"p_novo_status\":\"aguardando_teste\"}"

echo
echo "############################################"
echo "# CON-002 estendido: tenta concluir com AD2... espera, AD2 ja decidido (rejeitado, nao bloqueia). Confirma conclusao OK."
echo "############################################"
rpc "tenta concluir SEM responder checklist -- deve falhar" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"

echo
echo "############################################"
echo "# CON-002 (item C): item de mao de obra ITEM_B rejeitado -- confirma que NAO bloqueia conclusao mesmo pendente/rejeitado"
echo "############################################"
tbl_get "checklist itens obrigatorios" "$TOK_ENC" "checklist_template_itens?template_id=eq.$CHK_TPL&select=id,descricao,obrigatorio"
CHK_ITEM=$(jf "print(d[0]['id'] if isinstance(d,list) and d else '')")
tbl_post "responde item obrigatorio do checklist (ok=true)" "$TOK_ENC" "os_checklist_respostas" \
  "{\"os_id\":\"$OS\",\"template_item_id\":\"$CHK_ITEM\",\"ok\":true,\"respondido_por\":\"$ENC_ID\",\"respondido_em\":\"2026-08-13T12:00:00Z\"}"

echo
echo "############################################"
echo "# ADC-002 novamente: AD2 rejeitado tentando marcar execucao -- ja confirmado bloqueado acima; agora conclui a OS"
echo "############################################"
rpc "CONCLUI a OS (checklist ok, ITEM_A executado, AD1 executado, ITEM_B/AD2 rejeitados nao bloqueiam)" "$TOK_ENC" rpc_concluir_os "{\"p_os_id\":\"$OS\"}"
tbl_get "status da OS (esperado concluida)" "$TOK_ENC" "ordens_servico?id=eq.$OS&select=status"

echo
echo "############################################"
echo "# FIN/item 10: gera cobranca -- valor esperado EXATO R\$950.00 (700 aprovado original + 250 aprovado adicional; 300 + 150 rejeitados NUNCA entram)"
echo "############################################"
rpc "SUPORTE gera cobranca da OS" "$TOK_SUP" rpc_criar_cobranca "{\"p_cliente_id\":\"$CLIENTE_ID\",\"p_os_ids\":[\"$OS\"],\"p_venda_ids\":null}"
COB=$(rawid)
echo "COBRANCA=$COB"
tbl_get "valor_total da cobranca (ESPERADO 950.00)" "$TOK_SUP" "cobrancas?id=eq.$COB&select=valor_total,status"

echo
echo "############################################"
echo "# Pagamento -> liberacao -> garantia (fluxo residual, confirma que nao regrediu)"
echo "############################################"
rpc "parcela unica R\$950" "$TOK_SUP" rpc_parcelar_cobranca "{\"p_cobranca_id\":\"$COB\",\"p_parcelas\":[{\"numero_parcela\":1,\"valor\":950,\"vencimento\":\"2026-09-13\"}]}"
tbl_get "parcela criada" "$TOK_SUP" "parcelas?cobranca_id=eq.$COB&select=id,valor"
PARCELA=$(echo "$BODY" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
rpc "registra recebimento total (R\$950, pix)" "$TOK_SUP" rpc_registrar_recebimento "{\"p_parcela_id\":\"$PARCELA\",\"p_valor_recebido\":950,\"p_forma_pagamento\":\"pix\",\"p_data_recebimento\":\"2026-08-13\"}"
tbl_get "cobranca apos pagamento (esperado quitada)" "$TOK_SUP" "cobrancas?id=eq.$COB&select=status,valor_total"
rpc "libera a OS (cobranca quitada)" "$TOK_ENC" rpc_liberar_os "{\"p_os_id\":\"$OS\"}"
tbl_get "status final da OS (esperado liberada)" "$TOK_ENC" "ordens_servico?id=eq.$OS&select=status,data_liberacao"

echo
echo "############################################"
echo "# GAR/ADC-006: confirma que o historico preserva ITEM_B (rejeitado) e ITEM_AD2 (rejeitado) -- nunca apagados"
echo "############################################"
tbl_get "ITEM_B continua no historico (rejeitado, valor 300)" "$TOK_ENC" "orcamento_itens?id=eq.$ITEM_B&select=descricao,valor_total,status_aprovacao"
tbl_get "ITEM_AD2 continua no historico (rejeitado, valor 150)" "$TOK_ENC" "os_adicional_itens?id=eq.$ITEM_AD2&select=descricao,valor_total,status_aprovacao"
tbl_get "trilha de auditoria do orcamento (AUD)" "$TOK_ENC" "auditoria_eventos?entidade=eq.orcamento_itens&entidade_id=eq.$ITEM_A&select=acao,valor_anterior,valor_novo,criado_em"
tbl_get "trilha de auditoria do adicional (AUD)" "$TOK_ENC" "auditoria_eventos?entidade=eq.os_adicionais&entidade_id=eq.$ADIC&select=acao,valor_novo,criado_em"

echo
echo "############################################"
echo "# RESUMO FINAL E2E"
echo "############################################"
echo "ORC=$ORC ITEM_A(aprovado R\$700)=$ITEM_A ITEM_B(rejeitado R\$300)=$ITEM_B"
echo "OS=$OS ADIC=$ADIC ITEM_AD1(aprovado R\$250)=$ITEM_AD1 ITEM_AD2(rejeitado R\$150)=$ITEM_AD2"
echo "COBRANCA=$COB -- VALOR ESPERADO = 700 + 250 = R\$950.00 (300 + 150 = R\$450 rejeitados NUNCA cobrados)"
echo "=== FIM E2E PRINCIPAL ==="
