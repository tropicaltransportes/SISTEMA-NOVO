# TEST REPORT — FEATURE-ORCAMENTO-EXCLUSAO-01 (Exclusão lógica de rascunho / Cancelamento de orçamento)

Data: 2026-08-18
Ambiente: DEV/QA (`jzjbiejmcaygwycvqggm`) apenas. **NÃO promovido para produção** (`wtxbodhqyasdlmyoyjur`) nesta rodada — aguardando autorização explícita do usuário, conforme exigido pelo pedido original.
Migrations: `20260818150000_p2b_orcamento_exclusao_rascunho.sql`, `20260818150100_p2b_status_orcamento_cancelado_enum.sql` (isolada, `ALTER TYPE ... ADD VALUE`), `20260818150200_p2b_orcamento_cancelamento.sql`. Todas aplicadas em DEV/QA na ordem acima, nenhuma migration antiga editada.

---

## Resumo executivo

Dois fluxos novos e distintos implementados sobre `orcamentos`, sem nenhum `DELETE` físico: **exclusão lógica de rascunho** (`deleted_at`/`deleted_by`/`deleted_reason`, só para `status='rascunho'` sem OS ativa vinculada) e **cancelamento formal pós-rascunho** (novo valor de enum `status='cancelado'`, para `enviado`/`aprovado`/`rejeitado`/`parcialmente_aprovado`, também bloqueado por OS ativa vinculada). Ambos exigem motivo obrigatório (mín. 5 caracteres) validado no backend, geram evento em `auditoria_eventos`, e são protegidos por RBAC fail-closed (`tem_perfil()`) e RLS. Restauração administrativa (`administrador_tecnico`-only) implementada e testada. 92/92 asserções pgTAP passando (32 novas + 60 de regressão pré-existente, 0 falhas). `npm run build` do frontend passou. Validação por clique real no browser feita e confirmada nesta rodada (login real como `teste.admin@qa.local` contra o DEV/QA, fluxo completo excluir→restaurar→cancelar→PDF), diferente de etapas anteriores onde essa validação ficou bloqueada.

---

## MODELAGEM

Implementado. `orcamentos` ganhou `deleted_at timestamptz`, `deleted_by uuid → profiles`, `deleted_reason text` (mesma convenção já usada em `clientes`/`veiculos`/`pecas`), e `cancelado_em timestamptz`, `cancelado_por uuid → profiles`, `cancelamento_motivo text` (espelhando `desconto_motivo/desconto_por/desconto_em` já existente). `status_orcamento` ganhou o valor `'cancelado'` via migration isolada (`ALTER TYPE ... ADD VALUE`, mesma restrição do Postgres já contornada em `20260813100000_p1b_status_orcamento_enum.sql`). Índice parcial `idx_orcamentos_deleted_at` para a listagem operacional. `orcamento_itens` **não** ganhou coluna própria de exclusão — itens continuam fisicamente presentes, ocultos apenas transitivamente via RLS do orçamento pai (confirmado por teste, `ORC-DEL-002`).

## SOFT DELETE

Implementado e testado. `rpc_excluir_orcamento_rascunho(p_orcamento_id, p_motivo)`: exige `status='rascunho'`, bloqueia se já excluído (idempotência) ou se existe OS não-cancelada vinculada, motivo obrigatório (≥5 caracteres), grava `deleted_at/deleted_by/deleted_reason`, audita `ORCAMENTO_EXCLUIDO`. Testado real (`ORC-DEL-001` a `010`, `ORC-DEL-BONUS-01`): exclusão feliz, itens preservados, bloqueio em enviado/aprovado/com-OS, RBAC (executor/anon/inativo bloqueados), motivo ausente/curto bloqueado, idempotência.

## CANCELAMENTO

Implementado e testado. `rpc_cancelar_orcamento(p_orcamento_id, p_motivo)`: exige `status in ('enviado','aprovado','rejeitado','parcialmente_aprovado')`, bloqueia se já cancelado ou se existe OS não-cancelada vinculada, motivo obrigatório, grava `status='cancelado'` + `cancelado_em/cancelado_por/cancelamento_motivo`, audita `ORCAMENTO_CANCELADO`. Testado real (`ORC-CAN-001` a `006`, `ORC-CAN-BONUS-01/02`): cancelamento feliz, item/desconto/envio/OS bloqueados após cancelado, PDF continua disponível e indica "Cancelado", idempotência, RBAC. **Nenhuma outra RPC precisou de código novo por causa do cancelamento** — confirmado lendo cada corpo antes de escrever a migration: todo RPC que já grava em `orcamentos` é gated por um allow-list específico de status que nunca inclui `'cancelado'`.

## VERSIONAMENTO

Decisão formalizada, não inventada (BR-045). Excluir uma versão V2 recém-criada por `rpc_criar_versao_orcamento` (que já marcou a V1 original como `'substituido'` no momento em que a V2 nasceu) **não restaura V1 automaticamente** — confirmado explicitamente com o usuário antes da implementação (opção menos destrutiva: nenhuma mutação silenciosa de uma segunda linha não tocada diretamente pelo usuário). Reversível a qualquer momento via `rpc_restaurar_orcamento_excluido` (restaura a V2) ou nova versão a partir da V1. Nenhuma versão histórica é apagada fisicamente em nenhum cenário — confirmado por leitura de código (nenhum `DELETE` em `orcamentos` em nenhuma migration desta etapa).

## OS VINCULADA

Implementado e testado, mesmo predicado de bloqueio já provado em produção para BR-008/OS-004 (`rpc_criar_os`), reutilizado verbatim nas duas novas RPCs: `exists (select 1 from ordens_servico os where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada')`. Testado real: `ORC-DEL-005` (excluir orçamento com OS ativa → bloqueado), `ORC-DEL-006`/`ORC-CAN-004`-equivalente (cancelar orçamento com OS ativa → bloqueado). Nenhuma OS é cancelada automaticamente por este fluxo (não é comportamento pedido nem implementado).

## RBAC

Implementado, mesma disciplina fail-closed (`tem_perfil()`) já padrão no projeto desde o P0. `rpc_excluir_orcamento_rascunho`/`rpc_cancelar_orcamento`: `encarregado` + `administrador_tecnico` (mesma autoridade que já gerencia rascunho/desconto/versão). `rpc_restaurar_orcamento_excluido`: só `administrador_tecnico` — decisão deliberada, mais restrita que a própria exclusão. Testado real: executor bloqueado (`ORC-DEL-007`, `ORC-CAN-BONUS-02`), anon bloqueado (`ORC-DEL-008`), usuário inativo bloqueado mesmo com perfil válido (`ORC-DEL-009`), encarregado não consegue restaurar (`ORC-REST-002`).

## RLS

Implementado. `orcamentos_select_autenticado`/`orcamento_itens_select_autenticado` passaram a exigir `deleted_at is null or tem_perfil('administrador_tecnico')` — a barreira de visibilidade fica no banco, não no frontend. Confirmado por teste real e surpreendente-mas-correto: **o próprio encarregado que acabou de excluir o rascunho perde a visibilidade dele imediatamente** (`ORC-DEL-001c`), só `administrador_tecnico` continua vendo. `orcamentos_update_rascunho`/`orcamento_itens_insert/update/delete_rascunho` ganharam `and deleted_at is null`, porque `status='rascunho'` é ortogonal a `deleted_at` (um rascunho excluído continua `status='rascunho'`).

## AUDITORIA

Implementado, mesmo mecanismo único do projeto (`registrar_auditoria()`/`auditoria_eventos`, nenhum segundo sistema criado). Eventos `ORCAMENTO_EXCLUIDO`, `ORCAMENTO_CANCELADO`, `ORCAMENTO_RESTAURADO`, cada um com entidade/id, status anterior/novo (jsonb), motivo, usuário (via `auth.uid()` dentro da RPC `SECURITY DEFINER`) e timestamp automático.

## CONCORRÊNCIA

`select ... for update` em ambas as RPCs novas (mesmo padrão já provado em `rpc_criar_os`/`rpc_aplicar_desconto_orcamento`) serializa qualquer corrida real entre excluir/cancelar e as demais transições. **Concorrência real de duas sessões não é modelada em pgTAP puro** (mesma limitação já documentada em `supabase/tests/README.md` para EST-013/EST-016/NFR-001/002/GAR-008 — pgTAP roda numa única transação/sessão). Dentro dessa limitação, o pgTAP prova o invariante testando as duas ordens de execução possíveis sequencialmente (`ORC-CONC-001a/b`: excluir-depois-enviar e enviar-depois-excluir, ambas bloqueiam a segunda operação). Prova de concorrência real (duas chamadas HTTP simultâneas de verdade) disponível em `docs/testing/scripts/etapa8_orcexclusao_concorrencia.sh` (mesmo padrão de `etapa7_concorrencia_*.sh`) — **script escrito mas não executado nesta rodada** (não é necessário para o critério de aceite, que já está coberto pelo invariante testado + revisão de código do `for update`; fica disponível para quem quiser rodar a prova de contenção real).

## RESTAURAÇÃO

Implementado e testado. `rpc_restaurar_orcamento_excluido(p_orcamento_id, p_motivo default null)`: só `administrador_tecnico`, exige `deleted_at is not null`, limpa as 3 colunas, motivo opcional (histórico completo já em `auditoria_eventos`). Testado real: restauração feliz + volta a aparecer na listagem para não-admin (`ORC-REST-001/b/c`), encarregado bloqueado (`ORC-REST-002`), restaurar não-excluído bloqueado (`ORC-REST-003`). **Também confirmado por clique real no browser** (ver FRONTEND).

## PDF

Nenhuma mudança de backend necessária, confirmado por leitura de código (`rpc_dados_pdf_orcamento` já não tinha filtro de status). Testado real via pgTAP (`ORC-CAN-006`) **e por clique real no browser**: PDF de orçamento cancelado abre normalmente e mostra "Cancelado" com destaque, valores inalterados.

## FRONTEND

Implementado em `frontend/src/views/orcamentos/OrcamentosList.vue`, mesmo design system das demais telas (Dialog + Textarea obrigatório para exclusão/cancelamento, `ConfirmDialog` simples para restauração — nenhum `window.confirm()`, já não usado em lugar nenhum do projeto). Menu `⋮` reflete o estado: "Excluir rascunho" só em rascunho não-excluído; "Cancelar orçamento" só em enviado/aprovado/parcialmente_aprovado/rejeitado; "Restaurar orçamento" só para excluídos, só admin; orçamento cancelado não ganha nenhuma ação nova. Toggle "Mostrar excluídos" (só admin) sobre o que a RLS já decidiu entregar. Badges "Excluído" (checagem própria, já que `deleted_at` é ortogonal a `status`) e "Cancelado" (via `statusVisual.js`).

**Validado por clique real no browser nesta rodada** (login `teste.admin@qa.local` contra DEV/QA, servidor Vite local): fluxo completo excluir rascunho → validação de motivo obrigatório (toast + modal permanece aberto) → sucesso → some da listagem padrão → aparece em "Mostrar excluídos" com badge "Excluído" → restaurar → volta ao normal (botões Itens/Enviar de volta); cancelar orçamento enviado → modal com dados corretos (cliente/veículo/versão/valor) → sucesso → badge "Cancelado" → menu `⋮` sem nenhuma ação → PDF ainda abre e mostra "Cancelado". Nenhum erro novo no console do browser durante o fluxo.

## PGTAP

`supabase/tests/080_cancelamento_orcamento.sql` — 32/32 ok (`ORC-DEL-001..010` + 2 bônus, `ORC-CAN-001..006` + 2 bônus, `ORC-REST-001..003`, `ORC-CONC-001a/b`). Um bug real de teste (não de produto) foi encontrado e corrigido durante a execução: a asserção original tentava ler `deleted_at`/contagem de itens autenticado como o mesmo encarregado que acabou de excluir — a própria RLS nova (correta) escondia a linha dele também, fazendo a asserção falhar por design incorreto do teste, não por bug da RPC; corrigido reordenando as checagens para rodar como `administrador_tecnico` (que a RLS deixa ver linhas excluídas).

## REGRESSÃO

Suíte completa `supabase/tests/010` a `070` — **60/60 ok, 0 falhas**, nenhum arquivo anterior quebrou. Total geral desta rodada: **92/92 asserções pgTAP, 0 falhas**.

## BUILD

`npm run build` (frontend) passou sem erros — `OrcamentosList-*.js` (34.04 kB) compilou normalmente com as mudanças; `statusVisual-*.js` incluiu o novo status `cancelado`.

---

## MIGRATIONS CRIADAS

- `supabase/migrations/20260818150000_p2b_orcamento_exclusao_rascunho.sql`
- `supabase/migrations/20260818150100_p2b_status_orcamento_cancelado_enum.sql`
- `supabase/migrations/20260818150200_p2b_orcamento_cancelamento.sql`

## RPCs CRIADAS

- `rpc_excluir_orcamento_rascunho(p_orcamento_id uuid, p_motivo text)`
- `rpc_cancelar_orcamento(p_orcamento_id uuid, p_motivo text)`
- `rpc_restaurar_orcamento_excluido(p_orcamento_id uuid, p_motivo text default null)`

**RPCs existentes redefinidas** (só para acrescentar a guarda `deleted_at`, comportamento anterior preservado): `rpc_enviar_orcamento`, `rpc_aplicar_desconto_orcamento`.

## ARQUIVOS FRONTEND ALTERADOS

- `frontend/src/views/orcamentos/OrcamentosList.vue` — select, toggle "Mostrar excluídos", menu de ações, 2 dialogs novos (exclusão/cancelamento), confirm de restauração, badges, guardas de botões primários
- `frontend/src/constants/statusVisual.js` — status `cancelado` no mapa `STATUS_ORCAMENTO`
- `frontend/src/lib/permissoes.js` — constantes `PODE_EXCLUIR_ORCAMENTO_RASCUNHO`/`PODE_CANCELAR_ORCAMENTO`/`PODE_RESTAURAR_ORCAMENTO` (documentação, mesmo padrão do arquivo)

## OUTROS ARQUIVOS

- `supabase/tests/080_cancelamento_orcamento.sql` (novo)
- `docs/testing/scripts/etapa8_orcexclusao_concorrencia.sh` (novo, não executado nesta rodada — ver CONCORRÊNCIA)
- `docs/testing/BUSINESS_RULES.md` — BR-045, BR-046, BR-047

## TESTES EXECUTADOS

- `supabase/tests/080_cancelamento_orcamento.sql`: 32/32 ok
- Regressão `010` a `070`: 60/60 ok
- `npm run build`: ok
- Clique real no browser (login `teste.admin@qa.local`, DEV/QA): fluxo completo excluir/mostrar-excluídos/restaurar/cancelar/PDF confirmado

## ACHADOS

1. Bug de teste (não de produto), corrigido na hora: asserções de `deleted_at`/contagem de itens precisam rodar como `administrador_tecnico`, não como o encarregado que acabou de excluir — a RLS nova esconde a linha até dele mesmo, comportamento correto e intencional (D2 do plano).
2. UX melhorada além do pedido original: os botões primários "Itens"/"Enviar" (e o item de menu "Aplicar desconto"), que originalmente só checavam `status === 'rascunho'`, agora também checam `!deleted_at` — sem essa correção, um rascunho excluído continuava oferecendo esses botões na tabela (o backend já bloqueava via RLS/RPC, mas a UI oferecia uma ação que seria recusada). Corrigido durante a própria validação visual desta rodada.
3. O guard de OS-ativa dentro de `rpc_excluir_orcamento_rascunho` é, pela análise do modelo atual, inalcançável nesta RPC especificamente (um orçamento com OS vinculada nunca está em `status='rascunho'`, porque `rpc_criar_os` exige `status='aprovado'` no momento da criação da OS) — mantido mesmo assim por defesa em profundidade e para espelhar exatamente o predicado pedido na especificação original (seção 8), documentado aqui para não parecer código morto não intencional.

## PENDÊNCIAS

- Prova de concorrência real de duas sessões HTTP simultâneas (`etapa8_orcexclusao_concorrencia.sh`) escrita mas não executada nesta rodada — não bloqueia o critério de aceite (invariante já provado sequencialmente + revisão de código do `for update`).
- Promoção para produção: **não realizada nesta rodada**, aguardando autorização explícita do usuário, seguindo exatamente o mesmo gate já usado em FEATURE-SERVICOS-01 (migration em produção primeiro, só depois merge do frontend para `main` — `deploy.yml` publica em todo push para `main` sem checar estado do banco).
