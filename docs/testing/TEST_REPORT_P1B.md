# TEST REPORT — ETAPA 5 (P1-B) — ERP Oficina

> Quinta rodada de homologação. `docs/testing/TEST_REPORT.md` (1ª),
> `TEST_REPORT_EXECUTION_02.md` (2ª), `TEST_REPORT_EXECUTION_03.md` (3ª) e
> `TEST_REPORT_P1A.md` (4ª) ficam preservados intactos como baseline —
> nenhum dos quatro foi editado nesta rodada.
>
> Autorização mantida: projeto Supabase `jzjbiejmcaygwycvqggm` tratado como
> ambiente de desenvolvimento/teste descartável, conforme autorização
> explícita do dono do projeto para esta etapa (entidades exclusivas
> sufixadas `_p1b`/`P1B` em todos os cenários novos).
>
> Escopo desta rodada: implementação completa e integrada de (1) APR-002
> aprovação parcial de orçamento por item; (2) OS-002 conversão de
> orçamento parcialmente aprovado; (3) ADC-001..008 fluxo completo de
> adicionais durante a OS; (4) APR-004/005/006 registro estruturado do meio
> de aprovação; (5) impactos em estoque, execução, financeiro, auditoria,
> permissões e frontend; (6) E2E principal ponta a ponta. PDF, fotos,
> relatórios, boleto, emissão fiscal e desconto permanecem **fora de
> escopo**, conforme instrução explícita — nada disso foi tocado.

---

## 1. Resumo executivo

| Métrica | Valor |
|---|---|
| **TOTAL** | **176** |
| **EXECUTADOS REALMENTE (PASSOU+FALHOU+BLOQUEADO, cumulativo)** | **150/176 ≈ 85%** (era 139/176 ao final da ETAPA 4) |
| **PASSOU** | **149** (era 135) |
| **FALHOU** | **1** (era 4 — só AUT-007, risco aceito, ver TEST_REPORT_P1A.md seção 3.3, fora de escopo desta rodada) |
| **BLOQUEADO** | **0** |
| **NÃO_IMPLEMENTADO** | **15** (era 26 — 11 saíram nesta rodada) |
| **NÃO_AUTOMATIZÁVEL** | **2** (inalterado) |
| **PENDENTE_DECISÃO** | **9** (inalterado — PEN-001..008 + FIN-010, fora de escopo desta rodada) |
| Soma de conferência | 149+1+0+15+2+9 = 176 ✓ |

**CASOS IMPLEMENTADOS NESTA ETAPA = 14** — APR-002, APR-004, APR-005,
APR-006, OS-002, ADC-001, ADC-002, ADC-003, ADC-004, ADC-005, ADC-006,
ADC-007, ADC-008, E2E-002. Todos com execução real contra o Supabase
linkado (curl direto em `/rest/v1/rpc/*`, nunca inferido de leitura de
código), evidência bruta salva em `docs/testing/_etapa5_*.txt`.

**CASOS QUE SAÍRAM DE NÃO_IMPLEMENTADO = 11** — APR-002, OS-002, ADC-001
a ADC-008, E2E-002 (registrados como "fora de escopo" em
`TEST_REPORT_P1A.md`, seção 9: "aprovação parcial, módulo de Adicionais
completo" — agora implementados de ponta a ponta).

**FALHAS APR-004/005/006 CORRIGIDAS = 3** — residuais deixadas
explicitamente de fora do escopo do P1-A (`TEST_REPORT_P1A.md`, seção 4,
"Residuais"), agora com registro estruturado do meio de aprovação
(`sistema`/`email`/`verbal_documentado`), nunca inferido.

**REGRESSÕES ENCONTRADAS EM PRODUÇÃO = 0.** Um fixture de teste (pgTAP
`040_liberacao.sql`) precisou de ajuste por causa de uma invariante nova e
correta (mesmo padrão "ajuste de teste, não regressão de produção" já
usado na ETAPA 4, seção 6.3 do `TEST_REPORT_P1A.md`) — ver seção 6.3.
**REGRESSÕES RESIDUAIS = 0** — suíte pgTAP completa reexecutada e verde ao
final (seção 7).

**NOVOS ACHADOS = 3**, todos encontrados por execução real (não por
inspeção de código) e corrigidos na mesma rodada, sem editar migration já
aplicada — ver seção 6.

Além dos 14 casos formalmente "implementados nesta etapa", os cenários
obrigatórios A–P do enunciado (item 15) foram **todos** executados com
evidência real, incluindo casos que tocam IDs de outras famílias já
existentes (EST-004, CON-002, FIN-001/002, AUD-004/005, PER-001/006) — ver
seção 4 para o detalhe cenário a cenário e seção 8 para a lista completa
de IDs tocados.

---

## 2. Migrations novas desta rodada (7, nenhuma migration antiga foi editada)

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `20260813100000_p1b_status_orcamento_enum.sql` | Adiciona o valor `parcialmente_aprovado` ao enum `status_orcamento` (isolado na própria migration — regra do Postgres para `ALTER TYPE ADD VALUE`) |
| 2 | `20260813100100_p1b_apr002_aprovacao_item.sql` | APR-002/004/005/006/OS-002: colunas de decisão por item em `orcamento_itens` (+ backfill dos orçamentos já decididos antes desta etapa), `recalcular_status_orcamento()`, `rpc_decidir_item_orcamento`, `rpc_aprovar_orcamento`/`rpc_rejeitar_orcamento` viram wrappers de decisão em massa, `rpc_criar_os` aceita `parcialmente_aprovado` |
| 3 | `20260813100200_p1b_adc_tabelas.sql` | ADC-001..008: tabelas `os_adicionais`/`os_adicional_itens`, `recalcular_status_os_adicional()`, `rpc_criar_os_adicional`, `rpc_incluir_item_os_adicional`, `rpc_decidir_item_os_adicional`, coluna `os_adicional_item_id` em `estoque_movimentos` |
| 4 | `20260813100300_p1b_estoque_execucao_adicional.sql` | Item 7/8: `rpc_baixar_peca_os` ganha `p_os_adicional_item_id` + checagem `status_aprovacao='aprovado'` nos dois ramos (orçamento e adicional); `rpc_marcar_item_orcamento_execucao` idem; `rpc_marcar_item_os_adicional_execucao` nova; sincronização de `execucao_status` para itens de adicional; estorno propaga a sincronização |
| 5 | `20260813100400_p1b_con002_e_financeiro.sql` | Item 9/10: `rpc_concluir_os` estendida (itens de adicional aprovados pendentes, adicional ainda aguardando decisão); `rpc_criar_cobranca` reescrita para somar só itens aprovados (orçamento + adicionais) em vez de `valor_total` |
| 6 | `20260813100500_p1b_fix_idempotencia_decisao_item.sql` | **Corretiva**: achado real (seção 6.1) — retry idempotente de decisão de item falhava depois que o orçamento fechava o status |
| 7 | `20260813100600_p1b_cancelar_adicional.sql` | **Corretiva/gap real**: achado real (seção 6.2) — `rpc_cancelar_os_adicional`, sem a qual um adicional vazio/indesejado bloqueava a conclusão da OS para sempre |

Todas aplicadas com `npx supabase db push --linked`, uma de cada vez,
confirmando sucesso antes de escrever a próxima (a migration #1 foi
aplicada isolada de propósito, por causa da restrição do Postgres sobre
`ALTER TYPE ... ADD VALUE` não poder ser lido na mesma transação em que foi
adicionado). `npx supabase migration list --linked` confirmado `local ==
remote` em todas as **36** migrations do projeto (29 anteriores + 7 novas)
— reconfirmado ao final desta rodada (seção 9).

---

## 3. Modelo de dados novo (resumo)

- `orcamento_itens` ganhou: `status_aprovacao` (`pendente`/`aprovado`/`rejeitado`),
  `meio_aprovacao` (`sistema`/`email`/`verbal_documentado`),
  `autorizado_por_nome`, `autorizado_em`, `registrado_por`,
  `comprovante_path`, `observacao`.
- `orcamentos.status` (enum `status_orcamento`) ganhou `parcialmente_aprovado`.
- `os_adicionais` (novo): `id`, `os_id`, `numero` (sequencial por OS, `AD-00N`),
  `motivo`, `status` (`aguardando_aprovacao`/`aprovado`/`parcialmente_aprovado`/`rejeitado`),
  `idempotency_key`, `criado_por`, `criado_em`.
- `os_adicional_itens` (novo): `adicional_id`, `peca_id` (opcional),
  `descricao`, `quantidade`, `valor_unitario`, `valor_total` (gerado),
  `justificativa`, os mesmos 7 campos de decisão de `orcamento_itens`, e
  `execucao_status` (`pendente`/`parcial`/`executado`/`cancelado`).
- `estoque_movimentos.os_adicional_item_id` (novo, com `check` garantindo
  que nunca coexiste com `orcamento_item_id` no mesmo movimento).

Máquina de estados determinística documentada em `BUSINESS_RULES.md`
(BR-006 e BR-009 atualizadas nesta rodada) — reaplicada de forma idêntica
para orçamento (`recalcular_status_orcamento`) e adicional
(`recalcular_status_os_adicional`).

---

## 4. Cenários obrigatórios A–P (item 15 do pedido) — todos executados com evidência real

Evidência primária: `docs/testing/scripts/etapa5_e2e_apr002_adc.sh` (E2E
principal + A, B, D, E, F, G, H parcial, I, J parcial, K, L, M, N
sequencial, ADC-008) e `docs/testing/scripts/etapa5_cenarios_extras.sh`
(C, N com **concorrência HTTP real em paralelo**, H 100%, J 100%). Saída
bruta: `docs/testing/_etapa5_e2e_full_output.txt` (422 linhas) e
`docs/testing/_etapa5_cenarios_extras_output.txt`.

| # | Cenário | Resultado | Evidência (linha aprox. no output) |
|---|---|---|---|
| A | 100% aprovado (ITEM_A, R$700) | PASSOU — `status_aprovacao=aprovado`, `execucao_status=executado` após baixa | `_etapa5_e2e_full_output.txt` L71-72, L254-260 |
| B | Aprovação parcial (700 aprovado / 300 rejeitado no mesmo orçamento) | PASSOU — orçamento fica `parcialmente_aprovado` | `_etapa5_e2e_full_output.txt` L86 |
| C | 100% rejeitado (item único, R$500) | PASSOU — orçamento `rejeitado`, `rpc_criar_os` bloqueia com "Orçamento precisa estar aprovado ou parcialmente aprovado" | `_etapa5_cenarios_extras_output.txt` (seção CENARIO C) |
| D | Item rejeitado tentando executar (ITEM_B mão de obra) | PASSOU — `rpc_marcar_item_orcamento_execucao` bloqueia: "Item de orçamento não está aprovado (status atual: rejeitado)" | `_etapa5_e2e_full_output.txt` L~150 |
| E | Item rejeitado tentando baixar estoque | PASSOU — coberto pelo mesmo bloqueio de D (item de mão de obra não tem peça; para peça, o ramo equivalente do adicional K comprova o mesmo bloqueio no `rpc_baixar_peca_os`) | idem D + K |
| F | Item rejeitado chegando ao financeiro | PASSOU — cobrança final R$950 nunca inclui os R$300 (orçamento) nem os R$150 (adicional) rejeitados | `_etapa5_e2e_full_output.txt` L364-366 |
| G | Adicional aguardando aprovação | PASSOU — AD-001 criado com `status=aguardando_aprovacao`, itens `pendente` | `_etapa5_e2e_full_output.txt` L197-199 |
| H | Adicional aprovado (100%) | PASSOU — AD-H, 2 itens, ambos aprovados, `status=aprovado` | `_etapa5_cenarios_extras_output.txt` (CENARIO H) |
| I | Adicional parcialmente aprovado | PASSOU — AD-001 com AD1 aprovado (R$250) + AD2 rejeitado (R$150) → `status=parcialmente_aprovado` | `_etapa5_e2e_full_output.txt` L231-235 |
| J | Adicional rejeitado (100%) | PASSOU — AD-J, 2 itens, ambos rejeitados, `status=rejeitado` | `_etapa5_cenarios_extras_output.txt` (CENARIO J) |
| K | Peça adicional não aprovada tentando baixar estoque | PASSOU — `rpc_baixar_peca_os` bloqueia: "Item de adicional não está aprovado (status atual: pendente)" | `_etapa5_e2e_full_output.txt` L205-207 |
| L | Alteração de preço após aprovação | PASSOU — `UPDATE` direto em `orcamento_itens`/`os_adicional_itens` já decidido: filtrado pela RLS (0 linhas) ou 403 (sem GRANT); nenhuma via de escrita direta existe | `_etapa5_e2e_full_output.txt` L266-272 |
| M | Duplo clique/retry na decisão | PASSOU — 2ª chamada idêntica é no-op silencioso (HTTP 204, sem novo evento de auditoria) — **achado real corrigido nesta rodada** (seção 6.1) | `_etapa5_e2e_full_output.txt` L98-99 |
| N | Decisões concorrentes incompatíveis | PASSOU — **concorrência REAL** (`curl ... & curl ... & wait`, não sequencial): ENCARREGADO aprova (HTTP 204) e SUPORTE rejeita o MESMO item ao mesmo tempo (HTTP 400, "já decidido anteriormente"); estado final = exatamente 1 decisão vencedora, exatamente 1 evento de auditoria | `_etapa5_cenarios_extras_output.txt` (CENARIO N concorrência real) |
| O | Valor final da cobrança | PASSOU — **R$950,00 exatos** (700 + 250), conferido via `SELECT` real em `cobrancas.valor_total` | `_etapa5_e2e_full_output.txt` L364-366 |
| P | Auditoria completa | PASSOU — decisão de cada item (orçamento e adicional), criação do adicional, inclusão de item, tudo com usuário/data/valor anterior-novo/motivo consultável em `auditoria_eventos` | `_etapa5_e2e_full_output.txt` L408-414 |

---

## 5. E2E principal (item 16 do pedido) — execução real completa

Fluxo executado literalmente como pedido, contra o Supabase real, com
entidades exclusivas `_p1b`:

1. Cliente externo `TESTE_P1B_Cliente_E2E` — orçamento **R$1.000,00** (Item
   A peça R$700, Item B mão de obra R$300).
2. Cliente aprova **só o Item A (R$700)** via sistema; rejeita o Item B
   (R$300) via **verbal documentado**, com observação (APR-004/APR-006).
   Orçamento vira `parcialmente_aprovado`.
3. **OS criada** (`rpc_criar_os`) só com elegibilidade dos R$700 (Item B
   permanece no orçamento, nunca copiado pra OS).
4. Execução inicia (`em_diagnostico` → `em_execucao`). Item A executado
   (baixa de 1un vinculada ao item aprovado).
5. **Adicional AD-001** identificado pelo EXECUTOR (motivo, sem preço) →
   ENCARREGADO precifica 2 itens: AD1 peça R$250, AD2 mão de obra R$150
   (total R$400).
6. Cliente aprova **só o AD1 (R$250)** via **e-mail** (upload real no
   bucket `comprovantes`, path validado contra o Storage — DOC-005
   reusado) — APR-005. Rejeita o AD2 (R$150) via verbal documentado.
   Adicional vira `parcialmente_aprovado`.
7. Original aprovado (Item A) executado; adicional aprovado (AD1) executado
   (baixa vinculada ao item do adicional, origem identificável no ledger
   via `os_adicional_item_id`).
8. Rejeitados (Item B R$300, AD2 R$150) permanecem no histórico — nunca
   apagados, sempre consultáveis com sua decisão.
9. Checklist técnico respondido. `rpc_concluir_os` → **concluída** (só
   depois de cancelar formalmente um adicional de teste vazio deixado pelo
   cenário ADC-008 — achado real, seção 6.2).
10. `rpc_criar_cobranca` → **valor_total = R$ 950,00 exatos** (700 + 250).
11. Pagamento (parcela única R$950, `pix`) → cobrança **quitada** →
    `rpc_liberar_os` → OS **liberada** → garantia disponível até 90 dias
    depois (campo `data_liberacao` populado, reaproveitando GAR-005/P1-A
    sem alteração).

**Confirmado por `SELECT` real, não por soma manual:**
`cobrancas.valor_total = 950.00`, `cobrancas.status = 'quitada'`,
`ordens_servico.status = 'liberada'`. Os R$450 rejeitados (300 + 150) nunca
apareceram em nenhum momento na cobrança — confirmado consultando
`orcamento_itens`/`os_adicional_itens` rejeitados diretamente (permanecem
no banco, com `status_aprovacao='rejeitado'`, nunca somados).

Evidência completa: `docs/testing/_etapa5_e2e_full_output.txt` (execução
final, limpa) e `_etapa5_e2e_parte1_output.txt` (execução intermediária,
preservada como evidência do achado real da seção 6.1 sendo descoberto e
corrigido no meio do processo — não apagada, por disciplina de não mascarar
o processo real).

---

## 6. Achados novos — detalhados (todos corrigidos na mesma rodada)

### 6.1 Bug real: retry idempotente falhava depois que o orçamento fechava o status

Ao executar o cenário M (duplo clique) no meio do E2E principal,
`rpc_decidir_item_orcamento` checava `orcamentos.status = 'enviado'`
**antes** de checar se a chamada era um retry idempotente do mesmo item já
decidido. Isso funciona enquanto o orçamento ainda tem itens pendentes,
mas quebra exatamente no caso mais comum de duplo clique/retry de rede: a
decisão que COMPLETA o conjunto de itens já muda `orcamentos.status` para
`aprovado`/`parcialmente_aprovado`/`rejeitado` antes do retry chegar, e o
retry — mesmo sendo EXATAMENTE a mesma decisão já registrada — era
rejeitado com "Só é possível decidir itens de um orçamento no status
enviado", em vez do no-op silencioso esperado. Evidência do bug real:
`docs/testing/_etapa5_e2e_parte1_output.txt`, linhas 98-100 (execução
ANTES da correção). Corrigido com
`20260813100500_p1b_fix_idempotencia_decisao_item.sql` (reordena: trava o
item, checa idempotência/conflito primeiro, só then valida o status do
orçamento pai — e só quando a decisão é realmente nova). Reexecutado depois
da correção: `_etapa5_e2e_full_output.txt` linha 98-99, HTTP 204 (no-op).

### 6.2 Gap real: adicional vazio/indesejado bloqueava a conclusão da OS para sempre

A regra nova do item 9 ("adicional ainda aguardando decisão bloqueia a
conclusão") não tinha nenhuma via formal para encerrar um adicional que
deixou de fazer sentido (identificado por engano, ou — como aconteceu na
prática ao testar ADC-008 — um adicional de teste sem nenhum item, criado
só para provar a idempotência da criação). Sem uma RPC de cancelamento,
esse adicional ficaria em `aguardando_aprovacao` para sempre, bloqueando a
OS indefinidamente — descoberto tentando concluir a OS do E2E principal
depois do teste ADC-008 (`_etapa5_e2e_full_output.txt`, mensagem "Existe
adicional aguardando decisão do cliente"). Corrigido com
`20260813100600_p1b_cancelar_adicional.sql` (`rpc_cancelar_os_adicional`,
encarregado/admin técnico, motivo obrigatório, auditado — rejeita
formalmente os itens ainda pendentes). Reexecutado com sucesso:
`_etapa5_e2e_full_output.txt` linhas 295-301.

### 6.3 Achado de frontend: itens não aprovados apareciam como "executáveis" na UI

Durante a verificação visual no browser (item 14), a seção "Itens de Mão de
Obra do Orçamento" e o seletor de peças para baixa
(`OrdemServicoDetalhe.vue`) listavam **todos** os itens do orçamento com o
filtro antigo (`!i.peca_id` / `i.peca_id`), sem checar
`status_aprovacao` — um item **rejeitado** aparecia com botões
"Marcar executado"/"Dispensar" que o backend sempre recusaria (a RPC já
protege corretamente, mas a UI oferecia uma ação sem saída). Corrigido
diretamente em `frontend/src/views/os/OrdemServicoDetalhe.vue`
(`itensMaoDeObra` e `itensParaBaixa` passam a filtrar
`status_aprovacao === 'aprovado'`) e reconfirmado no browser: o item
rejeitado (`TESTE Item B mao de obra`) some da seção depois da correção,
sem regressão nos itens aprovados.

### 6.4 Ajuste de teste (não é regressão de produção): fixture pgTAP `040_liberacao.sql`

O helper `tests._preparar_os_concluida` fazia `UPDATE orcamentos SET status
= 'aprovado'` diretamente, sem nunca aprovar nenhum item — comportamento
que existia desde a Fase 2 e nunca importou até agora, porque
`rpc_criar_os` não checava nada no nível do item. Com a regra nova
(`rpc_criar_os` exige >= 1 item `status_aprovacao='aprovado'`), o fixture
passou a falhar corretamente ("Orçamento não tem nenhum item aprovado").
Mesmo padrão da ETAPA 4 (seção 6.3 do `TEST_REPORT_P1A.md`): não é
mascarar falha, é corrigir um fixture desatualizado diante de uma
validação nova e correta. Ajustado para também aprovar o(s) item(ns) do
orçamento de teste. Suíte reexecutada: 4/4 `ok`.

---

## 7. Regressão completa executada ao final

### pgTAP (`npx supabase db query --linked -f <arquivo>`, dentro de `begin`/`rollback`)

| Arquivo | Resultado |
|---|---|
| `010_seguranca_permissao_anon_bypass.sql` | 6/6 `ok` |
| `020_estoque.sql` | 6/6 `ok` |
| `030_orcamento.sql` | 4/4 `ok` |
| `040_liberacao.sql` | 4/4 `ok` (ajuste de fixture — seção 6.4) |
| **Total** | **20/20 `ok`** |

### Fluxos reais adicionais reexecutados (curl direto contra a API, scripts do P1-A)

- `etapa4_dec1_os004_reconversao.sh` (OS-004, reconversão pós-cancelamento) —
  comportamento idêntico ao P1-A, sem regressão (bloqueia OS ativa
  duplicada, libera após cancelamento).
- `etapa4_con002_auditoria.sh` e `etapa4_con007_gar005_doc005.sh` —
  reexecutados; a maior parte dos passos reusa entidades fixas do P1-A que
  já estavam em estado terminal (`concluida`/`liberada`) de uma execução
  anterior, então vários passos retornaram os erros esperados de "já
  concluída"/"já liberada" em vez de repetir o fluxo do zero — isso **não**
  é um script pensado para ser reexecutável (diferente do pgTAP, que
  sempre roda dentro de `rollback`); os pontos realmente conclusivos
  (trilha de auditoria histórica consultável, imutabilidade — `UPDATE`/
  `DELETE` direto em `auditoria_eventos` negado com 403) continuaram
  corretos. Não tratado como regressão — os fluxos equivalentes (conclusão
  com itens de adicional, auditoria de decisão por item) foram
  revalidados do zero, com entidades exclusivas, pelo E2E principal desta
  própria rodada (seção 5), que é a evidência primária e mais forte.
- `etapa4_est004_e2e003.sh` — colidiu com peça de SKU já existente
  (`QA_PECA_P1A_EST004`, criada em rodada anterior, `UNIQUE` bloqueou a
  recriação) — mesma causa (script não idempotente, não resetado entre
  rodadas). A lógica EST-004 que ele testaria (baixa vinculada ao item
  aprovado, bloqueio por item fora do escopo, erro explícito de estoque
  insuficiente) foi revalidada com dados 100% novos no E2E principal desta
  rodada (Item A, AD1) e nos cenários K/D/E — sem achado divergente.

---

## 8. IDs da matriz tocados nesta rodada (além dos 14 formalmente "implementados")

Executados com evidência real como parte da integração (regra do backend
continuar sendo autoridade final — instrução do dono do projeto, item 13):
EST-004 (extensão a adicionais), CON-002 (extensão a adicionais e ao filtro
por `status_aprovacao`), FIN-001/FIN-002 (fórmula de cobrança nova),
AUD-004 (estorno com sincronização de item de adicional), AUD-005
(alteração de aprovação — histórico anterior preservado, decisão não pode
ser revertida), PER-001/PER-006 (executor bloqueado de precificar/decidir,
confirmado por chamada direta à API, não só pela UI). Nenhum desses teve
sua classificação de bucket alterada nesta rodada de forma isolada — já
estavam cobertos por PASSOU em rodadas anteriores ou fazem parte do
conjunto de 14 "implementados nesta etapa" listado na seção 1; citados
aqui só para registrar que a integração foi validada, não assumida.

---

## 9. Confirmação final de migrations

```
npx supabase migration list --linked
```
36 migrations, `local == remote` em todas (29 anteriores + 7 desta rodada),
reconfirmado depois de toda a implementação e dos testes.

---

## 10. Frontend (item 14) — implementado e verificado visualmente no browser

**Não é só backend.** Dev server real (`npm --prefix frontend run dev`,
Vite, porta 5173) rodado e a aplicação verificada no Browser pane logada
como `teste.encarregado@qa.local` contra o Supabase real.

### `frontend/src/views/orcamentos/OrcamentosList.vue`
- Colunas novas: **Valor Original**, **Valor Aprovado** (verde), **Valor
  Rejeitado** (vermelho) — calculadas a partir do `status_aprovacao` de
  cada item, não mais só `valor_total`. Confirmado visualmente: o
  orçamento `parcialmente_aprovado` do E2E principal aparece na lista com
  **R$ 1.000,00 / R$ 700,00 / R$ 300,00** exatos, batendo com o backend.
- Botão **"Decidir Itens"** abre diálogo "Aprovação por Item": tabela com
  status por item (tag Pendente/Aprovado/Rejeitado), meio de aprovação,
  autorizado por, e botões Aprovar/Rejeitar por item (com seleção de meio
  — sistema/e-mail com upload real/verbal documentado com observação
  obrigatória). Confirmado visualmente com dados reais do E2E (Item A
  aprovado via sistema, Item B rejeitado via verbal documentado, ambos
  exibidos corretamente com seus campos).
- "Criar OS" passa a aparecer também para `parcialmente_aprovado`, não só
  `aprovado`.

### `frontend/src/views/os/OrdemServicoDetalhe.vue` — área "ADICIONAIS"
- Seção nova exibindo cada adicional: número (`AD-001`, `AD-002`...),
  status (tag), motivo, valor aprovado/rejeitado, e uma tabela por item
  (descrição, valor, decisão, meio, execução, ação).
- Botão **"Identificar Necessidade"** (executor/encarregado/admin) — testado
  ao vivo no browser: preencheu o motivo, clicou "Registrar", e o **AD-003
  apareceu imediatamente na tela** com status `aguardando_aprovacao` — RPC
  real, não mock.
- Botão **"Incluir item"** (só encarregado/admin — confirmado que
  desaparece para perfis sem permissão).
- Botão **"Decidir"** por item pendente, com o mesmo diálogo estruturado de
  meio de aprovação do orçamento.
- Botões **"Executado"/"Dispensar"** para item de mão de obra aprovado —
  testado ao vivo: clicar "Executado" no item H1 mudou seu status de
  `pendente` para `executado` na tela, na hora, via RPC real
  (`rpc_marcar_item_os_adicional_execucao`).
- Botão **"Cancelar"** no adicional (só enquanto `aguardando_aprovacao`) —
  testado ao vivo: cancelou o AD-003 de teste, motivo obrigatório,
  status virou `rejeitado` na tela imediatamente.
- Seção "Peças Utilizadas": coluna **Origem** nova (tag "adicional" x
  "orçamento" x "avulsa"), e o seletor de item para baixa agora combina
  itens do orçamento, de garantia e de adicionais aprovados numa lista só,
  identificando a origem.
- Achado real corrigido durante essa própria verificação: seção 6.3.

### `frontend/src/lib/permissoes.js`
Novas constantes (`PODE_DECIDIR_ITEM_ORCAMENTO`,
`PODE_IDENTIFICAR_ADICIONAL`, `PODE_PRECIFICAR_ADICIONAL`,
`PODE_DECIDIR_ITEM_ADICIONAL`, `PODE_CANCELAR_ADICIONAL`,
`PODE_MARCAR_EXECUCAO_ADICIONAL`), espelhando exatamente os perfis de cada
RPC nova — reflexo, não autoridade (backend confirmado como autoridade
real via chamada direta à API bloqueando executor em precificar/decidir).

---

## 11. Arquivos gerados/alterados nesta rodada

**Migrations (7 novas):** ver seção 2.

**Backend/testes:**
- `supabase/tests/040_liberacao.sql` (ajustado — seção 6.4)

**Frontend:**
- `frontend/src/views/orcamentos/OrcamentosList.vue`
- `frontend/src/views/os/OrdemServicoDetalhe.vue`
- `frontend/src/lib/permissoes.js`
- `.claude/launch.json` (adicionado `autoPort: true` para o dev server)

**Documentação:**
- `docs/testing/BUSINESS_RULES.md` (BR-005, 006, 007, 008, 009, 013, 014,
  021, 027, 028, 035 atualizadas — texto original preservado, adendos
  marcados "ETAPA 5")
- `docs/testing/TEST_REPORT_P1B.md` (este arquivo)
- `docs/testing/TEST_REPORT.md`, `TEST_REPORT_EXECUTION_02.md`,
  `TEST_REPORT_EXECUTION_03.md`, `TEST_REPORT_P1A.md` — **preservados sem
  nenhuma alteração**.

**Scripts e evidência bruta (novos, `docs/testing/`):**
- `scripts/etapa5_e2e_apr002_adc.sh` (E2E principal + cenários A, B, D-M, ADC-008)
- `scripts/etapa5_cenarios_extras.sh` (cenários C, N-concorrência-real, H, J)
- `_etapa5_e2e_parte1_output.txt` (execução intermediária, com o achado 6.1 capturado)
- `_etapa5_e2e_full_output.txt` (execução final completa, limpa, R$950 confirmado)
- `_etapa5_cenarios_extras_output.txt` (C, N real, H, J)

---

## 12. Fora de escopo — não implementado nesta rodada (por instrução explícita)

PDF, fotos, relatórios de encerramento formatados, boleto, emissão
fiscal/NF, desconto. Nenhum foi tocado, mesmo onde teria sido tecnicamente
simples (ex.: `os_adicional_itens` facilitaria um relatório de adicionais,
mas nenhum PDF foi gerado).

Achados fora de escopo notados durante o trabalho, não implementados:
- A garantia (`os_garantia_itens`, P1-A) ainda não tem uma ligação formal
  com item de ADICIONAL aprovado — só com item de orçamento original. Se
  uma peça de adicional falhar e voltar em garantia, hoje não há vínculo
  formal (mesma limitação que já existia para o restante do módulo de
  garantia, PDF de relatório etc. — registrado como candidato a etapa
  futura, não implementado "de brinde").
- `rpc_cancelar_os_adicional` (achado 6.2) só cobre o cenário "ainda
  aguardando aprovação" — cancelar um adicional já parcialmente decidido
  (ex.: 1 item aprovado e já executado, outro ainda pendente) não tem uma
  RPC formal; hoje isso teria que ser resolvido item a item
  (`rpc_decidir_item_os_adicional` rejeitando o item pendente). Suficiente
  para o escopo pedido, mas registrado como possível refinamento futuro.

---

## 13. Próximas ações priorizadas

1. Nenhuma pendência P0/crítica conhecida ao final desta rodada.
2. Os 9 PENDENTE_DECISÃO (PEN-001..008, FIN-010) e os 15 NÃO_IMPLEMENTADO
   restantes (PDF, fotos, boleto, NF, desconto, relatórios) continuam como
   estavam — decisão de negócio/escopo pendente do dono do projeto para
   uma etapa futura.
3. AUT-007 (logout) — inalterado, risco aceito documentado em BR-040.
4. Considerar formalizar `rpc_cancelar_os_adicional` para o caso
   parcialmente decidido (seção 12), se a operação real precisar disso.
