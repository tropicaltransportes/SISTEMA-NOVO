# TEST_REPORT_P1C.md — ETAPA 6 (P1-C) — Consolidação Funcional do ERP Oficina

Continuação de `TEST_REPORT_P1B.md` (preservado intacto, não editado). Esta
etapa resolve as 15 funcionalidades `NÃO_IMPLEMENTADO` e formaliza as 9
`PENDENTE_DECISÃO` que restavam ao final do P1-B, sem integrações
fiscais/bancárias externas (fora de escopo por decisão explícita).

Todos os 6 relatórios anteriores (`TEST_REPORT.md`, `TEST_REPORT_EXECUTION_02.md`,
`TEST_REPORT_EXECUTION_03.md`, `TEST_REPORT_P1A.md`, `TEST_REPORT_P1B.md`,
`TEST_MATRIX.md`) permanecem intactos — nenhum foi editado nesta rodada.

---

## 1. Resumo executivo

Contagem recalculada ID por ID a partir dos 176 casos de `TEST_MATRIX.md`
(não copiada de relatórios anteriores — ver seção 9 para a tabela completa).

| Métrica | Valor |
|---|---|
| **TOTAL** | **176** |
| **EXECUTADOS REALMENTE nesta rodada** (novos + reconfirmados) | **35** (24 que mudaram de status + 11 IDs cuja RPC subjacente foi alterada e foram reconfirmados) |
| **PASSOU** | **171** |
| **FALHOU** | **1** (AUT-007 — risco aceito, inalterado, documentado em `BUSINESS_RULES.md` BR-040) |
| **BLOQUEADO** | **0** |
| **NÃO_IMPLEMENTADO** | **0** (era 15 no início da rodada) |
| **NÃO_AUTOMATIZÁVEL** | **2** (EST-016, GAR-008 — condição de corrida, exige 2 sessões simultâneas, inalterado) |
| **PENDENTE_DECISÃO** | **0** (era 9 no início da rodada) |
| **DECIDIDO — FORA_DO_ESCOPO_ATUAL** (categoria adicional, fora dos 6 status oficiais da matriz, usada só para os 2 itens explicitamente tirados do escopo) | **2** (PEN-004 boleto, PEN-005 emissão fiscal) |

Conferência: 171 + 1 + 0 + 0 + 2 + 0 + 2 = **176**. ✓

| | Início da rodada | Fim da rodada |
|---|---|---|
| **NÃO_IMPLEMENTADO** | 15 | **0** |
| **PENDENTE_DECISÃO** | 9 | **0** (7 viraram PASSOU, 2 viraram DECIDIDO/FORA_DE_ESCOPO) |

| | Valor |
|---|---|
| **FALHAS NOVAS** | 0 |
| **REGRESSÕES ENCONTRADAS** | 1 (real — ver seção 5) |
| **REGRESSÕES RESIDUAIS** | 0 (a única regressão encontrada foi corrigida e reverificada por execução real na mesma rodada) |

O único `FALHOU` que permanece é **AUT-007**, mantido exatamente como
documentado desde o P1-A (risco aceito, não forçado para `PASSOU`).

---

## 2. Migrations novas desta rodada

13 migrations novas, timestamps `20260814110000` a `20260814111200`,
nenhuma migration anterior a `20260813100600` foi editada. Aplicadas com
`npx supabase db push --linked` e confirmadas `local == remote` via
`npx supabase migration list --linked` (**49 migrations no total**, eram 36
ao final do P1-B).

| # | Arquivo | Conteúdo |
|---|---|---|
| 1 | `20260814110000_p1c_config_administrativa.sql` | `custo_hora_config`, `desconto_config`, `centro_custo`, `anexos_config` — configuração administrativa versionada (histórico append-only) |
| 2 | `20260814110100_p1c_prazo_os.sql` | `previsao_conclusao` + `os_prazo_historico`, `rpc_definir_previsao_conclusao` (Decisão 3) |
| 3 | `20260814110200_p1c_desconto_orcamento.sql` | Desconto estruturado no orçamento, rateio proporcional por item, `rpc_aplicar_desconto_orcamento`, `rpc_criar_cobranca` passa a somar `valor_liquido` (Decisão 7) |
| 4 | `20260814110300_p1c_fotos_os.sql` | Bucket `os-fotos`, tabela `os_fotos`, `rpc_registrar_foto_os` (valida metadados reais do Storage), obrigatoriedade por `checklist_templates` (Decisão 6) |
| 5 | `20260814110400_p1c_concluir_os_fotos.sql` | `rpc_concluir_os` valida obrigatoriedade de foto + dispara snapshot de custo interno |
| 6 | `20260814110500_p1c_cliente_interno_custo.sql` | Colunas de custo em `ordens_servico`, `rpc_definir_centro_custo_os`, `calcular_e_snapshot_custo_interno_os` (Decisão 1/2) |
| 7 | `20260814110600_p1c_garantia_adicional_fix.sql` | `os_garantia_itens` aceita item original OU de adicional (CHECK mutuamente exclusivo), `rpc_criar_os_garantia` estendida, `rpc_baixar_peca_os` reescrita (reintroduz ramo de garantia perdido no P1-B) |
| 8 | `20260814110700_p1c_executor_remocao.sql` | `os_executores` ganha `ativo`/`removido_por`/`removido_em`/`motivo_remocao`, `rpc_remover_executor_os` (item 8) |
| 9 | `20260814110800_p1c_cancelamento_item_aprovado.sql` | Guarda contra cancelar item já executado, `rpc_criar_cobranca` exclui item cancelado (item 11) |
| 10 | `20260814110900_p1c_termo_ciencia_extensao.sql` | `termos_ciencia_debito` estruturado (Decisão 8) |
| 11 | `20260814111000_p1c_relatorios.sql` | RPCs de leitura: `rpc_dados_pdf_orcamento`, `rpc_relatorio_encerramento_os`, `rpc_relatorio_garantia_os`, `rpc_historico_veiculo` |
| 12 | `20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql` | **Migration corretiva** — corrige bug real (ver seção 5) |
| 13 | `20260814111200_p1c_fix_msg_teto_desconto.sql` | **Migration corretiva** — corrige mensagem de erro malformada |

---

## 3. Decisões de negócio formalizadas (8 decisões, resolvem 9 PENDENTE_DECISÃO)

Texto completo em `docs/testing/BUSINESS_RULES.md`, seção final "Decisões
formalizadas — ETAPA 6 (P1-C)". Resumo:

1. **Cliente interno / OS interna** — nunca gera cobrança; apura custo total (peças + mão de obra). Resolve FIN-010, PEN-001, PEN-002.
2. **Custo da hora interna** — configuração administrativa versionada (`custo_hora_config`), snapshot imutável no momento da conclusão.
3. **Prazo da OS** — manual pelo encarregado, sem faixas automáticas, histórico auditado. Resolve PEN-003.
4. **Boleto** — `DECIDIDO — FORA_DO_ESCOPO_ATUAL`. Resolve PEN-004.
5. **Emissão fiscal/NF** — `DECIDIDO — FORA_DO_ESCOPO_ATUAL`. Resolve PEN-005.
6. **Fotos** — antes/depois, obrigatoriedade configurável por tipo de serviço, nunca global. Resolve PEN-006.
7. **Descontos** — estruturado, teto configurável, rateio proporcional por item, nunca altera silenciosamente orçamento já aprovado. Resolve ORC-007, ORC-008, FIN-003, PEN-007.
8. **Termo de Ciência de Débito** — registro estruturado (cliente, valor reconhecido, responsável, documento, quem registrou). Resolve PEN-008.

---

## 4. E2E interno — cliente interno e custo total (item 16, execução real)

Script: `docs/testing/scripts/etapa6_e2e_interno.sh`. Executado contra o
Supabase real (`jzjbiejmcaygwycvqggm`).

Fluxo: cliente interno `_p1c` → veículo da frota → OS interna (sem
orçamento) → 2 executores (2h + 1h apontadas) → custo/hora configurado a
R$40,00 → peça consumida via adicional técnico aprovado (2un × R$25,00) →
checklist com foto antes/depois **obrigatórias** → tentativa de concluir
sem foto **bloqueada** → fotos enviadas → conclusão → executor2 **removido
formalmente** (histórico preservado) → relatório de encerramento →
histórico do veículo.

**Resultado real, com números exatos:**

```
custo_pecas       = R$ 50,00   (2un × R$ 25,00)
custo_mao_obra    = R$ 120,00  (3h × R$ 40,00)
custo_total       = R$ 170,00  (custo_pecas + custo_mao_obra)
custo_hora_aplicado = R$ 40,00 (snapshot — não recalcula se o valor mudar depois)
```

**Confirmado: NENHUMA cobrança foi criada** para esta OS —
`cobranca_origens?os_id=eq.<OS>` retornou `[]`, e uma tentativa explícita de
`rpc_criar_cobranca` contra essa OS foi bloqueada com
`"Somente OS externa e concluída pode gerar cobrança"`.

Evidência bruta: `docs/testing/scripts/etapa6_e2e_interno.sh` (script) — 3
execuções, a 3ª limpa (as duas primeiras expuseram e corrigiram bugs de
script, não de produção — path duplicado no upload de foto e falta de
sufixo único entre reruns).

---

## 5. E2E externo com desconto (item 17, execução real)

Script: `docs/testing/scripts/etapa6_e2e_externo_desconto.sh`.

Fluxo: orçamento externo com 3 itens (bruto R$300,01) → desconto fixo
R$100,00 autorizado pelo encarregado (bloqueado corretamente acima do teto
de 15% e sem motivo) → rateio proporcional exato por item → envio →
aprovação parcial (item A e C aprovados, item B rejeitado) → tentativa de
alterar desconto pós-decisão **bloqueada** → OS → execução dos itens
aprovados (item B bloqueado) → adicional técnico aprovado e executado
(R$50,00) → 2º adicional aprovado e **cancelado formalmente antes de
executar** (nunca entra na cobrança) → tentativa de cancelar item **já
executado bloqueada** → conclusão → cobrança → Termo de Ciência de Débito
estruturado → liberação → garantia de item de **adicional** → relatório.

**Confirmação matemática, com números exatos:**

```
valor_bruto            = R$ 300,01
desconto_valor          = R$ 100,00  (33,33 + 33,33 + 33,34 — rateio exato, sem sobra de centavo)
valor_liquido            = R$ 200,01
item_A (aprovado, líquido) = R$  66,67
item_B (REJEITADO)          = nunca entra no cálculo
item_C (aprovado, líquido) = R$  66,67
adicional aprovado+executado = R$  50,00
adicional aprovado+CANCELADO = R$  40,00 — nunca entra no cálculo
---------------------------------------------
COBRANÇA FINAL = 66,67 + 66,67 + 50,00 = R$ 183,34  (confirmado via GET direto na cobrança)
```

`valor bruto − desconto válido + adicionais aprovados = valor final
cobrado`: **300,01 − 100,00 + 250,01(itens aprovados brutos incluídos no
líquido)... a fórmula operacional real é `soma(valor_líquido dos itens
aprovados) + soma(itens de adicional aprovados e não cancelados)` = 133,34 +
50,00 = **183,34**, batendo exatamente com o valor da cobrança gerada.
Nenhum item rejeitado ou cancelado entrou no cálculo.

Termo de Ciência registrado com todos os campos estruturados da Decisão 8
(`cliente_id`, `valor_reconhecido=183.34`, `responsavel_nome`,
`responsavel_documento`, `registrado_por`, `observacao`) — confirmado
também na UI (`CobrancasList.vue`, browser real).

### Bugs reais encontrados e corrigidos durante esta execução

1. **`rpc_baixar_peca_os` — regressão real do P1-B, corrigida.** A garantia
   de item de ADICIONAL falhava com `"Item de adicional não pertence a
   esta OS"`. Causa: o ramo "adicional da própria OS" era checado antes do
   ramo "OS de garantia", e os dois usam o mesmo parâmetro
   (`p_os_adicional_item_id`). Além disso, a reescrita do P1-B
   (`20260813100300`, para acrescentar o ramo de adicional) **já havia
   derrubado silenciosamente o ramo de garantia inteiro** (baseado em
   `os_origem_id`, introduzido no P1-A) — ninguém detectou porque a
   suíte de regressão do P1-B não teve um cenário de baixa em OS de
   garantia. Corrigido em `20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql`
   (reordena os ramos, garantia primeiro) e reverificado com sucesso real
   (HTTP 204, movimento de estoque gravado).
2. **Mensagem de erro malformada** em `rpc_aplicar_desconto_orcamento`
   (`%.2f%%` não é suportado pelo `RAISE` do PL/pgSQL — vazava ".2f"
   literal na mensagem). Corrigido em `20260814111200`. Não é regressão
   (função nova desta rodada), só um defeito corrigido antes de fechar a
   rodada.

Evidência bruta: `docs/testing/scripts/etapa6_e2e_externo_desconto.sh` (3
execuções — a 1ª expôs o bug de ordem de ramos, a 2ª expôs o bug de
mensagem, a 3ª ficou limpa, com só os 6 HTTP 400 esperados dos cenários
negativos).

---

## 6. Fotos obrigatórias/opcionais (Decisão 6, item 3)

Demonstrado no E2E interno: checklist com `foto_antes_obrigatoria=true` e
`foto_depois_obrigatoria=true` bloqueou `rpc_concluir_os` com a mensagem
específica de qual foto falta, em cada etapa (sem nenhuma → bloqueia citando
antes; com só antes → bloqueia citando depois; com as duas → concluiu).
Testado também no E2E externo: checklist **sem** obrigatoriedade concluiu
sem nenhuma foto anexada. Complementado com script dedicado
(`etapa6_complementos_exe007_doc002.sh`): path inexistente, arquivo maior
que o limite configurado, executor sem vínculo com a OS e foto de outra OS
— todos bloqueados com mensagem específica.

---

## 7. PDF de orçamento, relatório de encerramento, histórico do veículo, relatório de garantia (browser real)

Verificado no navegador real (dev server Vite, não só por leitura de
código nem só por API) — screenshots de texto capturados via
`get_page_text`, workaround de `.p-datatable-mask` da memória de sessão
aplicado quando necessário:

- **`/orcamentos/:id/pdf`** — orçamento real do E2E externo: bruto
  R$300,01, desconto rateado 33,33/33,33/33,34 por item, líquido R$200,01,
  situação por item (aprovado/aprovado/rejeitado) — tudo batendo com a API.
- **`/os/:id/relatorio-encerramento`** — OS interna real do E2E: custo
  R$170,00 detalhado, 2 executores (um marcado "removido"), checklist,
  2 fotos, adicional aprovado/executado, peça utilizada.
- **`/veiculos/:id/historico`** — veículo real com 4 OS + 1 orçamento,
  navegação para a OS confirmada. Quilometragem documentada como não
  rastreada (nenhuma tabela do sistema guarda odômetro — não inventado).
- **`/os/:id/relatorio-garantia`** — OS de garantia real (item de
  adicional), OS original, prazo de 90 dias, execução realizada.

Regressão de frontend corrigida durante esta verificação: o diálogo de
Termo de Ciência em `CobrancasList.vue` ainda chamava
`rpc_registrar_termo_ciencia` com a assinatura antiga (2 parâmetros) — a
extensão da Decisão 8 tornou `p_responsavel_nome` obrigatório, o que teria
quebrado esse fluxo em produção sem a correção. Corrigido e reverificado no
browser (dialog mostra os campos novos e "Valor reconhecido: R$ 183,34").

---

## 8. Cancelamento de adicional parcialmente decidido (item 11)

Demonstrado no E2E externo:
- item aprovado **ainda não executado** → cancelado formalmente com motivo
  (`rpc_marcar_item_os_adicional_execucao`, status `cancelado`) — nunca
  entra na cobrança.
- item aprovado **já executado** → tentativa de cancelar **bloqueada**
  (`"Item de adicional já executado (executado) não pode ser cancelado"`).
- item ainda pendente de decisão → segue coberto pelo fluxo já existente
  (`rpc_decidir_item_os_adicional` / `rpc_cancelar_os_adicional`).

---

## 9. Tabela completa — 176 IDs (fonte: `TEST_MATRIX.md`, recontados nesta rodada)

Gerada ID por ID a partir dos 176 títulos `##` de `TEST_MATRIX.md` — não
copiada de relatórios anteriores. IDs sem alteração de RPC/schema nesta
rodada mantêm o status consolidado ao final do P1-B (`TEST_REPORT_P1B.md`)
sem terem sido re-executados individualmente agora — isso é declarado
explicitamente na coluna Observação de cada linha, para não mascarar o que
foi e o que não foi re-verificado nesta rodada especificamente.

| ID | Status | Última Execução | Evidência | Observação |
|---|---|---|---|---|
| AUT-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-004 | PASSOU | P1-C (reconfirmado) | Regressao pontual desta rodada: usuario inativo bloqueado em leitura (clientes vazio) e em RPC nova (rpc_criar_centro_custo recusado) — script etapa6_regressao_pontual.sh. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| AUT-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-007 | FALHOU | P1-A | TEST_REPORT_P1A.md secao 3.3 | Risco aceito documentado (JWT stateless do Supabase) — nao corrigido por decisao de escopo, ver BUSINESS_RULES.md BR-040 Decisao #3. |
| AUT-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUT-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-004 | PASSOU | P1-C (reconfirmado) | Regressao pontual: documento duplicado entre 2 clientes ativos bloqueado (409/23505) apos as migrations desta rodada. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| CAD-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-011 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CAD-012 | PASSOU | P1-C | Browser real (VeiculoHistorico.vue) + rpc_historico_veiculo: OS/orcamentos/custo em ordem cronologica, navegacao para a OS confirmada. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| ORC-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-007 | PASSOU | P1-C | E2E externo (item 17): rpc_aplicar_desconto_orcamento aplicado (R$100 fixo sobre bruto R$300.01), rateio exato 33.33/33.33/33.34, total rastreavel (desconto_por/desconto_em/motivo). | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| ORC-008 | PASSOU | P1-C | E2E externo: desconto 20% bloqueado acima do teto (15%), sem motivo bloqueado, executor bloqueado; codigo tambem impede negativo/> bruto. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| ORC-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-011 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-012 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-013 | PASSOU | P1-C | Browser real (OrcamentoPdf.vue) + rpc_dados_pdf_orcamento: documento com empresa/numero/versao/cliente/veiculo/itens/desconto/total/situacao renderizado com dados reais do E2E. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| ORC-014 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-015 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ORC-016 | PASSOU | P1-C (reconfirmado) | Regressao pontual: idempotencia de criacao de orcamento (client_request_id) confirmada — 2a chamada com a mesma chave bloqueada 409. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| APR-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-011 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| APR-012 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-011 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| OS-012 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-004 | PASSOU | P1-C (reconfirmado) | rpc_marcar_item_os_adicional_execucao ganhou guarda nova (item 11). Reconfirmado: decisao de item de adicional (aprovado/rejeitado) funcionando nos dois E2E. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| ADC-005 | PASSOU | P1-C (reconfirmado) | Reconfirmado: item de adicional decidido continua imutavel (nao houve mudanca nesta regra). | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| ADC-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| ADC-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-004 | PASSOU | P1-C (reconfirmado) | rpc_baixar_peca_os reescrita 2x nesta rodada (garantia+adicional). Reconfirmado: baixa de item de orcamento aprovado funcionando (E2E externo, ITEM_A/ITEM_C). | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| EST-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-011 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-012 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-013 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-014 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-015 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EST-016 | NÃO_AUTOMATIZÁVEL | Fase 2 (execucao 02) | TEST_REPORT_EXECUTION_02.md | Exige 2 sessoes simultaneas reais (condicao de corrida) — nao automatizado em nenhuma rodada, inalterado nesta. |
| EXE-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EXE-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EXE-003 | PASSOU | P1-C | E2E interno (item 16): rpc_remover_executor_os encerra participacao do executor2 (ativo=false), apontamento historico (inicio/fim) preservado intacto, motivo/quem/quando registrados. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| EXE-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EXE-005 | PASSOU | P1-C | E2E interno: foto tipo 'antes' enviada ao bucket os-fotos e registrada via rpc_registrar_foto_os (metadados reais do Storage validados). | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| EXE-006 | PASSOU | P1-C | E2E interno: foto tipo 'depois' enviada e registrada; conclusao da OS validou a presenca antes de liberar. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| EXE-007 | PASSOU | P1-C | Complementos (script dedicado): path inexistente bloqueado, MIME nao permitido bloqueado (accidental real no E2E, confirmado), tamanho excedente bloqueado (limite reduzido a 10 bytes so para o teste), executor sem vinculo bloqueado, foto de outra OS bloqueada. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| EXE-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EXE-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| EXE-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CON-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CON-002 | PASSOU | P1-C (reconfirmado) | rpc_concluir_os reescrita 2x nesta rodada (fotos + custo interno). Reconfirmado: bloqueio de itens pendentes/adicional aguardando aprovacao, e obrigatoriedade de foto, em ambos os E2E. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| CON-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CON-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CON-005 | PASSOU | P1-C | Browser real (OsRelatorioEncerramento.vue) + rpc_relatorio_encerramento_os: OS interna real com custo/executores/checklist/fotos/adicionais/pecas exibidos corretamente. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| CON-006 | PASSOU | P1-C | Mesmo relatorio: os 2 executores da OS interna aparecem, um deles marcado 'removido' (EXE-003), confirmando consolidacao de multiplos executores. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| CON-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| CON-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-001 | PASSOU | P1-C (reconfirmado) | rpc_criar_cobranca reescrita 2x nesta rodada (desconto + exclusao de item cancelado). Reconfirmado: cobranca R$183.34 exata no E2E externo. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| FIN-002 | PASSOU | P1-C (reconfirmado) | Mesma rpc_criar_cobranca. Reconfirmado no E2E externo. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| FIN-003 | PASSOU | P1-C | E2E externo: desconto autorizado pelo encarregado flui ate a cobranca (valor_liquido por item), auditoria registrada (evento 'aplicar_desconto'). | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| FIN-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| FIN-010 | PASSOU | P1-C | E2E interno: OS interna concluida sem gerar cobranca (rpc_criar_cobranca bloqueado explicitamente 'Somente OS externa e concluida'). | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| LIB-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-003 | PASSOU | P1-C (reconfirmado) | E2E externo: liberacao bloqueada sem cobranca/termo/pagamento (regra pre-existente, nao alterada) — rpc_liberar_os continua validando; liberado com sucesso apos termo de ciencia estruturado. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| LIB-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| LIB-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| GAR-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| GAR-002 | PASSOU | P1-C (reconfirmado) | rpc_baixar_peca_os ramo garantia. Reconfirmado: OS de garantia aberta dentro do prazo de 90 dias (E2E externo). | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| GAR-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| GAR-004 | PASSOU | P1-C (reconfirmado) | rpc_criar_os_garantia/rpc_baixar_peca_os. Reconfirmado: OS de garantia vinculada a OS original, navegavel (relatorio de garantia, browser real). | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| GAR-005 | PASSOU | P1-C (reconfirmado) | os_garantia_itens/rpc_criar_os_garantia. Reconfirmado: item nao aprovado/nao pertencente a OS original e rejeitado pela validacao (mesma logica do P1-A, agora estendida a itens de adicional). | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| GAR-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| GAR-007 | PASSOU | P1-C | Browser real (OsRelatorioGarantia.vue) + rpc_relatorio_garantia_os: OS de garantia por item de ADICIONAL, OS original, prazo, execucao realizada exibidos com dados reais. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| GAR-008 | NÃO_AUTOMATIZÁVEL | Fase 2 (execucao 02) | TEST_REPORT_EXECUTION_02.md | Exige 2 sessoes simultaneas reais (condicao de corrida) — nao automatizado em nenhuma rodada, inalterado nesta. |
| AUD-001 | PASSOU | P1-C (reconfirmado) | Regressao pontual: tentativa de UPDATE direto em auditoria_eventos bloqueada (403) — append-only preservado. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| AUD-002 | PASSOU | P1-C (reconfirmado) | E2E interno/externo: novos eventos de auditoria (desconto, prazo, custo/hora, remocao de executor, cancelamento de item, termo) gravados via registrar_auditoria — mesma tabela/mecanismo do P1-A, estendido. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| AUD-003 | PASSOU | P1-C (reconfirmado) | Mesma evidencia de AUD-002 — trilha completa dos dois E2E principais. | RPC subjacente alterada nesta rodada — reconfirmado por execucao real (nao so herdado). |
| AUD-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUD-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| AUD-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PER-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| DOC-001 | PASSOU | P1-C | PDF da V1 gerado via rpc_dados_pdf_orcamento contem exatamente a versao correta (versao=1, itens da V1). | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| DOC-002 | PASSOU | P1-C | Complementos: PDF da V1 idem antes/depois de rpc_criar_versao_orcamento criar a V2 (so status muda p/ 'substituido'); PDF da V2 tem dados proprios independentes. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| DOC-003 | PASSOU | P1-C | Mesma evidencia de CON-005 (rpc_relatorio_encerramento_os) — dados de cliente/veiculo/itens/executores/datas conferidos reais. | Era NÃO_IMPLEMENTADO no inicio da rodada — implementado e testado nesta rodada. |
| DOC-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| DOC-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| DOC-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| E2E-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-001 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-002 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-003 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-004 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-005 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-006 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-007 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-008 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-009 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| NFR-010 | PASSOU | P1-B (herdado) | Ver TEST_REPORT_P1B.md (tabela/secoes por ID) ou relatorio de rodada anterior aplicavel | Sem alteracao de RPC/schema nesta rodada — status herdado do consolidado ao final do P1-B, nao re-executado individualmente nesta rodada. |
| PEN-001 | PASSOU | P1-C | Mesma evidencia de FIN-010 — Decisao 1 formalizada em BUSINESS_RULES.md, cobranca_origens vazio para a OS interna. | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| PEN-002 | PASSOU | P1-C | E2E interno: custo_hora_config=R$40,00, 3h apontadas (2 executores), custo_mao_obra=R$120,00 exato, snapshot custo_hora_aplicado gravado. | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| PEN-003 | PASSOU | P1-C | E2E interno e externo: rpc_definir_previsao_conclusao usado em ambos, prazo manual do encarregado com historico auditado (os_prazo_historico). | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| PEN-004 | DECIDIDO_FORA_DE_ESCOPO | P1-C | BUSINESS_RULES.md — Decisoes ETAPA 6 (P1-C) | Fora do escopo atual por decisao explicita do dono do projeto (boleto/emissao fiscal). Nao e mais PENDENTE_DECISAO — decisao formalizada. |
| PEN-005 | DECIDIDO_FORA_DE_ESCOPO | P1-C | BUSINESS_RULES.md — Decisoes ETAPA 6 (P1-C) | Fora do escopo atual por decisao explicita do dono do projeto (boleto/emissao fiscal). Nao e mais PENDENTE_DECISAO — decisao formalizada. |
| PEN-006 | PASSOU | P1-C | E2E interno: checklist com foto_antes/foto_depois_obrigatoria=true bloqueou conclusao ate as duas fotos existirem; E2E externo usou checklist sem obrigatoriedade e concluiu sem foto. | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| PEN-007 | PASSOU | P1-C | E2E externo: desconto_config (teto percentual) bloqueou desconto acima do limite; ORC-007/ORC-008/FIN-003 mesma evidencia. | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |
| PEN-008 | PASSOU | P1-C | E2E externo + browser real (dialogo Termo em CobrancasList.vue): termo com cliente_id/valor_reconhecido/responsavel_nome/documento/registrado_por/observacao gravados e exibidos. | Era PENDENTE_DECISAO no inicio da rodada — decisao formalizada em BUSINESS_RULES.md e implementada/testada nesta rodada. |

---

## 10. Regressão (item 18)

pgTAP (`supabase/tests/*.sql`) **não pôde ser executado** nesta rodada —
`npx supabase test db --linked` exige Docker local
(`LegacyDockerRunError: failed to run docker`), indisponível neste
ambiente — mesma limitação já registrada em rodadas anteriores. Cobertura
de regressão real feita via REST direta (mesmo padrão dos scripts
`etapa3_*`/`etapa4_*`/`etapa5_*`):

- `docs/testing/scripts/etapa6_regressao_pontual.sh` — AUT-004 (usuário
  inativo bloqueado em leitura e em RPC nova), CAD-004 (documento
  duplicado entre clientes ativos), ORC-016 (idempotência de criação de
  orçamento), BR-027 (auditoria append-only, UPDATE direto bloqueado
  403), validação de `rpc_liberar_os`. **Nenhuma regressão encontrada.**
- Os dois E2E principais (seções 4 e 5) exercitaram de ponta a ponta todas
  as RPCs reescritas nesta rodada (`rpc_baixar_peca_os`, `rpc_concluir_os`,
  `rpc_criar_cobranca`, `rpc_marcar_item_orcamento_execucao`,
  `rpc_marcar_item_os_adicional_execucao`, `rpc_criar_os_garantia`),
  confirmando que os comportamentos de EST-004, CON-002, FIN-001/002,
  ADC-004/005, GAR-002/004/005 continuam corretos.
- 1 regressão real foi encontrada e corrigida (seção 5, item 1) — não é
  residual: reverificada com sucesso na mesma rodada.

**FALHAS NOVAS = 0. REGRESSÕES ENCONTRADAS = 1. REGRESSÕES RESIDUAIS = 0.**

---

## 11. RBAC (item 12)

`frontend/src/lib/permissoes.js` ganhou constantes para: configuração de
custo/hora e teto de desconto (só `administrador_tecnico`), centro de
custo, prazo, desconto (encarregado/admin técnico), fotos (executor
restrito à própria OS + gestão), garantia de adicional, remoção de
executor, cancelamento formal de item aprovado, termo de ciência,
relatórios. Backend continua sendo a autoridade final — todas as RPCs
novas usam `tem_perfil()`, testado via API direta nos dois E2E (ex.:
executor tentando aplicar desconto bloqueado, executor sem vínculo à OS
tentando anexar foto bloqueado).

---

## 12. Fora de escopo (confirmado, não implementado)

Integrações fiscais/bancárias externas (boleto real, NF real de venda) —
`DECIDIDO — FORA_DO_ESCOPO_ATUAL`, ver seção 3, decisões 4 e 5. Nenhum
mock, tabela fictícia ou código incompleto foi criado para esses dois
itens.

---

## 13. Arquivos desta rodada

**Migrations (13):** `supabase/migrations/20260814110000` a `20260814111200`.

**Scripts de evidência (5):**
- `docs/testing/scripts/etapa6_e2e_interno.sh`
- `docs/testing/scripts/etapa6_e2e_externo_desconto.sh`
- `docs/testing/scripts/etapa6_regressao_pontual.sh`
- `docs/testing/scripts/etapa6_complementos_exe007_doc002.sh`

**Documentação:**
- `docs/testing/BUSINESS_RULES.md` (8 decisões formalizadas, BR-002/011/018/019/023/024/025/029/036/037/039 atualizadas, BR-041/042 novas)
- `docs/testing/TEST_REPORT_P1C.md` (este arquivo)

**Frontend (9 arquivos):**
- Novos: `frontend/src/views/orcamentos/OrcamentoPdf.vue`,
  `frontend/src/views/os/OsRelatorioEncerramento.vue`,
  `frontend/src/views/os/OsRelatorioGarantia.vue`,
  `frontend/src/views/veiculos/VeiculoHistorico.vue`
- Alterados: `frontend/src/router/index.js`,
  `frontend/src/views/financeiro/CobrancasList.vue` (correção crítica —
  ver seção 7), `frontend/src/views/orcamentos/OrcamentosList.vue`,
  `frontend/src/views/os/OrdemServicoDetalhe.vue`,
  `frontend/src/views/veiculos/VeiculosList.vue`,
  `frontend/src/lib/permissoes.js`

`npm run build` limpo, sem erro. Navegação real confirmada no Browser pane
(seção 7).

---

## 14. Próximas ações priorizadas

1. Nenhum item crítico pendente desta rodada.
2. AUT-007 permanece risco aceito — reavaliar só se o perfil de risco da
   oficina mudar (acesso compartilhado/público a estações de trabalho).
3. Quilometragem do veículo: não existe hoje em nenhuma tabela do sistema;
   se vier a ser necessária para o histórico do veículo (CAD-012), requer
   nova decisão de negócio + campo estruturado — não inventado nesta
   rodada.
4. pgTAP (`supabase/tests/*.sql`) continua não executável neste ambiente
   por falta de Docker — se isso for resolvido futuramente, rodar a suíte
   completa uma vez para fechar a lacuna que a regressão via REST não
   cobre 100% (asserts de estrutura fina de schema, por exemplo).
