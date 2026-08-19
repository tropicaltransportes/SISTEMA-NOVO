# TEST_REPORT — FEATURE-OS-CANCELAMENTO-01

Exclusão lógica e cancelamento seguro de Ordens de Serviço. Implementado e testado em **DEV/QA** (projeto `jzjbiejmcaygwycvqggm`) — 50/50 pgTAP + 84/84 regressão verdes, validado em browser real, antes de qualquer promoção.

**Atualização de 2026-08-19 (fora do escopo original desta rodada):** as
4 migrations foram promovidas para produção (`wtxbodhqyasdlmyoyjur`) em
caráter **emergencial**, com autorização explícita do dono do projeto,
depois que um merge de PR feito por fora desta sessão publicou o frontend
novo em produção sem o schema correspondente, quebrando a listagem de OS
ao vivo. Ver `docs/ENVIRONMENTS.md`, seção "Promoção emergencial de
2026-08-19", para a causa raiz completa e o risco estrutural exposto no
pipeline de deploy. Produção confirmada 55/55 migrations, local == remote,
depois da promoção.

Data: 2026-08-18 (implementação/testes) — 2026-08-19 (promoção emergencial).

## Resumo executivo

Formalizados dois fluxos distintos e um terceiro conceito de bloqueio:

1. **Exclusão lógica** (`rpc_excluir_os_rascunho`) — só para OS `aberta` sem nenhum rastro operacional. Soft delete (`deleted_at/deleted_by/deleted_reason`), nunca `DELETE` físico.
2. **Cancelamento formal** (`rpc_cancelar_os`) — para OS já operada (`aberta` até `concluida`). Transação única: encerra apontamentos abertos, fecha adicionais pendentes, estorna estoque (idempotente), reabre item de mão de obra parcial, reverte OS origem de garantia para `liberada`, grava motivo/auditoria.
3. **Bloqueio** — recebimento confirmado, cobrança ativa, `liberada`/`reaberta_garantia`, ou garantia já derivada nunca permitem cancelamento simples.

4 migrations novas, 1 RPC nova (`rpc_cancelar_os`) + 1 RPC de restauração nova (`rpc_restaurar_os_excluida`) + 1 RPC de exclusão nova (`rpc_excluir_os_rascunho`) + 5 RPCs existentes alteradas (patch mínimo, corpo majoritariamente reproduzido). 50 asserções pgTAP novas, 100% verdes. Regressão completa (010 a 080, 84 asserções) permanece verde. 1 bug real encontrado e corrigido durante a validação em browser (ver ACHADOS).

---

## Resultado por item

```
MODELAGEM              = OK — schema real auditado antes de qualquer alteração (status_os, os_executores,
                          os_adicionais/os_adicional_itens, estoque_movimentos, cobrancas/cobranca_origens/
                          parcelas/recebimentos, os_garantia_itens, auditoria_eventos). Nenhum nome assumido.
EXCLUSÃO LÓGICA         = OK — rpc_excluir_os_rascunho, soft delete (deleted_at/deleted_by/deleted_reason),
                          nunca DELETE físico. BR-048.
CRITÉRIO OS VIRGEM      = OK — status='aberta' E ausência de apontamento/estoque/foto/adicional/checklist
                          respondido/cobrança. Documentado item a item em BR-048, com nota explícita de quais
                          checagens são "defesa em profundidade" (estruturalmente inalcançáveis pelo fluxo real
                          em 'aberta') vs realmente alcançáveis (foto e adicional SÃO permitidos em 'aberta').
CANCELAMENTO            = OK — rpc_cancelar_os, 6 status de origem permitidos (aberta..concluida), transação
                          única, motivo obrigatório. rpc_transicionar_os passa a rejeitar 'cancelada'. BR-049.
ESTOQUE                 = OK — loop reaproveita estornar_saida_estoque_interno já existente; cobre peça de
                          orçamento E de adicional sem lógica nova (mesma origem_tipo/origem_id).
ESTORNO                 = OK — idempotente por construção (guarda estornado_de já existente); mão de obra
                          (sem peça, sem ledger) tratada explicitamente 'parcial'->'pendente'.
APONTAMENTOS            = OK — fim is null vira now() ao cancelar; auditado
                          (APONTAMENTO_ENCERRADO_POR_CANCELAMENTO). Histórico nunca apagado.
FOTOS                   = OK — nunca excluídas; RPC de registro ganhou guarda de deleted_at (OS excluída não
                          recebe novo anexo).
CHECKLIST               = OK — respostas nunca apagadas; seleção de template sozinha não bloqueia exclusão,
                          resposta real bloqueia. Gate de cancelamento não exige checklist completo.
ADICIONAIS              = OK — aguardando_aprovacao fecha formalmente ao cancelar (helper reaproveitado de
                          rpc_cancelar_os_adicional, sem inventar vocabulário novo); executado nunca é tocado.
FINANCEIRO              = OK — recebimento confirmado bloqueia sempre; cobrança ativa sem pagamento bloqueia
                          e exige cancelar a cobrança primeiro (fluxo manual, gate de perfil próprio) — decisão
                          deliberada de não auto-cancelar cobrança dentro de rpc_cancelar_os. BR-050.
LIBERAÇÃO               = OK — 'liberada' sempre bloqueada, mensagem explícita.
GARANTIA                = OK — origem com filha derivada bloqueada (defesa em profundidade); cancelar a
                          PRÓPRIA garantia devolve a origem de 'reaberta_garantia' para 'liberada' — achado
                          durante o design, sem isso a origem ficaria presa para sempre (ver ACHADOS).
ORÇAMENTO ORIGEM        = OK — nunca apagado/cancelado/alterado por cancelamento ou exclusão de OS.
RECONVERSÃO             = OK — BR-008 preservada; achado durante os testes de restauração: exclusão lógica
                          não liberava o orçamento para reconversão porque o predicado de bloqueio não sabia
                          de deleted_at — corrigido (migration 4, ver ACHADOS).
RBAC                    = OK — excluir/cancelar: encarregado/administrador_tecnico. Restaurar: só
                          administrador_tecnico. Testado: executor bloqueado, anon bloqueado, usuário inativo
                          bloqueado mesmo com perfil correto.
RLS                     = OK — OS excluída invisível para quem não é administrador_tecnico (mesmo quem
                          excluiu perde a visão imediatamente); guardas de deleted_at acrescentadas em
                          policies que só checavam status (os_executores, os_checklist_respostas).
AUDITORIA               = OK — OS_EXCLUIDA, OS_RESTAURADA, OS_CANCELADA (com motivo real, diferente do
                          trigger genérico), APONTAMENTO_ENCERRADO_POR_CANCELAMENTO, ADICIONAL_CANCELADO_POR_OS.
IDEMPOTÊNCIA            = OK — excluir/cancelar uma OS já excluída/cancelada é bloqueado explicitamente;
                          estorno de estoque é independentemente idempotente (guarda estornado_de).
CONCORRÊNCIA            = PARCIAL — for update em rpc_cancelar_os e (novo) em rpc_baixar_peca_os garantem
                          serialização real. Testes pgTAP só provam o INVARIANTE de estado final via duas
                          ordens de execução sequenciais, não duas sessões HTTP simultâneas (limitação
                          conhecida da ferramenta, mesma ressalva já documentada em supabase/tests/README.md
                          para outras features). Ver LIMITAÇÕES.
FRONTEND                = OK, com 1 achado corrigido em runtime (ver ACHADOS) — Excluir/Cancelar/Restaurar OS
                          testados de ponta a ponta no browser real (não só pela API): menu "⋮" dedicado,
                          modais com motivo obrigatório e resumo de consequências, badges de excluída/cancelada
                          com motivo/quem/quando, filtro "Mostrar excluídas" na listagem. O filtro de status
                          (Select "Ativas/Concluídas/Canceladas") não pôde ser exercitado por clique real nesta
                          sessão — ver LIMITAÇÕES (é lógica puramente client-side, sem risco de segurança).
PGTAP                   = OK — 50/50 novas asserções verdes (supabase/tests/090_cancelamento_os.sql).
REGRESSÃO               = OK — 010 a 080 (84 asserções) permanecem 100% verdes após as 4 migrations.
```

---

## Migrations criadas

1. `supabase/migrations/20260818170000_p2d_os_exclusao_logica.sql` — colunas `deleted_at/deleted_by/deleted_reason`; RLS `os_select_autenticado` ganha guarda de `deleted_at`; guardas de `deleted_at` em `os_executores_insert_proprio`, `os_checklist_insert_resposta`, `os_checklist_update_resposta`, `rpc_registrar_foto_os`, `rpc_criar_os_adicional`; `rpc_excluir_os_rascunho`; `rpc_restaurar_os_excluida`.
2. `supabase/migrations/20260818170100_p2d_os_cancelamento.sql` — colunas `cancelado_em/cancelado_por/cancelamento_motivo`; helper `cancelar_os_adicional_interno` (extraído de `rpc_cancelar_os_adicional`, sem duplicar lógica); `rpc_cancelar_os_adicional` passa a delegar; `rpc_transicionar_os` rejeita `'cancelada'`; `rpc_cancelar_os` (nova, RPC principal da feature).
3. `supabase/migrations/20260818170200_p2d_os_concorrencia_e_correcoes.sql` — `rpc_baixar_peca_os` ganha `for update` (única RPC operacional relevante que não tinha); `estornar_saida_estoque_interno` corrigida para não ressincronizar o item original quando a origem do movimento é uma OS de garantia (bug pré-existente, achado ao desenhar a reversão de garantia).
4. `supabase/migrations/20260818170300_p2d_os_reconversao_apos_exclusao.sql` — achado ao escrever os testes de restauração (ver ACHADOS): `rpc_criar_os` e `rpc_restaurar_os_excluida` passam a ignorar OS soft-deleted no predicado de bloqueio de reconversão (BR-008), que antes só olhava `status <> 'cancelada'`.

## RPCs criadas/alteradas

**Novas:** `rpc_excluir_os_rascunho`, `rpc_restaurar_os_excluida`, `rpc_cancelar_os`, `cancelar_os_adicional_interno` (helper interno, sem gate de perfil próprio).

**Alteradas (corpo majoritariamente reproduzido do original, diff mínimo):** `rpc_transicionar_os` (rejeita `'cancelada'`), `rpc_cancelar_os_adicional` (delega ao helper), `rpc_registrar_foto_os` (+guarda `deleted_at`), `rpc_criar_os_adicional` (+guarda `deleted_at`), `rpc_baixar_peca_os` (+`for update`), `estornar_saida_estoque_interno` (+guarda de garantia), `rpc_criar_os` (+`deleted_at is null` no predicado BR-008).

## Arquivos frontend

- `frontend/src/views/os/OrdemServicoDetalhe.vue` — computeds `podeExcluirOS/podeCancelarOS/podeRestaurarOS/osEhVirgem/osCancelavel`; menu "⋮" (`itensMenuAcoesOS`); dois `Dialog` novos (Excluir/Cancelar, motivo obrigatório, resumo de consequências no de cancelar); badges de excluída/cancelada com motivo/quem/quando; remoção do botão vermelho genérico de `transicoesDisponiveis`.
- `frontend/src/views/os/OrdensServicoList.vue` — filtro de status (Select), checkbox "Mostrar excluídas" (admin), badge "Excluída", menu "⋮" com "Restaurar OS".
- `docs/testing/BUSINESS_RULES.md` — BR-048 a BR-051.
- `supabase/tests/090_cancelamento_os.sql` — novo.

## Testes executados

- **pgTAP `090_cancelamento_os.sql`**: `select plan(50)` → **50/50 ok**, rodado via `npx supabase db query --linked -f` contra DEV/QA (self-rollback, nada persiste). Cobre OS-DEL-001..009 + RBAC + motivo, OS-REST-001..004, OS-CAN-001..009, OS-FIN-CAN-001..004, OS-CONC-001/002.
- **Regressão completa**: `010_seguranca_permissao_anon_bypass` (6/6), `020_estoque` (6/6), `030_orcamento` (4/4), `040_liberacao` (4/4), `050_regressao_garantia` (4/4), `060_contratos_rpc_criticas` (20/20), `070_servicos` (16/16), `080_cancelamento_orcamento` (32/32) — todos verdes após as 4 migrations, nenhuma quebra.
- **Frontend/browser real** (não só API): login como `administrador_tecnico`, criação de OS interna nova, Excluir OS (motivo, navegação de volta pra listagem, RLS escondendo de quem não é admin), "Mostrar excluídas" + badge na listagem, abertura da OS excluída (badge com motivo/por/quando, ações operacionais escondidas), Restaurar OS (ConfirmDialog, volta a aparecer pra todo perfil), transição para `em_diagnostico`, Cancelar OS (motivo, resumo de consequências vazio corretamente quando não há nada a estornar), badge de cancelada com motivo/por/quando, menu "⋮" ausente numa OS já cancelada. `npm run build` limpo, sem erros de console durante toda a sessão.
- **Não executado por clique real**: filtro de status da listagem (Select) — ver LIMITAÇÕES.

## Achados

1. **Bug real corrigido durante a validação em browser**: `osEhVirgem` (frontend) não checava `deleted_at`, então uma OS já excluída (que continua `status='aberta'`) mostrava as duas opções "Excluir OS" **e** "Restaurar OS" simultaneamente no menu. Corrigido (`osEhVirgem` agora exige `!os.value.deleted_at`), revalidado no mesmo browser real — passou a mostrar só "Restaurar OS".
2. **Bug real corrigido antes de qualquer código escrito, achado auditando o schema**: exclusão lógica não mudava `status`, só `deleted_at` — o predicado de bloqueio de reconversão de BR-008 (`rpc_criar_os`) e o espelho em `rpc_restaurar_os_excluida` só olhavam `status <> 'cancelada'`, então excluir uma OS "por engano" **não liberava** o orçamento para nova conversão, contradizendo o propósito da própria exclusão. Corrigido na migration 4, coberto por `OS-REST-004a/b`.
3. **Bug pré-existente, não introduzido por esta feature, achado ao desenhar a reversão de garantia**: `estornar_saida_estoque_interno` resincronizava `execucao_status` do item ORIGINAL (de outra OS) usando o ledger de uma OS de garantia, quando o movimento estornado vinha de uma baixa de garantia. `rpc_baixar_peca_os` já tinha essa consciência (pula o sync no ramo de garantia); o estorno nunca ganhou a mesma guarda. Já era alcançável hoje (cancelamento de garantia em `em_diagnostico` via `rpc_transicionar_os` antigo); corrigido junto por estar diretamente implicado pela ampliação do escopo de cancelamento.
4. **Achado de design, não bug**: `rpc_baixar_peca_os` era a única RPC operacional relevante sem `for update` (todas as outras já tinham). Corrigido — sem isso, uma baixa concorrente com `rpc_cancelar_os` poderia escapar do estorno.
5. Confirmado por leitura direta do código (não assumido): `rpc_cancelar_cobranca` exige perfil `suporte_administrativo`/`administrador_tecnico`, diferente do gate de `rpc_cancelar_os` (`encarregado`/`administrador_tecnico`) — reforça a decisão de nunca auto-cancelar cobrança dentro do cancelamento de OS.

## Limitações

1. **Concorrência real (duas sessões HTTP simultâneas)**: não testada — pgTAP roda numa única sessão/transação. O `for update` garante a serialização correta no banco (mecanismo verificado por leitura de código), mas a demonstração automatizada é só do invariante de estado final via ordens de execução sequenciais (`OS-CONC-001/002`), mesma limitação já documentada para outras features em `supabase/tests/README.md`. Uma prova de contenção real exigiria um script HTTP dedicado (mesmo padrão de `docs/testing/scripts/etapa7_concorrencia_*.sh`), não incluído nesta rodada.
2. **Filtro de status da listagem (`OrdensServicoList.vue`) não testado por clique real no browser**: o ambiente de Browser pane desta sessão apresentou uma dificuldade específica e reprodutível em interagir com o overlay do componente PrimeVue `Select` (clique por coordenada, clique via DOM direto em `<li>`/`<span>` com sequência completa de eventos de mouse, e navegação por teclado — nenhum método fez o valor mudar, enquanto o mesmo tipo de interação funcionou normalmente para o `Menu` de ações, `Checkbox` "Mostrar excluídas" e diálogos). O checkbox "Mostrar excluídas" (mesmo arquivo, lógica de filtro client-side irmã) foi testado com sucesso e funcionou corretamente, o que dá confiança indireta de que a infraestrutura geral do arquivo está correta. A lógica do filtro (`ordensFiltradas`) foi revisada por leitura de código e é puramente client-side, sem RPC nem risco de segurança — não bloqueia a promoção da feature, mas fica registrado como não verificado por clique real e deve ser conferido manualmente pelo usuário antes de considerar a tela 100% validada visualmente.
3. **Cobrança "aberta sem pagamento" bloqueando cancelamento**: por decisão deliberada (não um gap), `rpc_cancelar_os` nunca cancela a cobrança automaticamente — exige que o usuário cancele a cobrança primeiro (fluxo já existente, `rpc_cancelar_cobranca`), e só então cancele a OS. Testado (`OS-FIN-CAN-002/004`), mas é um fluxo em duas etapas manuais, não uma automação de ponta a ponta.

---

## Próximas ações

1. Revisão/aprovação deste relatório pelo usuário.
2. Validação manual do filtro de status na listagem (item 2 de LIMITAÇÕES).
3. Homologação formal em DEV/QA (fora do escopo desta sessão de implementação).
4. ~~Autorização explícita do usuário antes de promover qualquer migration para produção~~ — **feito em caráter emergencial em 2026-08-19**, ver atualização no topo deste relatório e `docs/ENVIRONMENTS.md`.
5. **Novo, decorrente do incidente:** avaliar o risco estrutural do pipeline de deploy (`.github/workflows/deploy.yml` publica qualquer coisa que chegue em `main` sem checar se o schema de produção está em dia) — ver seção "Promoção emergencial" em `docs/ENVIRONMENTS.md`.
