# TEST_REPORT_OS_DOCUMENTO_FINAL01 — Documento Final da OS (com PDF de valores executados)

**Data:** 2026-08-20
**Ambiente testado:** DEV/QA (`jzjbiejmcaygwycvqggm`) — nenhuma alteração aplicada em produção (`wtxbodhqyasdlmyoyjur`).
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
