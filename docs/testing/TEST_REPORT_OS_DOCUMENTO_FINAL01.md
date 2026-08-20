# TEST_REPORT_OS_DOCUMENTO_FINAL01 — Documento Final da OS (com PDF de valores executados)

**Data:** 2026-08-20 (implementação) / 2026-08-20 (BUG-OS-DOC-02, ver adenda no final)
**Ambiente testado:** DEV/QA (`jzjbiejmcaygwycvqggm`) na implementação original; produção (`wtxbodhqyasdlmyoyjur`) recebeu a migration `20260820190000` na correção do BUG-OS-DOC-02 (adenda abaixo), com autorização explícita do usuário.
**Escopo:** ETAPA DOC-OS-FINAL-01 — documento comercial de conclusão da OS, equivalente em identidade visual ao PDF de orçamento já homologado, mostrando o que foi *efetivamente* executado (não o que foi aprovado).

## Resumo executivo

Implementada uma RPC nova de leitura (`rpc_documento_final_os`), sem tabela nova e sem alteração de regra financeira — todo o modelo de dados já era snapshot-safe (achado confirmado por auditoria antes de implementar, ver seção "Achado de auditoria" abaixo). No frontend, extraídos 5 componentes Vue e 1 módulo de desenho jsPDF compartilhados entre o orçamento e o novo documento, para não duplicar CSS/lógica de desenho (item 37 do pedido) — o PDF do orçamento foi retestado ao vivo depois da extração e não apresentou regressão. Nova view `OsDocumentoFinal.vue` (rota `/os/:id/documento`) com Visualizar/Imprimir/Baixar PDF, acessível pelo menu "⋮" da OS (item "Documento Final") e por um botão "Visualizar OS" no card "Serviço Concluído".

14/14 testes pgTAP novos passaram; suíte de regressão completa (10 arquivos, todas as etapas anteriores) sem nenhuma falha nova. `npm run build` limpo. Testado ao vivo no browser contra dados reais do projeto DEV/QA — cenário externo com peças (achado real, ver abaixo) e cenário interno com custo consolidado.

**Achado durante a implementação, registrado antes de codificar (não mascarado):** o cenário literal do pedido — item aprovado com utilização *parcial* permanecendo assim numa OS concluída ("aprovado 5, utilizado 3, resto dispensado") — **não é alcançável hoje pelo sistema real**: `rpc_concluir_os` bloqueia a conclusão enquanto qualquer item aprovado estiver `parcial`, e a única forma de "fechar" um item (`cancelado`) só é permitida a partir de `pendente` (0% baixado), nunca a partir de `parcial`. Confirmado com o dono do projeto: a RPC do documento já foi construída corretamente (soma real do estoque, nunca a quantidade aprovada), e o gap em si fica registrado como **PENDENTE_DECISÃO** — não foi alterado o módulo de conclusão da OS (mesmo módulo que causou os 2 incidentes de produção anteriores), essa decisão de escopo foi tomada com o usuário antes de implementar.

## Tabela por critério (seção 57 do pedido)

| Critério | Resultado |
|---|---|
| DOCUMENTO | PASSOU — `rpc_documento_final_os` + `OsDocumentoFinal.vue`, disponível a partir de `status='concluida'` |
| SNAPSHOT | PASSOU — DOC-OS-09 (pgTAP): alterar `pecas.custo_medio` após a conclusão não altera o documento já gerado; `orcamento_itens.valor_unitario`/`os_adicional_itens.valor_unitario` nunca fazem join vivo com catálogo (herdado do modelo já existente, confirmado por auditoria) |
| PEÇAS | PASSOU — só peças com quantidade efetivamente baixada (líquido do ledger `estoque_movimentos`, nunca a quantidade aprovada) aparecem (DOC-OS-01/02/04/05/06) |
| MÃO DE OBRA | PASSOU — só itens com `execucao_status='executado'` aparecem (DOC-OS-03/03b/07) |
| ADICIONAIS | PASSOU — incorporados naturalmente às seções Peças/Mão de Obra (nunca uma 3ª tabela separada), mesmos filtros de aprovação/execução do orçamento original (DOC-OS-01/02/05) |
| VALORES | PASSOU — resumo financeiro (Subtotal Peças/Mão de Obra/Valor bruto/Desconto/Acréscimos/VALOR FINAL) calculado com a mesma fórmula de `rpc_criar_cobranca` |
| COBRANÇA | PASSOU — DOC-OS-08: `valor_final` calculado bate exatamente com `cobrancas.valor_total` de uma cobrança real gerada para a mesma OS |
| CLIENTE EXTERNO | PASSOU — testado ao vivo (OS TST0A01, peça R$150) e via pgTAP (peças+mão de obra+adicional, R$2.315, igual ao exemplo do pedido) |
| CLIENTE INTERNO | PASSOU — testado ao vivo (OS P1C1786556981: custo peças R$50 + mão de obra R$80 = R$130, exatamente igual ao já exibido na tela operacional da OS) e via pgTAP (DOC-OS-10/11); nenhuma cobrança fictícia, bloco rotulado "não representa cobrança" |
| GARANTIA | PASSOU (com limitação registrada) — só exibida quando `data_liberacao` existe (90 dias fixos, mesmo literal realmente aplicado por `rpc_criar_os_garantia`); nenhuma OS testada ao vivo já estava liberada, então a seção não pôde ser visualmente confirmada em produção real — validada por leitura de código e pela condição já teoricamente coberta pelo `case when os.data_liberacao is not null` |
| VISUALIZAÇÃO | PASSOU — testado ao vivo, rota `/os/:id/documento` |
| IMPRIMIR | PASSOU — função nomeada no `<script setup>` (nunca `@click` inline); confirmado tanto em dev (`window.print()` de fato chamado) quanto inspecionando o bundle de produção (`dist/assets/OsDocumentoFinal-*.js` contém `window.print` puro, sem o padrão `_ctx.window` que causava o BUG-PDF-PRINT-01 no orçamento) |
| BAIXAR PDF | PASSOU — jsPDF vetorial (`gerarPdfDocumentoFinalOs`), testado ao vivo (clique real, sem erro de console) para os dois cenários (externo/interno); mesma técnica de redesenho do logo em canvas do orçamento (evita o bug real de PDF de 22MB já documentado em BUG_PDF_EXPORT_02_REPORT.md) |
| A4 | PASSOU — mesmo `@page { size: A4 }` e margens do orçamento (CSS compartilhado herdado de `AppShell.vue`) |
| MULTIPÁGINA | NÃO_TESTADO — nenhuma OS com volume suficiente de peças/mão de obra existia nos dados de DEV/QA no momento do teste; a lógica de quebra de página (`garantirEspaco`/`estimarAlturaResumo`) é a mesma já validada no orçamento (PDF-ORC-008, 30 itens), só com constantes recalibradas para a composição de linhas da OS — mesma limitação já conhecida (sem cabeçalho repetido por página) documentada no orçamento |
| LOGO | PASSOU — mesmo componente `BrandLogo`/mesmo PNG redesenhado em canvas, testado ao vivo na tela (visualização) |
| BUILD | PASSOU — `npm run build` limpo, 0 erros |
| REGRESSÃO | PASSOU — 10/10 arquivos pgTAP sem falha nova; PDF de orçamento retestado ao vivo (view + baixar PDF) depois da extração de componentes compartilhados, sem regressão visual ou funcional |

## Backend

**Migration:** `supabase/migrations/20260820190000_p3_doc_os_final01.sql` — `rpc_documento_final_os(p_os_id uuid) returns jsonb`, `language sql stable` (sem `security definer` — mesmo padrão de todas as RPCs de relatório, respeita RLS de cada tabela consultada). Nenhuma tabela nova, nenhuma coluna nova, nenhuma alteração em RPC existente.

Decisões de implementação (todas verificadas contra o código real antes de codificar, não assumidas):
- Quantidade de peça exibida = líquido do ledger `estoque_movimentos` (`saida` − `estorno_saida`), agrupado por `orcamento_item_id`/`os_adicional_item_id` — nunca a coluna `quantidade` (aprovada) do item.
- Mão de obra exibida = `execucao_status='executado'` (não há sinal automático de baixa para mão de obra, é marcação manual via `rpc_marcar_item_orcamento_execucao`/`rpc_marcar_item_os_adicional_execucao`, já existente).
- `valor_final` = Subtotal Peças + Subtotal Mão de Obra − Desconto (rateado, só orçamento) + Acréscimos — algebricamente idêntico à fórmula de `rpc_criar_cobranca` (`sum(valor_liquido)` aprovado-não-cancelado + `sum(valor_total)` de adicional aprovado-não-cancelado + acréscimos), calculado de forma independente para ficar disponível assim que a OS conclui, sem esperar a cobrança existir (decisão confirmada com o usuário — ver plano da etapa).
- Garantia: 90 dias fixos a partir de `data_liberacao` (mesmo literal hardcoded realmente aplicado em `rpc_criar_os_garantia`) — não usa `orcamento_itens.garantia_dias_snapshot`, que a auditoria confirmou ser só metadado decorativo do catálogo, não o que o sistema de fato aplica.
- Cliente interno: reaproveita `ordens_servico.custo_pecas/custo_mao_obra/custo_total`, já congelados por `calcular_e_snapshot_custo_interno_os` na conclusão — nenhum cálculo novo.
- Sem seção "Observações": auditoria confirmou que `ordens_servico` não tem coluna de observação geral — não inventado.

## pgTAP — `supabase/tests/110_documento_final_os.sql`

14/14 assertions, executadas contra DEV/QA via `npx supabase db query --linked -f`:

| # | Caso | Resultado |
|---|---|---|
| DOC-OS-01/02 | Peças mostram só o utilizado (orçamento executado + adicional executado); subtotal 1.765 (1.750+15), igual ao exemplo do pedido | PASSOU |
| DOC-OS-03/03b | Mão de obra mostra só o executado; subtotal 550 | PASSOU |
| DOC-OS-04 | Item de orçamento rejeitado nunca aparece | PASSOU |
| DOC-OS-05 | Item de adicional rejeitado nunca aparece | PASSOU |
| DOC-OS-06 | Item aprovado com **zero** utilizado (nunca baixado) nunca aparece — item 49 do pedido | PASSOU |
| DOC-OS-07 | Serviço aprovado e dispensado (`cancelado`, não `executado`) nunca aparece — item 51 do pedido | PASSOU |
| DOC-OS-08/08b/08c | `valor_final` bate exatamente com `cobrancas.valor_total` de uma cobrança real (item 23 do pedido); = R$ 2.315,00 | PASSOU |
| DOC-OS-09 | Snapshot: mudar `pecas.custo_medio` depois da conclusão não altera o documento — item 52 do pedido | PASSOU |
| DOC-OS-10/11 | Cliente interno: sem bloco de cobrança; `custo_total` reflete o snapshot já calculado | PASSOU |

**Desvio deliberado do exemplo literal do pedido** (registrado no cabeçalho do arquivo de teste): o item 47 pede "5 abraçadeiras aprovadas, 3 efetivamente utilizadas" — como esse estado não é alcançável numa OS realmente concluída (ver "Achado de auditoria" acima), o teste usa 3 aprovadas/3 utilizadas (100%), preservando os mesmos valores finais do exemplo (peças 1.750+15=1.765, mão de obra 550, bruto 2.315). Os casos "aprovado com zero utilizado" (DOC-OS-06) e "aprovado e dispensado" (DOC-OS-07) — que são os que realmente provam que a RPC nunca fatura o que não foi entregue — são plenamente alcançáveis hoje e foram testados normalmente.

**Regressão completa** (todos os 10 arquivos de `supabase/tests/`, incluindo o novo): 0 falhas.

## Frontend

Componentes compartilhados novos (`frontend/src/components/documentos/`): `DocCabecalho.vue`, `DocBlocoClienteVeiculo.vue`, `DocTabelaItens.vue`, `DocResumoFinanceiro.vue`, `DocRodape.vue`. Módulo de desenho jsPDF compartilhado: `frontend/src/lib/pdfDocumento.js`. `OrcamentoPdf.vue` e `pdfOrcamento.js` foram refatorados para consumi-los (nenhum dado/cálculo/regra alterado — só estrutura), e retestados ao vivo depois da mudança.

Novos arquivos específicos da OS: `frontend/src/views/os/OsDocumentoFinal.vue`, `frontend/src/lib/pdfDocumentoFinalOs.js`. Rota `os/:id/documento` (`frontend/src/router/index.js`). Entrada de menu "Documento Final" em `OsCabecalho.vue` (visível em `concluida`/`liberada`/`reaberta_garantia`). Botão "Visualizar OS" adicionado ao card "Serviço Concluído" em `OrdemServicoDetalhe.vue`.

## Verificação ao vivo (browser, DEV/QA)

1. OS externa concluída real (TST0A01/QA01): abriu `/os/:id/documento` a partir do card "Serviço Concluído" e a partir do menu "⋮" → "Documento Final". Peças mostrou 1 item real (3 × R$50 = R$150), Resumo Financeiro bateu (Valor Final R$150,00), sem Mão de Obra (nenhuma vinculada, coerente com a tela operacional), sem Garantia (OS ainda não liberada), sem aviso PrimeUI, sem erro novo de console. "Baixar PDF" clicado sem erro. "Imprimir" confirmado chamando `window.print()` de fato (interceptado via script) e confirmado no bundle de produção que não sofre o bug `_ctx.window` (BUG-PDF-PRINT-01).
2. OS interna concluída real (P1C1786556981): documento mostrou bloco "Custo Interno" (Peças R$50 + Mão de Obra R$80 = R$130), idêntico ao valor já exibido na tela operacional da própria OS; sem bloco de cobrança; aviso "não representa cobrança" visível.
3. Orçamento existente (ORC-f1000000-V1, aprovado, R$500): PDF reaberto depois da extração de componentes — visual e conteúdo idênticos ao esperado (Cliente/Veículo/Peças/Resumo/Condições/Rodapé), "Baixar PDF" sem erro novo de console.

## Pendências / limitações conhecidas (não inventadas, registradas)

- **PENDENTE_DECISÃO**: item aprovado parcialmente executado e formalmente "fechado" preservando a quantidade real (itens 12/24/50 do pedido) não é alcançável hoje via `rpc_concluir_os` — ver "Achado de auditoria" acima. Corrigir isso exigiria tocar o módulo OS-FLOW (já responsável por 2 incidentes de produção); fora de escopo desta etapa por decisão do usuário.
- **NÃO_TESTADO**: cenário multipágina real (muitos itens) — sem fixture de volume suficiente em DEV/QA no momento do teste; lógica reaproveitada da já validada no orçamento.
- Seção "Garantia" não pôde ser confirmada visualmente contra uma OS `liberada` real (nenhuma disponível com dados adequados no momento do teste) — validada por leitura de código/lógica condicional apenas.
- Cabeçalho compacto repetido por página / numeração "Página X/Y" — mesma limitação técnica já documentada no orçamento (CSS puro de impressão do navegador não suporta hoje).
- Nenhuma alteração foi aplicada em produção (`wtxbodhqyasdlmyoyjur`) — migration e testes rodaram só contra DEV/QA, conforme escopo de segurança combinado antes de iniciar (histórico de 3 incidentes de produção pela mesma causa raiz nos últimos 4 dias).

---

## ADENDA — BUG-OS-DOC-02: "rpc_documento_final_os não encontrada no banco"

**Sintoma reportado:** ao abrir o documento final de uma OS, a tela mostrava "Não foi possível carregar o documento desta OS." e o Supabase retornava `PGRST202 — Could not find the function public.rpc_documento_final_os(p_os_id) in the schema cache`.

### CAUSA RAIZ

**Não foi mismatch de assinatura, e não foi cache do PostgREST em DEV/QA (ambos descartados por evidência, não por suposição).** A causa real foi um 4º incidente da mesma cadeia já documentada no projeto (17/08, 19/08, 20/08): o mecanismo de auto-commit/auto-merge deste ambiente commitou (`a0b52b7`, 16:39:18) e mergeou via PR #35 (`b236080`, 16:39:45 — 27s depois) todo o trabalho de DOC-OS-FINAL-01 direto em `main`, sem confirmação explícita nesta conversa. `main` dispara `.github/workflows/deploy.yml` a cada push, **sem nenhum gate de schema/migration** — o frontend novo (incluindo a rota `os-documento-final`) foi automaticamente publicado em `https://tropicaltransportes.github.io/SISTEMA-NOVO/` (confirmado buscando o bundle publicado e achando o chunk `OsDocumentoFinal`/string `os-documento-final` nele). A migration `20260820190000_p3_doc_os_final01.sql`, por decisão de escopo deliberada e registrada nesta mesma etapa, só tinha sido aplicada em DEV/QA — nunca em produção. Resultado: frontend de produção chamando uma RPC que genuinely não existia no banco de produção.

### BANCO CONECTADO / MIGRATION

| | |
|---|---|
| MIGRATION LOCAL | `supabase/migrations/20260820190000_p3_doc_os_final01.sql` — existe no repositório |
| BANCO DEV/QA (`jzjbiejmcaygwycvqggm`) | `20260820190000` aplicada (`local == remote`, confirmado via `supabase migration list`) |
| BANCO DE PRODUÇÃO (`wtxbodhqyasdlmyoyjur`), ANTES da correção | `20260820190000` **ausente** (`remote: ""`) — única migration faltante em toda a lista, nenhuma outra divergência |
| BANCO CONECTADO PELA APLICAÇÃO | `frontend/.env` (dev local) → DEV/QA; `frontend/.env.production` (usado pelo `npm run build` do `deploy.yml`, é o que está publicado) → **produção** — confirmado lendo os dois arquivos e confirmando que o site publicado usa a URL/anon key de produção |

### ASSINATURA FRONTEND vs BANCO

Frontend (`OsDocumentoFinal.vue`): `supabase.rpc('rpc_documento_final_os', { p_os_id: osId.value })`.
Banco (ambos os ambientes, consultado via `pg_get_function_identity_arguments`): `rpc_documento_final_os(p_os_id uuid) returns jsonb`, `security invoker` (`prosecdef = false`).
**Assinaturas idênticas — não houve incompatibilidade de nome de parâmetro.** Confirmado chamando a RPC via PostgREST (mesmo caminho HTTP que o frontend usa, com a anon key) em DEV/QA: `200 null` (sucesso, UUID de teste inexistente). A mesma chamada em produção, antes da correção, devolvia o erro relatado — reproduzindo o bug de forma isolada e definitiva.

### GRANTS

`roles_with_execute: {anon, authenticated, postgres, service_role}` em ambos os ambientes — grants corretos, sem alteração necessária.

### SCHEMA CACHE

**Não foi a causa.** A função nem existia no banco de produção — não havia nada para o PostgREST cachear. Nenhum reload de cache foi necessário; aplicar a migration (que cria a função) já é suficiente, e PostgREST reconheceu a função imediatamente após o `db push` (confirmado pela chamada HTTP seguinte, sem qualquer reload manual).

### TESTE RPC DIRETO

Antes da correção (produção): `curl POST .../rest/v1/rpc/rpc_documento_final_os` com `p_os_id` de teste → `404 PGRST202` (erro idêntico ao relatado pelo usuário).
Depois da correção (produção, mesmo comando): `200 null` — função encontrada e executada com sucesso.

### CORREÇÃO APLICADA

Nenhuma mudança de código. `npx supabase db push --project-ref wtxbodhqyasdlmyoyjur` aplicando exclusivamente `20260820190000_p3_doc_os_final01.sql` (a mesma migration já testada 14/14 em DEV/QA — função nova, sem tabela/coluna/dado alterado), **com autorização explícita do usuário antes de escrever em produção**. `supabase migration list --project-ref wtxbodhqyasdlmyoyjur` confirma `local == remote` em 100% das migrations depois da correção.

Adicionalmente, corrigido um problema real encontrado durante a investigação do item 15 do pedido (não estava relacionado à causa raiz, mas violava a exigência de não expor erro técnico ao usuário): `OsDocumentoFinal.vue` estava passando `error.message` (texto cru do Postgres/PostgREST) para o `toast` de erro. Corrigido para logar o erro completo só no `console.error` e mostrar ao usuário a mesma mensagem genérica já usada no corpo da página; adicionado botão "Tentar novamente" ao estado de erro (sugerido no item 15 do pedido). Verificado ao vivo: UUID inválido → toast e corpo mostram só a mensagem genérica, console mostra o erro técnico completo, "Imprimir"/"Baixar PDF" seguem desabilitados, "Tentar novamente" reexecuta a chamada.

### DOCUMENTO / VALORES / IMPRIMIR / BAIXAR PDF (pós-correção)

Não houve mudança na lógica da RPC nem do frontend além do tratamento de erro acima — os resultados da seção "Verificação ao vivo" mais acima continuam válidos (RPC idêntica, mesma migration, agora também em produção). Confirmado ao vivo em DEV/QA depois do fix de erro: fluxo feliz (peças/mão de obra/resumo financeiro) segue idêntico ao já documentado.

### REGRESSÃO

`npm run build` limpo. Suíte pgTAP completa (11 arquivos, incluindo `110_documento_final_os.sql`) executada de novo contra DEV/QA depois da correção — 0 falhas. `supabase migration list` em produção — 100% sincronizado, nenhuma outra divergência introduzida.

### Risco estrutural (não corrigido nesta etapa, já registrado anteriormente na memória do projeto)

Este é o **4º incidente** com a mesma causa raiz (auto-commit/auto-merge sem confirmação + `deploy.yml` sem gate de schema) em 4 dias corridos (17/08, 19/08, 20/08 ×2). O código da correção deste bug específico está pronto e verificado; o mecanismo que causa a classe inteira de incidentes continua sem gate. Recomendação permanece: construir um gate de CI que bloqueie deploy de frontend quando `supabase migration list` do ambiente de destino mostrar migration pendente, e/ou revisar o hook de auto-commit/merge para não fechar PRs automaticamente sem revisão.
