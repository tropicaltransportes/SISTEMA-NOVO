# ETAPA OS-FLOW-03 — Relatório: máquina de estados, apontamentos e peças adicionais

Data: 2026-08-20. Escopo: correção de regra de negócio na máquina de
estados da OS + reorganização de apresentação (aprovado ≠ utilizado).
**DEV/QA apenas** (`jzjbiejmcaygwycvqggm`) — nada foi promovido a
produção nesta etapa, conforme pedido explícito.

## FASES REAIS

`status_os` é um **enum** Postgres (não CHECK), definido em
`20260806130200_ordens_servico.sql`, nunca alterado desde então: `aberta,
em_diagnostico, aguardando_aprovacao, em_execucao, aguardando_teste,
concluida, liberada, reaberta_garantia, cancelada`. `reaberta_garantia`
é vestigial — nenhuma transição real o produz (só a OS de origem de uma
garantia recebe esse status, via `rpc_criar_os_garantia`). `BR-035`
(`docs/testing/BUSINESS_RULES.md`) estava desatualizada (descrevia um
enum hipotético que nunca foi implementado) — corrigida nesta etapa.

## ATIVIDADES

`os_executores.etapa` é o enum `etapa_execucao` (`diagnostico, execucao,
teste, revisao`) — conceito **separado** da fase da OS, confirmado por
auditoria: não existe FK/CHECK cruzando os dois. Antes desta etapa, o
frontend só sugeria automaticamente `diagnostico`/`execucao` (nunca
`teste`) ao iniciar um apontamento — gap corrigido em
`OsTrabalhoAtual.vue` (`etapaSugerida`), que ajudava a inconsistência
original a acontecer.

## INCONSISTÊNCIA FASE/APONTAMENTO

**Confirmada e corrigida.** Nenhuma das duas RPCs de transição
(`rpc_transicionar_os`, `rpc_concluir_os`) consultava `os_executores`
antes desta etapa — uma OS podia chegar em `aguardando_teste` (ou até ser
concluída) com um apontamento de execução ainda `fim is null`. Corrigido
em `supabase/migrations/20260819180000_p2e_os_fluxo_transicoes.sql`: as
duas RPCs agora bloqueiam com `"Finalize o apontamento em andamento antes
de transicionar/concluir esta OS."` sempre que existir
`os_executores.fim is null and coalesce(ativo, true)` para a OS.
Diagnóstico prévio em DEV (query read-only, antes da migration): **0 OS
inconsistentes encontradas** — nenhum dado precisou de correção manual.

## RETORNO DE FASE

Implementados 2 retrocessos controlados em `rpc_transicionar_os`:
`aguardando_teste → em_execucao` (pedido, item 7) e `em_execucao →
em_diagnostico` (item 6, "avaliar" — decidi implementar, mesmo padrão,
mesmo risco baixo). `concluida → teste/execução` (item 9) foi avaliado e
**conscientemente não implementado**: uma OS `concluida` externa pode já
ter cobrança vinculada antes de ser liberada, e desfazer a conclusão sem
tratar essa cobrança é inseguro — decisão documentada em BR-053. `liberada`
nunca permite retorno operacional (não está em nenhuma tupla).

## MOTIVO

Retrocesso exige `p_motivo` (mínimo 5 caracteres) — sem isso, a RPC
bloqueia com mensagem explícita. Testado via pgTAP (OS-FLOW-004) e ao
vivo no browser (dialog de motivo, `OrdemServicoDetalhe.vue`).

## AUDITORIA

Cada retrocesso grava um evento explícito em `auditoria_eventos`
(`registrar_auditoria`) com `acao='OS_RETORNOU_PARA_EXECUCAO'` ou
`'OS_RETORNOU_PARA_DIAGNOSTICO'`, status anterior/novo, motivo, usuário e
timestamp — além do `mudanca_status` genérico que o trigger
`trg_audit_os_status` já grava pra toda transição (sem motivo). Confirmado
via pgTAP (OS-FLOW-003, lê `auditoria_eventos` de volta e compara o
motivo exato) e ao vivo no browser ("Atividade Recente" mostrando a
transição correta após cada retorno).

## ADICIONAIS

Formalizado: `os_adicional_itens.status_aprovacao` (decisão do cliente:
pendente/aprovado/rejeitado) já era uma coluna **independente** de
`execucao_status` (consumo físico: pendente/parcial/executado/cancelado)
— mesmo padrão em `orcamento_itens`. Nenhuma mudança de schema foi
necessária; o problema era só de apresentação. `OsCardsApoio.vue` ganhou
contagem por item (identificados/aprovados/executados/aguardando decisão)
em vez de só "N aguardando / M"; `OsAdicionaisDialog.vue` ganhou rótulo
"Pendente de utilização" em vez do valor cru `execucao_status`. Testado
ao vivo: criar adicional → incluir item (mão de obra, o teste de clique
automatizado não conseguiu selecionar Peça no PrimeVue Select — ver
Frontend abaixo) → decidir aprovado → card mudou corretamente para "1
identificado(s) / 1 aprovado(s) · 0 executado(s)".

## PEÇAS APROVADAS

`itensParaBaixa` (computed já existente no orquestrador, reaproveitado
sem alteração) já calculava, por item aprovado, `restante = aprovado -
(baixado - estornado)` a partir do ledger de `estoque_movimentos`.
`OsPecasDialog.vue` ganhou seção "Previstas / Aprovadas" mostrando
Aprovada/Utilizada/Pendente por linha + botão "Registrar utilização"
(chama a mesma `rpc_baixar_peca_os` de sempre, sem lógica de estoque
duplicada). Confirmado via pgTAP (OS-ADP-002: item recém-aprovado
continua `execucao_status='pendente'`) e visualmente no browser (dialog
abre sem erro, estado vazio correto quando não há pendência).

## PEÇAS UTILIZADAS

Seção "Utilizadas" preservada sem alteração (mesma tabela de
`movimentos`). Confirmado ao vivo mostrando um movimento real existente.

## ESTOQUE

`rpc_baixar_peca_os` **não foi alterada** — já bloqueava baixa de item
não aprovado (`status_aprovacao <> 'aprovado'`) e já calculava
`disponivel` corretamente antes desta etapa. Confirmado por pgTAP
(OS-ADP-003: baixa de item aprovado passa, `execucao_status` vira
`executado`; OS-ADP-004: baixa de item rejeitado é bloqueada).

## UTILIZAÇÃO PARCIAL

Suportada pelo modelo já existente (`execucao_status='parcial'` quando
`0 < baixado < aprovado`, via `sincronizar_execucao_item_orcamento`/
`sincronizar_execucao_item_adicional`, não alterados nesta etapa) —
`OsPecasDialog.vue` exibe Pendente = Aprovada − Utilizada por linha, que
reflete parcialidade automaticamente. Não foi criado um caso pgTAP
dedicado de utilização parcial nesta etapa (o OS-ADP-003 já testado usa
baixa total) — comportamento herdado e não modificado, risco baixo.

## FRONTEND

`OrdemServicoDetalhe.vue`, `OsCabecalho.vue`, `OsTrabalhoAtual.vue`,
`OsPecasDialog.vue`, `OsCardsApoio.vue`, `OsPendenciasConclusao.vue`,
`OsAdicionaisDialog.vue` editados. Testado ao vivo no browser (login real
`teste.encarregado@qa.local`, DEV): ciclo completo **Execução → Teste →
Retornar para Execução (com motivo, dialog real) → Execução → Teste**
funcionou de ponta a ponta sem hack manual no banco — status, ação
principal do cabeçalho, rótulo "Atividade"/"Iniciar teste" vs "Iniciar
trabalho", "Pendências para Conclusão" e "Atividade Recente" todos
corretos a cada passo. Confirmado visualmente que, com apontamento
aberto, o botão de avanço de fase some e vira um aviso
("Finalize o apontamento em andamento para avançar de fase"). O card de
Adicionais e o banner de "adicional aguardando decisão" confirmados ao
vivo. **Limitação da sessão de teste**: não consegui selecionar uma Peça
no `Select` do PrimeVue via clique automatizado dentro do dialog "Incluir
Item Precificado" (item acabou incluído como mão de obra) — a seção
"Previstas/Aprovadas" do `OsPecasDialog` foi confirmada renderizando sem
erro (estado vazio), mas a linha não-vazia com botão "Registrar
utilização" não foi clicada de fato nesta sessão; a lógica que a alimenta
(`itensParaBaixa`) é a mesma já validada por pgTAP (OS-ADP-002/003).
Recomendo uma conferência visual humana rápida dessa seção específica.

## PGTAP

`supabase/tests/100_transicao_os.sql` (novo, 16/16 assertions):
OS-FLOW-001/002/003/004/005/006, OS-AP-003, OS-ADP-002/003/004.
OS-ADP-001 (peça aprovada aparece no escopo da OS) é comportamento de
apresentação, não testável por pgTAP — coberto pela verificação de
browser acima. `supabase/tests/060_contratos_rpc_criticas.sql` foi
atualizado (contrato de `rpc_transicionar_os` passou de 2 para 3
parâmetros — mudança intencional, documentada no próprio teste).

**Achado real durante a implementação (não estava no pedido):**
`create or replace function rpc_transicionar_os(uuid, status_os, text
default null)` não substituiu a versão de 2 parâmetros — Postgres
identifica função por lista de tipos de parâmetro, então as duas
coexistiram como overload, tornando toda chamada de 2 argumentos
ambígua (quebraria o frontend inteiro, que ainda chama sem motivo em todo
lugar exceto o retorno de fase). Corrigido com uma segunda migration
(`20260819180100_p2e_fix_overload_rpc_transicionar_os.sql`, `drop
function if exists rpc_transicionar_os(uuid, status_os)`) — mesmo padrão
já usado em `20260817140100_p2_fix_natureza_gerada.sql` (correção vira
migration nova, nunca edita uma já aplicada).

## REGRESSÃO

10 arquivos pgTAP rodados via `npx supabase db query --linked -f` contra
DEV: `010, 020, 030, 040, 050, 060, 070, 080, 090, 100` — **todos verdes**
depois da correção do contrato em `060` (218 assertions no total, 0
falhas). `npm run build` (frontend) limpo, rodado 1x após todas as edições.

## Critério de aceite (checklist)

1. ✅ OS em Teste não pode continuar com apontamento de Execução aberto
   (BR-052, `rpc_transicionar_os`/`rpc_concluir_os`).
2. ✅ Avanço de fase bloqueia apontamento incompatível (mesma checagem,
   sem distinguir etapa — "qualquer apontamento aberto", conforme item
   11 do pedido).
3. ✅ Teste → Execução controlado (BR-053).
4. ✅ Retorno exige motivo e gera auditoria (`OS_RETORNOU_PARA_EXECUCAO`/
   `_DIAGNOSTICO`).
5. ✅ Histórico nunca apagado (OS-FLOW-005: apontamentos antigos
   preservados, `fim` intacto).
6. ✅ Ciclo Execução→Teste→Execução→Teste funciona (testado por pgTAP e
   ao vivo no browser).
7. ✅ Peça adicional aprovada aparece no escopo da OS (`OsPecasDialog`
   "Previstas/Aprovadas").
8. ✅ Frontend distingue aprovado de utilizado (Aprovada/Utilizada/
   Pendente por linha, "Pendente de utilização" em vez de valor cru).
9. ✅ Só conta como utilizada após consumo físico real
   (`execucao_status`, inalterado, já era assim).
10. ✅ Baixa de estoque continua vinculada à origem correta
    (`rpc_baixar_peca_os`, inalterada).
11. ✅ Item rejeitado nunca pode ser utilizado (OS-ADP-004).
12. ✅ Frontend deixa claro aprovado ≠ utilizado (`OsPecasDialog`,
    `OsPendenciasConclusao` — nova linha "peça(s) aprovada(s) ainda não
    utilizada(s)").
13. ✅ Nenhuma regra crítica só no frontend — bloqueio real está nas RPCs;
    frontend só reflete visualmente (`apontamentoAberto` em
    `OsCabecalho.vue`).
14. ✅ Regressão permanece verde (218/218 assertions, 10 arquivos).

## Dados inconsistentes encontrados

Nenhum (query de diagnóstico rodada antes da migration, 0 linhas — ver
seção "Inconsistência fase/apontamento" acima).

## Pendências

- Perfil Executor/Suporte Administrativo não testados ao vivo nesta etapa
  (só Encarregado) — RBAC não foi alterado, mesmos gates de sempre.
- Conferência visual humana da seção "Previstas/Aprovadas" do
  `OsPecasDialog` com um item de peça real (não mão de obra) — não
  consegui selecionar Peça no Select via automação nesta sessão.
- Utilização parcial não tem caso pgTAP dedicado (comportamento herdado,
  não modificado).
