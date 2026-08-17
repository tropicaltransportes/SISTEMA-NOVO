# Marca Tropical Transportes — guia de uso (ETAPA BRAND-01)

Fonte oficial: pasta fornecida pelo dono do projeto
(`Identidade Visual - Tropical Transportes/Logotipo/PNG/`) +
`MANUAL DE MARCA - TROPICAL TRANSPORTES.pdf` (49 páginas, mesma pasta).
Todos os arquivos usados aqui são cópias byte-a-byte dos PNGs oficiais —
nenhuma logo foi redesenhada, recolorida, filtrada ou gerada por IA.

## Qual arquivo usar

| Contexto | Componente | Arquivo |
|---|---|---|
| Fundo claro, precisa do símbolo isolado | `<BrandLogo variant="symbol" surface="light" />` | `tropical-symbol-light.png` |
| Fundo escuro, precisa do símbolo isolado (ex.: sidebar recolhida) | `<BrandLogo variant="symbol" surface="dark" />` | `tropical-symbol-dark.png` |
| Fundo claro, logo completa em linha (PDF, papelaria) | `<BrandLogo variant="horizontal" surface="light" />` | `tropical-logo-horizontal-light.png` |
| Fundo escuro, logo completa em linha (sidebar expandida, login) | `<BrandLogo variant="horizontal" surface="dark" />` | `tropical-logo-horizontal-dark.png` |
| Fundo claro, composição empilhada (símbolo acima do nome) | `<BrandLogo variant="vertical" surface="light" />` | `tropical-logo-vertical-light.png` |
| Fundo escuro, composição empilhada | `<BrandLogo variant="vertical" surface="dark" />` | `tropical-logo-vertical-dark.png` |
| Assinatura horizontal alternativa (símbolo à direita do nome) — uso pontual, sem componente dedicado | — | `tropical-logo-horizontal-alt.png` |

**Nunca** use `filter: hue-rotate/brightness/invert` (ou qualquer outro
filtro CSS) para "fabricar" a versão light/dark a partir da outra — as duas
já existem como arquivos oficiais distintos, com colorway própria aprovada
pelo Manual de Marca (página 17-19, "Variações de Cores").

## Mapeamento Prancheta → arquivo (confirmado por inspeção visual + Manual de Marca)

O Manual de Marca (páginas 16-19) documenta 3 modelos oficiais de
logotipo — horizontal (Modelo 01), vertical (Modelo 02) e horizontal
alternativo (Modelo 03) — cada um com 5 colorways (um por cor de fundo
oficial). O mapeamento abaixo foi confirmado lendo cada PNG como imagem
(não só pelo nome do arquivo) e comparando com a página 17/18/20 do
manual (aplicação do símbolo/logotipo sobre cada cor de fundo oficial):

| Prancheta | Uso | Confirmação |
|---|---|---|
| 1 | símbolo, fundo claro | verde escuro + verde claro sólidos — bate com o swatch "Branco gelo"/"Verde banana" da p.20 |
| 2 | símbolo, fundo escuro | traços em branco gelo + verde claro — bate com o swatch "Azul miragem"/"Verde escuro" da p.20 |
| 5 | horizontal, fundo claro | "Tropical" verde escuro + "TRANSPORTES" verde escuro — bate com Modelo 01 sobre Branco gelo (p.17) |
| 13 | horizontal, fundo escuro | "Tropical" branco gelo + "TRANSPORTES" verde claro — bate com Modelo 01 sobre Azul miragem (p.17) |
| 17 | vertical, fundo claro | mesma lógica de cor de 5, layout empilhado — bate com Modelo 02 sobre Branco gelo (p.18) |
| 20 | vertical, fundo escuro | mesma lógica de cor de 13 (TRANSPORTES em verde claro, contrastante) — bate com Modelo 02 sobre Azul miragem (p.18). Descartadas as Pranchetas 18/19 (mesmo layout, mas "TRANSPORTES" em tom pálido quase invisível — variante para fundo Verde Escuro, não a mais versátil para o dark mode do ERP) |
| 21 | horizontal alternativo, fundo claro | símbolo à direita do nome — bate com Modelo 03 (p.19/16) |

Arquivos originais preservados, sem qualquer alteração, em `originals/`
(mesmo nome "Prancheta N.png" da pasta fornecida pelo dono do projeto).

## Paleta oficial

Fonte: Manual de Marca, página 25 ("2. Paleta de Cores RGB") — nomes e
hex exatamente como o documento, confirmados por amostragem de pixel nos
PNGs oficiais (script `Pillow`, sem arredondamento).

| Nome oficial | Hex | Token CSS | Papel |
|---|---|---|---|
| Verde escuro | `#06772b` | `--brand-verde-escuro` | Cor dominante do logotipo; fills sólidos/texto em fundo **claro** (5.70:1 contra branco — passa AA) |
| Verde claro | `#00c038` | `--brand-verde-claro` | Acento/detalhe do logotipo; texto/ícone em fundo **escuro** (5.96:1 contra Azul Miragem — passa AA) |
| Branco gelo | `#edfff2` | `--brand-branco-gelo` | Tom mais claro; o próprio logotipo usa em fundo escuro; serve como tinta pálida de fundo/borda em documentos claros |
| Azul miragem | `#1c2a3a` | `--brand-azul-miragem` | Fundo escuro oficial da marca — usado como `--bg-page` do ERP (dark mode) |
| Verde banana | `#c7d291` | `--brand-verde-banana` | Terciária — só passa contraste AA-*large* com verde escuro (3.55:1); uso esparo, nunca como fundo de texto corrido |

**Não incluída como token de marca**: um sexto arquivo `#585E63.png`
existe na pasta `Cores/` fornecida, mas **não aparece** na página oficial
"Paleta de Cores RGB" do Manual (só as 5 acima). Como não há confirmação
de que seja uma cor oficial (pode ser um experimento descartado do
material bruto), ele foi **deixado de fora** dos tokens de marca em vez de
adivinhado — dúvida registrada aqui em vez de decisão inventada (ver
seção 26 da instrução da etapa).

### Contraste (WCAG, calculado — ver `docs/testing/BRAND_01_REPORT.md` para a tabela completa)

- Branco sobre Verde escuro: **5.70:1** — OK para texto normal.
- Branco sobre Verde claro: **2.44:1** — **reprovado**. Nunca usar verde
  claro como fundo sólido com texto branco em cima — só como acento fino
  (borda, ícone, texto) sobre superfície escura, ou como ponta de
  gradiente ao lado do verde escuro.
- Verde escuro sobre Azul Miragem (fundo escuro): **2.55:1** —
  **reprovado**. Verde escuro nunca deve ser cor de texto/ícone solto
  sobre o fundo escuro do app — só como fill de botão (com texto branco
  em cima, que aí sim passa).

## Regras de uso (Manual de Marca, "6.6 Positivo/Negativo" a "6.8 Redução")

- Altura mínima da composição completa: **45mm** (redução máxima
  documentada, página 23).
- Usos proibidos (página 22, "Usos Incorretos"): alterar tipografia,
  rotacionar, alterar proporções, distorcer, alterar cores. Mantido à
  risca nesta etapa — nenhum componente aplica `transform`, `filter` nem
  redimensiona sem preservar proporção (`BrandLogo.vue` usa
  `object-fit: contain` e nunca define `width`+`height` fixos ao mesmo
  tempo para as variantes não-quadradas).
- Área de proteção: o manual não define um valor numérico de *clear
  space* nas páginas revisadas; o favicon foi gerado com ~14% de margem
  transparente ao redor do símbolo como resguardo prático (não é uma
  regra do manual, é uma decisão de implementação — registrado aqui para
  transparência).

## Observação encontrada no material (não afeta os assets usados)

A página 2 do Manual de Marca ("Índice") contém o texto "...para utilizar
a identidade visual **da Dra. Ana Luiza Delmondes**..." — claramente um
resquício de um template de outro cliente que não foi totalmente
adaptado para a Tropical Transportes. Não afeta nenhum arquivo de logo
nem a paleta de cores (ambos claramente da Tropical, conferidos
visualmente), mas fica registrado aqui como curiosidade/possível ponto a
avisar o dono do projeto, sem gerar nenhuma decisão de código.
