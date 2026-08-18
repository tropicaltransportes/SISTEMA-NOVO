# BUG-PDF-EXPORT-02 — PDF de orçamento sem "casca" de navegador

Separação de **Imprimir** (`window.print()`) e **Baixar PDF** (geração vetorial
direta via jsPDF, sem depender do diálogo de impressão do navegador) no
documento de orçamento, mais refinamento de layout. Ambiente: DEV/QA
(`jzjbiejmcaygwycvqggm`) — nada aplicado em produção (`wtxbodhqyasdlmyoyjur`)
nesta rodada; mudança é 100% frontend, sem migration.

**Nenhum cálculo, regra de negócio, aprovação ou versionamento foi alterado.**
`gerarPdfOrcamento` desenha a partir dos mesmos dados que a tela já carrega de
`rpc_dados_pdf_orcamento` — nenhuma chamada nova ao backend.

## O que mudou

- **`frontend/package.json`** — novas dependências `jspdf` + `jspdf-autotable`
  (únicas libs de PDF no projeto; nenhuma outra existia antes).
- **`frontend/src/lib/pdfOrcamento.js`** (novo) — `gerarPdfOrcamento(d)`
  desenha o documento (cabeçalho com logo, chip de status ou faixa
  "CANCELADO", blocos Cliente/Veículo, tabelas Peças/Mão de Obra via
  `autoTable`, Resumo Financeiro, Condições Comerciais, Rodapé) e
  `nomeArquivoOrcamento(d)` gera `Orcamento_<codigo>_V<versao>.pdf`.
- **`frontend/src/views/orcamentos/OrcamentoPdf.vue`** — botões **Imprimir**
  e **Baixar PDF** distintos; refino de espaçamento (padding 40px→32px,
  vários `margin-bottom` reduzidos); Resumo Financeiro com VALOR TOTAL numa
  caixa destacada (era só 17px, agora 20px + fundo verde-gelo — item
  principal do resumo); rodapé simplificado (removida a frase "Estamos à
  disposição...", identificação em 2 linhas), aplicado igualmente à
  tela/impressão e ao PDF gerado, pra ficarem visualmente consistentes.
- **`frontend/src/layouts/AppShell.vue`** — novo bloco `<style>` (sem
  `scoped`, de propósito — ver nota técnica abaixo) escondendo
  `#p-license-host` e `.p-toast` em `@media print`.
- **`docs/testing/TEST_MATRIX.md` / `TEST_MATRIX_INDEX.csv`** — `DOC-007`.
- **`docs/testing/BUSINESS_RULES.md`** — nota de implementação em BR-041
  documentando os dois mecanismos de emissão (não muda o status DEFINIDA).

### Por que o banner de licença precisou de CSS fora de `<style scoped>`

Confirmado ao vivo: `#p-license-host` (o host do banner "Invalid PrimeUI
License") é injetado pelo PrimeVue direto em `document.body`, **fora** de
qualquer árvore Vue — nunca recebe o atributo `data-v-*` que o
`<style scoped>` do `OrcamentoPdf.vue` ou do `AppShell.vue` dependeria pra
alcançá-lo. O mesmo vale pro Toast (`.p-toast`, declarado em `App.vue`,
teleportado pro `body`). Por isso o `<style scoped>` original do
`AppShell.vue` (planejado inicialmente) não teria efeito nenhum — precisou
de um segundo bloco `<style>` genuinamente global. **Isso esconde os dois
elementos só na impressão** (mesma categoria de já esconder sidebar/topbar
ali do lado) — **não desliga, não mascara e não contorna o mecanismo de
licença do PrimeVue na tela do app**; o banner continua aparecendo
normalmente pra quem usa o sistema. Decisão de não mexer na licença em si
foi tomada explicitamente com o usuário antes de começar esta tarefa.

## Bugs reais encontrados e corrigidos durante a verificação

Nenhum destes constava no pedido original — foram achados testando de
verdade, não suposição, e corrigidos na hora por bloquearem os próprios
critérios de aceite do pedido (item 2 e item 9/PDF-EXP-008):

1. **PDF de 22MB por causa do logo.** `tropical-logo-horizontal-light.png`
   é 5338×1034px (pensado pra tela, não pra um elemento de ~10mm no PDF).
   Passado direto pro `jsPDF.addImage`, o PNG caiu no fallback de embutir
   bitmap cru (RGB + canal alfa/SMask separado, nenhum comprimido) — um PDF
   de teste de 30 itens chegou a 22.126.505 bytes. Corrigido redesenhando o
   logo num `<canvas>` de 300px de altura antes de gerar o data URL (mais
   `compression: 'MEDIUM'` no `addImage` como defesa extra). O mesmo PDF
   depois da correção: **95.394 bytes** (redução de ~232x).
2. **Rótulo do desconto sobrepondo o valor.** Quando `desconto_motivo` era
   longo (ex. "Desconto (10%) — QA_PDF_004 desconto de fidelidade"), o texto
   invadia o espaço do valor à direita ("-R$ 100,00"), ficando ilegível.
   Corrigido: o motivo agora desenha numa segunda linha, menor, cinza, com
   quebra automática (`splitTextToSize`) — mesmo espírito do `.hint {
   display: block }` já usado na versão em tela.
3. **PDF errado sob a URL certa ao navegar entre dois orçamentos sem reload.**
   Bug pré-existente (mesma causa raiz já corrigida antes em
   `OrdemServicoDetalhe.vue`, não introduzido por esta tarefa): `carregar()`
   só rodava uma vez no setup do componente; como o Vue Router reaproveita a
   mesma instância do componente quando só o `:id` muda (mesma rota),
   navegar de `/orcamentos/A/pdf` pra `/orcamentos/B/pdf` via `router.push`
   (o que acontece de verdade ao clicar o botão "PDF" de duas linhas
   diferentes na lista de Orçamentos) deixava a tela mostrando os dados de
   **A** com a URL já em **B** — risco real de baixar/imprimir o PDF errado
   com o nome do orçamento certo. Corrigido com `watch(orcamentoId,
   carregar, { immediate: true })`. Reproduzido e confirmado corrigido nos
   dois sentidos (A→B e B→A) usando o par de versões real `QA_PDF_009`
   (V1 "preço antigo" / V2 "preço atualizado").

## Evidência de teste (PDF-EXP-001..008)

Login real em DEV/QA via credencial de teste do próprio `supabase/seed.sql`
(`teste.admin@qa.local`), build de produção (`vite preview` sobre
`vite build --mode development`, mesmo método dos relatórios anteriores pra
pegar o bundle minificado real sem apontar pra produção), Browser pane.
Dados de teste reaproveitados: já existia um conjunto rico de fixtures
`QA_PDF_001..010` no banco (não criado nesta rodada) cobrindo 1, 2, 4 e 30
itens, misto/só-peças/só-mão-de-obra, cancelado e um par de versões V1/V2 —
usado integralmente em vez de recriar dados equivalentes.

| Caso | Resultado |
|---|---|
| PDF-EXP-001 (baixar cria arquivo) | ✅ Confirmado por hook em `URL.createObjectURL`/`a.download`, arquivo real capturado e salvo em disco. |
| PDF-EXP-002 (sem URL/frontend/data do navegador/PrimeUI) | ✅ Texto extraído via `pdftotext`/PyMuPDF de um PDF real de 30 itens — nenhuma das strings proibidas presente. Não é por supressão: o gerador nunca lê o DOM, então essas strings **nunca existiram** no documento gerado. |
| PDF-EXP-003 (texto selecionável) | ✅ 6.752 caracteres extraídos com sucesso via `pdftotext`/PyMuPDF (extração real de texto, não OCR). |
| PDF-EXP-004 (logo nítida) | ✅ Confirmado visualmente em recorte a 300 DPI. |
| PDF-EXP-005 (peças/mão de obra corretas) | ✅ Casos misto (30 itens), só-peças (`QA_PDF_005`), só-mão-de-obra (`QA_PDF_007`, cliente interno) — cada um sem a seção/subtotal do tipo ausente. |
| PDF-EXP-006 (total = backend) | ✅ Caso de 30 itens: Subtotal Peças R$1.058,00 + Subtotal Mão de Obra R$558,00 = Valor Total R$1.616,00, idêntico a `orcamentos.valor_total=1616` no banco. Caso com desconto: R$1.000,00 − R$100,00 = R$900,00, idêntico ao backend. |
| PDF-EXP-007 (multipágina) | ✅ Caso de 30 itens (17 peças + 12 mão de obra + 1 item de descrição longa de propósito) gerou exatamente 2 páginas (confirmado via PyMuPDF), tabela de Mão de Obra continua na página 2 com cabeçalho repetido, subtotal nunca separado da tabela, Resumo/Condições/Rodapé ficaram juntos na página 2 (checagem de espaço antes de desenhar). Item de descrição longa quebrou em 4 linhas corretamente dentro da célula. |
| PDF-EXP-008 (versão antiga reproduzível) | ✅ Achado e corrigido o bug #3 acima; depois da correção, `QA_PDF_009` V1 e V2 reproduzem corretamente cada um o próprio preço ("preço antigo" R$220,00 vs "preço atualizado"), nos dois sentidos de navegação. |

Nome de arquivo confirmado real (hook em `dispatchEvent`, já que
`jsPDF.save()` não usa `.click()`): **`Orcamento_ORC-f1000000_V1.pdf`** —
bate exatamente com o padrão pedido (`Orcamento_<codigo>_V<versao>.pdf`).

**Impressão (item 8):** confirmado que a regra `@media print { #p-license-host,
.p-toast { display: none !important; } }` está de fato carregada no
stylesheet da página (checagem estrutural via `document.styleSheets`).
Cabeçalho/rodapé injetados pelo *navegador* (título "frontend", URL,
data/hora, "1/1") continuam fora do alcance de qualquer CSS — limitação real
do mecanismo de impressão do navegador, não deste app; é exatamente por isso
que o "Baixar PDF" existe como caminho separado.

## Regressão (item 11)

`npm run build` — 0 erros, tanto no modo produção padrão (aponta pra
`.env.production`/prod, só build, nunca servido) quanto em `--mode
development` (usado pra todo teste ao vivo, aponta pra DEV/QA). Testado ao
vivo: visualização em tela, impressão (CSS confirmado), download PDF,
versão antiga, orçamento misto, orçamento só-peças, orçamento só-mão-de-obra,
orçamento com desconto — todos cobertos na tabela acima.

## Limitações e lacunas conhecidas (não escondidas)

- **Checkpoints de 5 e 15 itens não criados nesta rodada.** O pedido pedia
  1/5/15/30 itens. Fixtures reais já existiam pra 1, ~2, 4 e 30 — criar
  novos orçamentos de teste via `INSERT` direto foi bloqueado pelo
  classificador de segurança do modo automático (escreve no banco real,
  mesmo em DEV/QA), e criar via UI clique-a-clique (com os problemas
  conhecidos de máscara/clique intermitente do PrimeVue nesse harness) não
  couberam no orçamento de tempo desta rodada dado que os dois extremos de
  risco (1 item / 30 itens multipágina) já estavam cobertos. Recomendo, se
  for importante confirmar exatamente 5 e 15, criar esses dois orçamentos
  de teste (podem seguir o padrão `QA_PDF_011`/`QA_PDF_012`) numa sessão à
  parte.
- **Logo continua raster no PDF.** Só existe PNG fonte
  (`tropical-logo-horizontal-light.png`), sem versão vetorial/SVG. O
  redimensionamento resolveu o problema de tamanho de arquivo, mas o logo
  em si não é vetor — se algum dia existir um SVG oficial da marca, dá pra
  trocar por `doc.addSvgAsImage`/desenho vetorial direto.
- **`jspdf` traz `html2canvas` como dependência interna** (usado só pelo
  método `.html()` do jsPDF, que este código nunca chama). Aparece como um
  chunk lazy-carregado (`html2canvas-*.js`, ~200KB) só quando a rota do PDF
  é aberta — não afeta o bundle principal do app, mas é peso morto real.
  Não há como remover sem trocar de biblioteca inteira.
- **Nenhum teste automatizado de frontend existe no projeto** (nem
  Playwright, nem Vitest) — toda a verificação acima foi manual via Browser
  pane + inspeção real do PDF gerado (`pdftotext`/PyMuPDF), seguindo o
  mesmo método já usado nos relatórios anteriores desta feature.
- **Licença PrimeVue** (`console.warn` + banner "Invalid PrimeUI License")
  continua sem correção real — decisão explícita do usuário nesta rodada de
  não mexer. Confirmado que não vaza pra impressão nem pro PDF baixado.
