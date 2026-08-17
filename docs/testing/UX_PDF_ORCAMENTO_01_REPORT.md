# UX-PDF-ORCAMENTO-01 — Redesign comercial do PDF de orçamento

Reformulação visual do documento de orçamento (`frontend/src/views/orcamentos/OrcamentoPdf.vue`),
de aparência de impressão técnica do sistema para proposta comercial. **Só
layout/apresentação** — nenhuma regra de negócio, cálculo, aprovação,
versionamento, permissão ou dado histórico foi alterado. Ambiente: DEV/QA
(`jzjbiejmcaygwycvqggm`) — nenhuma migration nem dado desta etapa foi
aplicado em produção (`wtxbodhqyasdlmyoyjur`) até o momento deste relatório.

## O que mudou, tecnicamente

1. **Migration aditiva** `supabase/migrations/20260818160000_p2c_pdf_orcamento_dados_comerciais.sql`
   — `CREATE OR REPLACE FUNCTION rpc_dados_pdf_orcamento` passa a devolver
   também `cliente.telefone`, `cliente.email` e `itens[].natureza`. Nenhuma
   tabela nova, nenhuma policy nova, nenhuma coluna nova — só expõe colunas
   que já existiam:
   - `orcamento_itens.natureza` é coluna **gerada** desde a
     FEATURE-SERVICOS-01 (`peca` / `servico_cadastrado` / `servico_avulso`,
     derivada de `peca_id`/`servico_id`) — usada para separar PEÇAS de MÃO
     DE OBRA sem nenhuma análise de texto da descrição (item 11 da
     instrução).
   - `clientes.telefone`/`clientes.email` já existiam desde a Fase 1, com a
     mesma RLS de SELECT que já liberava `nome`/`documento`.
   - Função continua `security invoker` (sem `security definer`) — mesma
     postura de segurança de antes.
2. **Componente reescrito**: `frontend/src/views/orcamentos/OrcamentoPdf.vue`
   (template + estilo). O `carregar()`/chamada à RPC e o mecanismo de
   impressão (`window.print()` + `@media print`) continuam os mesmos.

## LAYOUT
Fundo branco, identidade violeta/grafite, cabeçalho com "ORÇAMENTO" +
código + versão à direita e marca (logo/texto) à esquerda, seções bem
delimitadas (Cliente/Veículo, Peças, Mão de Obra, Resumo Financeiro,
Condições Comerciais, rodapé). Badge "Rascunho" removida; "Situação"
por item removida; valores de aprovado/rejeitado zerados removidos;
horário reduzido a data (`Emissão: 17/08/2026`, sem segundos). Faixa
diagonal discreta "ORÇAMENTO CANCELADO" quando `status = 'cancelado'`
(substitui o badge normal nesse caso, sem duplicar sinalização). Nenhum
coração no rodapé.

## PEÇAS
Seção própria, tabela `Item | Qtde | Valor Unit. | Subtotal`, populada via
`orcamento_itens` filtrado por `natureza = 'peca'`. Some por completo
quando o orçamento não tem nenhum item de peça (testado no cenário
PDF-ORC-002, só mão de obra).

## MÃO DE OBRA
Seção própria, tabela `Serviço | Qtde | Valor Unit. | Subtotal`, populada
por `natureza <> 'peca'` (cobre tanto `servico_cadastrado` quanto
`servico_avulso` — item 11 da instrução: avulso continua pertencendo a
esta seção). Some por completo quando não há item de mão de obra (testado
no cenário PDF-ORC-001, só peças).

## SUBTOTAIS
Cada tabela tem sua própria linha `SUBTOTAL PEÇAS`/`SUBTOTAL MÃO DE OBRA`
no rodapé da tabela, e os mesmos dois valores reaparecem no topo do Resumo
Financeiro. Verificado matematicamente em todos os cenários testados —
exemplo real capturado (PDF-ORC-003): Subtotal Peças R$ 550,00 + Subtotal
Mão de Obra R$ 400,00 = Valor bruto R$ 950,00 = Valor total R$ 950,00
(sem desconto). Cenário com 30 itens (PDF-ORC-008): R$ 1.058,00 +
R$ 558,00 = R$ 1.616,00, batendo exatamente com `valor_bruto`/`valor_total`
devolvidos pelo backend.

## RESUMO FINANCEIRO
Bloco único: Subtotal Peças (se houver) → Subtotal Mão de Obra (se
houver) → Valor bruto → Desconto (se `desconto_valor > 0`, com percentual
e motivo) → **Valor Total** em destaque máximo (maior peso/tamanho de
fonte do documento, cor de acento). **Valor aprovado/Valor rejeitado
removidos** (item 16 da instrução — pertencem ao processo interno de
aprovação, não a este documento). **Acréscimos omitido de propósito**:
`orcamento_acrescimos` é um mecanismo estruturalmente separado
(pós-aprovação, somado só na cobrança via `rpc_criar_cobranca`, nunca no
`valor_total`/`valor_liquido` do próprio orçamento — confirmado lendo
`20260814110200_p1c_desconto_orcamento.sql` e `20260806130100_orcamentos.sql`).
Mostrar uma linha "Acréscimos" aqui seria inventar uma relação que não
existe no modelo atual; testado no cenário PDF-ORC-005 (orçamento com um
`orcamento_acrescimos` de R$ 80 registrado) e o Valor Total do PDF
permanece R$ 500,00, idêntico ao `valor_liquido` do backend — nenhuma
divergência.

## CLIENTE
Nome sempre exibido; Documento/Telefone/E-mail exibidos **somente se
preenchidos** (`v-if` por campo — nenhum texto "Sem documento informado" e
nenhum "—" de preenchimento). Testado com cliente sem documento
(PDF-ORC-007, `TESTE_Cliente_Interno`): linha "Documento" simplesmente não
aparece, enquanto Telefone e E-mail aparecem normalmente.

## VEÍCULO
Placa + prefixo (se houver) em destaque, Modelo/Ano na linha abaixo. Sem
campo adicional inventado (a tabela `veiculos` não tem cor/outros campos
comerciais hoje).

## CONDIÇÕES COMERCIAIS
Duas frases, ambas **derivadas de regra de negócio já formalizada** (não
inventadas):
- Garantia: "Garantia de 90 dias para peças e serviços, conforme regra
  vigente da oficina." — texto de BR-024 (`docs/testing/BUSINESS_RULES.md`),
  mesmo valor de 90 dias já usado como literal em `rpc_criar_os_garantia`.
- Serviços adicionais: "Serviços adicionais identificados após o início da
  execução serão registrados e submetidos à aprovação antes de serem
  realizados." — parafraseia BR-009 em 3ª pessoa (voltada ao cliente) sem
  criar obrigação comercial nova.

**Não incluído** (dado não modelado hoje, não inventado): validade da
proposta, condição de pagamento, prazo estimado de execução. Ver
"Melhorias futuras" abaixo.

## VERSIONAMENTO
Preservado integralmente. Testado com par V1/V2 reais (PDF-ORC-009):
- V1 (`status = 'substituido'`) continua mostrando "Versão 1", preço antigo
  (R$ 220,00) intacto, mesmo depois de V2 existir com preço diferente.
- V2 (`status = 'enviado'`, `orcamento_raiz_id` apontando pra V1) mostra
  "Versão 2", código próprio (`ORC-f100000a-V2`), preço atualizado
  (R$ 260,00).

Nenhuma alteração de preço de catálogo, cliente ou configuração retroage
sobre uma versão já emitida — a RPC só lê o snapshot já gravado em
`orcamento_itens`, sem join vivo com `pecas`/`servicos` (mesma garantia já
documentada na FEATURE-SERVICOS-01).

## PDF MULTIPÁGINA
Testado com 30 itens (18 peças + 12 mão de obra, incluindo uma descrição
propositalmente longa) — documento renderizado com ~2011px de altura de
conteúdo (≈ 2 páginas A4). Regras CSS aplicadas: `@page { size: A4; margin:
14mm 12mm; }` (confirmado presente no stylesheet computado do navegador),
`break-inside: avoid` (+ `page-break-inside` para navegadores mais antigos)
em cada linha de tabela, no bloco Cliente/Veículo, no Resumo Financeiro, em
Condições Comerciais e no rodapé — evita corte de linha/subtotal isolado.
`<thead>` de cada tabela repete nativamente em cada página impressa
(comportamento padrão do navegador, sem JS adicional).

**Limitação assumida, não implementada**: cabeçalho compacto por página
("Tropical Transportes / Orçamento XXXXX / Versão X / Página X/Y") não é
tecnicamente viável com CSS puro sob o mecanismo atual (impressão do
navegador via `window.print()`, sem motor de paginação/contagem de página
dedicado) — registrado como melhoria futura abaixo, conforme a própria
instrução da etapa ("se tecnicamente simples com o mecanismo atual").

## IMPRESSÃO
`@page` com margem A4 confirmado no CSSOM. `.no-print` continua ocultando
os botões de ação (Voltar/Imprimir) na impressão. Nenhuma sidebar, header
do ERP ou elemento de navegação aparece dentro de `.documento-papel` (o
componente é uma rota isolada, sem `AppShell`). Verificado no DOM da
página: nenhum texto contendo "license" é renderizado visualmente na tela
do PDF — o aviso `[PrimeUI] PrimeUI license is not configured.` observado
no console do navegador é emitido pela própria biblioteca PrimeVue 5 em
tempo de execução (não está em nenhum arquivo-fonte do projeto, busca
confirmou isso), aparece globalmente em qualquer tela do app (não é
específico desta página) e é o mesmo item já registrado antes desta etapa
("PrimeVue license banner", pendente de decisão do dono do projeto —
licença vs. downgrade). Como não é visível na tela nem sai na impressão,
não bloqueia o critério de aceite desta etapa, mas continua sendo um item
em aberto separado.

## LOGO
Mecanismo preparado, nenhuma logo fictícia criada. `OrcamentoPdf.vue` usa
`import.meta.glob('../../assets/logo-tropical.*', { eager: true, import:
'default' })` — build passa limpo hoje (glob vazio, sem warning); quando o
arquivo real for adicionado, ele passa a aparecer automaticamente, sem
outra alteração de código. Enquanto isso, o cabeçalho mostra só texto
("Tropical Transportes" / "Oficina Mecânica"), sem monograma nem forma
geométrica no lugar da marca.

- **ARQUIVO ESPERADO** = `frontend/src/assets/logo-tropical.png` (ou
  `.svg`/`.webp`)
- **DIMENSÃO RECOMENDADA** = altura ≈ 96px (proporção livre, exibida a
  44px de altura no cabeçalho)
- **FORMATO** = PNG transparente ou SVG (preferencial)
- **LOCAL DE SUBSTITUIÇÃO** = `frontend/src/assets/` — basta salvar o
  arquivo com esse nome

## DADOS INSTITUCIONAIS AUSENTES
Nenhum CNPJ, endereço, telefone, e-mail ou site institucional foi
inventado. Não existe hoje nenhuma tabela/config de dados da empresa no
banco (`empresa_config` ou equivalente) — o único dado real disponível é o
nome "Tropical Transportes — Oficina Mecânica", hardcoded na própria RPC
desde a etapa anterior (P1-C), inalterado por esta etapa. Ver "Melhorias
futuras".

## BUILD
`npm run build` (dentro de `frontend/`) — sucesso, 0 erros, 0 warnings
relacionados ao componente ou ao mecanismo de logo. Bundle gerado:
`OrcamentoPdf-*.js` (7.62 kB) + `OrcamentoPdf-*.css` (5.32 kB).

## REGRESSÃO
Suíte pgTAP completa executada contra DEV/QA (`npx supabase db query
--linked -f ...`, cada arquivo em `begin;...rollback;`, nenhum dado
residual):

| Arquivo | Resultado |
|---|---|
| `010_seguranca_permissao_anon_bypass.sql` | 6/6 ok |
| `020_estoque.sql` | 6/6 ok |
| `030_orcamento.sql` | 4/4 ok |
| `040_liberacao.sql` | 4/4 ok |
| `050_regressao_garantia.sql` | 4/4 ok |
| `060_contratos_rpc_criticas.sql` | 20/20 ok |
| `070_servicos.sql` | 16/16 ok |
| `080_cancelamento_orcamento.sql` | 32/32 ok |

**92/92 assertions, 0 falhas** — inclui `ORC-CAN-006` (PDF continua
disponível e indica status cancelado), que chama a mesma RPC alterada por
esta etapa. Nenhum valor, snapshot, versionamento, aprovação, item,
desconto ou conversão para OS foi tocado.

## Cenários testados (dados reais em DEV/QA, prefixo `QA_PDF_`)

| ID | Cenário | Orçamento | Resultado |
|---|---|---|---|
| PDF-ORC-001 | Somente peças | `f1000000-…-0001` | Seção Mão de Obra ausente; total R$ 550,00 |
| PDF-ORC-002 | Somente mão de obra | `f1000000-…-0002` | Seção Peças ausente; total R$ 400,00 |
| PDF-ORC-003 | Peças + mão de obra | `f1000000-…-0003` | 550+400=950=bruto=total |
| PDF-ORC-004 | Com desconto | `f1000000-…-0004` | bruto 1.000,00 − desconto 100,00 (10%) = total 900,00 |
| PDF-ORC-005 | Com "acréscimo" (pós-aprovação) | `f1000000-…-0005` | total 500,00, inalterado pelo acréscimo registrado à parte |
| PDF-ORC-006 | Peças + MO + desconto | `f1000000-…-0006` | bruto 500,00 − desconto 50,00 = total 450,00 |
| PDF-ORC-007 | Cliente sem documento | `f1000000-…-0007` | linha Documento ausente; Telefone/E-mail presentes |
| PDF-ORC-008 | Muitos itens (30) | `f1000000-…-0008` | 1.058+558=1.616=bruto=total; ~2 páginas A4 |
| PDF-ORC-009 | Versão histórica (V1/V2) | `f1000000-…-0009` / `f100000a-…-0009` | V1 preserva preço antigo e "Versão 1"; V2 mostra preço novo e "Versão 2" |
| PDF-ORC-010 | Cancelado | `f1000000-…-0010` | Faixa "ORÇAMENTO CANCELADO"; valores preservados, nada recalculado |

Massa de teste deixada em DEV/QA (prefixo `QA_PDF_`, mesmo padrão já usado
pelas rodadas anteriores) para eventual regressão visual futura — nenhuma
foi aplicada ou é aplicável a produção.

## Melhorias futuras não implementadas (registradas, não inventadas)

- **MELHORIA FUTURA — CONFIGURAÇÕES COMERCIAIS**: validade da proposta,
  condição de pagamento e prazo estimado de execução não existem como dado
  estruturado ou configurável hoje; precisam de modelagem própria antes de
  aparecer no PDF.
- **MELHORIA FUTURA — DADOS INSTITUCIONAIS DA EMPRESA**: CNPJ, endereço,
  telefone, e-mail e site da Tropical Transportes não existem em nenhuma
  tabela/config; sugestão de estrutura futura: `empresa_config` (ou
  equivalente) alimentando tanto este PDF quanto outros documentos
  (`OsRelatorioEncerramento.vue`, `OsRelatorioGarantia.vue`).
- **Logo oficial**: aguardando arquivo do dono do projeto — mecanismo já
  preparado (ver seção LOGO).
- **Cabeçalho compacto por página** em documentos multipágina: não viável
  com CSS puro no mecanismo atual de impressão do navegador; exigiria
  motor de paginação dedicado (ex.: biblioteca de geração de PDF no
  cliente), decisão de arquitetura fora do escopo desta etapa.
- **Aviso "PrimeUI license is not configured"**: item pré-existente,
  global ao app, pendente de decisão do dono (licença vs. downgrade do
  PrimeVue) — não específico desta etapa, não bloqueia o critério de
  aceite por não ser visível na tela nem na impressão.

## Status

DEV/QA: migration aplicada, RPC estendida, componente reescrito, 92/92
pgTAP verdes, build limpo, 10/10 cenários validados visualmente com dados
reais. **Não promovido a produção nesta rodada** — aguardando decisão do
dono do projeto para abrir PR/merge/deploy, dado o histórico recente de
merge automático inadvertido (FEATURE-ORCAMENTO-EXCLUSAO-01).

---

## BUG-PDF-PRINT-01 — Botão "Imprimir / PDF" não funcionava

**BUG IMPRESSÃO** = clicar em "Imprimir / PDF" não fazia absolutamente
nada — nenhum diálogo de impressão abria, nenhum erro visível na tela.
Confirmado em produção (build minificado); no servidor de desenvolvimento
(`npm run dev`) o botão funcionava normalmente, o que mascarava o defeito
durante as etapas anteriores.

**CAUSA** = `@click="window.print()"` era um binding **inline no
template**. O compilador do Vue (`<script setup>`, modo *inline
template* — usado só no build de produção; o servidor de desenvolvimento
compila o template separadamente, sem essa otimização, por causa do HMR)
só deixa passar direto identificadores de uma whitelist fixa de globais
(`Infinity,undefined,NaN,isFinite,isNaN,parseFloat,parseInt,
decodeURIComponent,encodeURIComponent,Math,Number,Date,Array,Object,
Boolean,String,RegExp,Map,Set,JSON,Intl,BigInt,console,Error`) —
`window` **não está nela**. Qualquer identificador fora da whitelist e
fora dos bindings do `<script setup>` é reescrito para `_ctx.<nome>`, e
como o componente nunca expôs `window`, `_ctx.window` é `undefined` — a
chamada falhava (`Cannot read properties of undefined`) silenciosamente
sob o gesto de clique, sem deixar rastro visível para o usuário. Causa
confirmada por **inspeção direta do bundle minificado real**
(`dist/assets/OrcamentoPdf-*.js`), não por suposição:

```
// ANTES (bug) — u é o proxy _ctx:
onClick:d[1]||=e=>u.window.print()

// DEPOIS (corrigido) — window puro, dentro de uma função do script:
function je(){if(U.value)try{window.print()}catch(e){console...
```

**ARQUIVO CORRIGIDO** = `frontend/src/views/orcamentos/OrcamentoPdf.vue`
(script e template). Nenhum outro arquivo tinha esse padrão (`grep` por
`window.print()`/`window.location`/`window.` inline em template não
encontrou ocorrência equivalente em outro componente).

**HANDLER** = novo método `imprimir()` declarado no `<script setup>`
(closure JS normal — nunca passa pelo compilador de expressão de
template, então `window` resolve pelo escopo do JavaScript de verdade,
não pela whitelist do Vue):

```js
function imprimir() {
  if (!d.value) return
  try {
    window.print()
  } catch (e) {
    console.error('Falha ao abrir a impressão do orçamento:', e)
    toast.add({ severity: 'error', summary: 'Não foi possível abrir a impressão. Tente novamente.', life: 6000 })
  }
}
```

Botão trocado de `@click="window.print()"` para `@click="imprimir"`, com
`:disabled="carregando || erro || !d"` e `:loading="carregando"` — não é
mais possível clicar antes dos dados carregarem (item 4 da instrução).
Erro não fica mais silencioso: `console.error` + toast visível (item 5) —
sem `catch` vazio.

**WINDOW.PRINT** = chamado de forma **síncrona**, direto no corpo da
função disparada pelo clique — sem `await` antes (item 3 da instrução).
O único `await` do componente (`carregar()`, que busca os dados da RPC)
já roda antes do botão ficar habilitado, então o clique em si nunca
espera nada — preserva o gesto do usuário exigido pelos navegadores para
abrir o diálogo nativo.

**CSS PRINT** = revisado, nenhuma mudança necessária no `@media print` do
próprio documento (já corrigido na etapa UX-PDF-ORCAMENTO-01: `@page`,
`.no-print`, `break-inside/page-break-inside: avoid`). Confirmado de novo
no CSSOM do build de produção: `@page { size: a4; margin: 14mm 12mm; }` e
`.no-print[data-v-…] { display: none !important; }` presentes e corretos.
Também confirmado (herdado da etapa BRAND-01, não desta correção) que
`.sidebar`/`.topbar` do `AppShell.vue` continuam escondidos na impressão
(`display: none !important` dentro de `@media print`).

**A4** = `@page { size: A4; margin: 14mm 12mm; }` confirmado presente e
ativo no CSSOM do build de produção testado.

**MULTIPÁGINA** = inalterado nesta correção — já validado na etapa
UX-PDF-ORCAMENTO-01 (cenário de 30 itens, `break-inside`/
`page-break-inside: avoid` em linhas de tabela, blocos e resumo
financeiro).

**LOGO** = inalterada nesta correção — `BrandLogo` (import estático do
Vite, processado/hasheado no build, nunca path absoluto quebrável — ver
etapa BRAND-01) continua carregando normalmente; confirmado que o clique
corrigido não interfere na logo nem depende dela.

**BUILD** = `npm run build` (modo produção padrão, apontando para o
ambiente configurado em `.env.production`) — limpo, 0 erros. Verificação
da causa e da correção feita com uma segunda build adicional, em
`--mode development` (usa `.env`, que aponta para DEV/QA) só para poder
autenticar com credencial de teste e clicar de verdade **no mesmo modo de
compilação de produção** (minificado, template inline) sem usar
credenciais reais de produção — a variável testada foi o modo de
compilação, não o ambiente de dados.

**TESTE BROWSER** = build de produção (minificado) servido localmente via
`vite preview`, login real (DEV/QA), navegação até o PDF, clique real no
botão:
- Antes da correção: bundle minificado mostrava `u.window.print()` — a
  causa, confirmada por leitura do arquivo, não pelo clique em si.
- Depois da correção: bundle mostra `window.print()` puro dentro da
  função `imprimir`; clique real não gera nenhum erro novo no console
  (`read_console_messages` antes/depois idêntico, sem `TypeError`); botão
  reflete corretamente o estado carregado (`disabled: false` só depois de
  `carregando` terminar). Testado em Chromium (motor do Browser pane usado
  nesta sessão) — Edge/Chromium não foi testado à parte por serem o mesmo
  motor de renderização; sem diferença de comportamento esperada para
  `window.print()`.

**REGRESSÃO** = confirmada sem alteração de dado/cálculo após a correção:
orçamento com peças+mão de obra (`f1000000-…-0003`) continua mostrando
Valor total R$ 950,00, idêntico a antes; versão histórica
(`f1000000-…-0009`) continua mostrando "Versão 1" corretamente; botão
"Voltar" (`router.push('/orcamentos')`, binding que já era uma função do
`<script setup>`, nunca teve esse bug) inalterado.

### Causa raiz, em uma frase

Chamar uma API do navegador (`window`, `document`, `location`, etc.)
direto numa expressão inline do `<template>` de um componente
`<script setup>` é seguro em desenvolvimento mas pode quebrar
silenciosamente em produção — a correção geral é sempre envolver a
chamada numa função declarada no `<script setup>` e usar essa função como
handler, nunca a API do navegador diretamente no template.
