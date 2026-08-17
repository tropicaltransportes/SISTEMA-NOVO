# BRAND-01 — Identidade visual oficial Tropical Transportes

Incorporação dos arquivos oficiais de marca (fornecidos pelo dono do
projeto) ao ERP Oficina, com centralização do uso via `BrandLogo.vue` e
migração do destaque roxo/violeta provisório para a identidade Tropical
(verde). **Só branding/frontend** — nenhuma migration, RPC, regra de
negócio, cálculo ou permissão foi tocada.

## ASSETS RECEBIDOS

Fonte: pasta local do dono do projeto
`LOCADORA - OPERAÇÃO E LOGISTCA/PROJETO IDENTIDADE E MARCKETING/01
DESENVOLVIMENTDO DE MARCA - INICIAL/Identidade Visual - Tropical
Transportes/` (não estava anexada à conversa — localizada no
filesystem local, mesma origem também presente, com pequenas variações
de nome de pastas, em `LOCADORA - SETOR PESSOAL/.../IDENTIDADE VISUAL
TROPICAL/`). Continha:

- `Logotipo/PNG/` — 23 Pranchetas (variações completas do logotipo)
- `Logotipo/LOGOTIPO/` — subconjunto (símbolo isolado + grafismos)
- `Cores/` — 6 PNGs de swatch, nomeados pelo próprio hex
- `Grafismos/PNG/` e `Grafismos/PDF/` — padrões gráficos (fora do escopo desta etapa)
- `Instagram/` — templates de rede social (fora do escopo)
- `Fontes/` — IBM Plex Sans + Maven Pro em `.zip` (não instaladas nesta etapa — ver "Melhorias futuras")
- `Papelaria/` — cartão de visita, envelope, crachá, agenda em PDF (fora do escopo)
- `MANUAL DE MARCA - TROPICAL TRANSPORTES.pdf` — 49 páginas, fonte
  normativa para paleta, modelos de logotipo, regras de uso e redução
  mínima

## ASSETS UTILIZADOS

7 PNGs oficiais confirmados por **inspeção visual real** (lidos como
imagem, não só pelo nome do arquivo) e cruzados com as páginas 16-20 do
Manual de Marca:

| Papel | Arquivo em `frontend/src/assets/brand/` | Fonte |
|---|---|---|
| Símbolo, fundo claro | `tropical-symbol-light.png` | Prancheta 1 |
| Símbolo, fundo escuro | `tropical-symbol-dark.png` | Prancheta 2 |
| Horizontal, fundo claro | `tropical-logo-horizontal-light.png` | Prancheta 5 |
| Horizontal, fundo escuro | `tropical-logo-horizontal-dark.png` | Prancheta 13 |
| Vertical, fundo claro | `tropical-logo-vertical-light.png` | Prancheta 17 |
| Vertical, fundo escuro | `tropical-logo-vertical-dark.png` | Prancheta 20 |
| Horizontal alternativo (bônus, não usado em tela ainda) | `tropical-logo-horizontal-alt.png` | Prancheta 21 |

Originais preservados intactos (mesmo nome, mesmos bytes — conferido por
`md5sum`) em `frontend/src/assets/brand/originals/`. Nenhum arquivo foi
redesenhado, recolorido, filtrado, distorcido ou gerado por IA — só
copiado. Nenhum redimensionamento: os PNGs já são pequenos (33-68 KB
cada, ~370 KB total, mesmo em 2000-5300px de largura, por serem
majoritariamente área plana/transparente), então não há upscaling nem
necessidade de compressão adicional.

## MAPPING

Ver `frontend/src/assets/brand/README.md` para a tabela completa e o
raciocínio de cada escolha (inclusive por que as Pranchetas 18/19 foram
descartadas em favor da 20 para "vertical-dark" — mesma composição, mas
"TRANSPORTES" quase invisível nelas, quando a 20 bate exatamente com o
colorway oficial para o fundo Azul Miragem documentado na p.18 do
manual).

## TOKENS EXTRAÍDOS

Fonte: Manual de Marca, página 25 ("2. Paleta de Cores RGB") — nomes e
hex exatamente como o documento, confirmados por amostragem de pixel
(Pillow, sem arredondamento) tanto nos swatches de `Cores/` quanto nos
próprios PNGs do logotipo:

| Nome oficial | Hex | Token | Contraste medido |
|---|---|---|---|
| Verde escuro | `#06772b` | `--brand-verde-escuro` | branco sobre ele: **5.70:1** (AA ok) |
| Verde claro | `#00c038` | `--brand-verde-claro` | branco sobre ele: **2.44:1** (reprovado — só acento, nunca fill+texto branco) |
| Branco gelo | `#edfff2` | `--brand-branco-gelo` | sobre Azul Miragem: **14.00:1** |
| Azul miragem | `#1c2a3a` | `--brand-azul-miragem` | vira `--bg-page` (dark mode) |
| Verde banana | `#c7d291` | `--brand-verde-banana` | verde escuro sobre ele: **3.55:1** (só AA-*large*) |

`#585E63.png` existe na pasta `Cores/` mas **não aparece** na página
oficial de paleta do manual — **deixado de fora dos tokens** por falta de
confirmação (dúvida registrada, não decisão inventada).

Verde claro sobre Azul Miragem (fundo escuro do app): **5.96:1** (AA ok)
— por isso é o acento de modo escuro (`--accent-1`/`--accent-text`), e
verde escuro (que reprova a 2.55:1 no mesmo fundo) é reservado para fills
sólidos com texto branco (5.70:1) e para o documento claro do PDF.

## BrandLogo

`frontend/src/components/brand/BrandLogo.vue` — props `variant`
(symbol/horizontal/vertical), `surface` (light/dark), `size`, `class`.
Imports estáticos do Vite (não `import.meta.glob`, já que os 6 arquivos
são fixos e conhecidos) — cada tela que usa `BrandLogo` só baixa a imagem
efetivamente renderizada (confirmado via Network: a tela de PDF só busca
`horizontal-light.png`; a sidebar só busca `horizontal-dark.png` +
`symbol-dark.png`, nunca os 6 juntos). Nunca deforma: altura fixa (prop
`size`), largura livre (`object-fit: contain`, sem `width`+`height` fixos
simultâneos nas variantes não-quadradas).

## LOGIN

`AuthLayout.vue` (usado por Login/Esqueci Senha/Definir Senha/Alterar
Senha) — símbolo/monograma desenhado em CSS removido, substituído por
`<BrandLogo variant="horizontal" surface="dark" />`. Texto "Tropical
Transportes" ao lado removido (já está na própria imagem). Composição
final: **logo oficial → "ERP Oficina" → tagline**, exatamente como
sugerido na instrução. Glow decorativo de fundo (`rgba(109, 40, 217,
0.25)`, roxo) trocado por verde escuro translúcido. Verificado ao vivo
(logout/login reais em DEV/QA): imagem carrega (`complete: true`,
5338×1034), fundo `rgb(28, 42, 58)` = Azul Miragem.

## SIDEBAR

`AppShell.vue` — quadrado com gradiente roxo + bolinha branca (CSS)
removido. Expandida: `<BrandLogo variant="horizontal" surface="dark" />`
+ legenda "ERP Oficina" tipograficamente separada (uppercase, menor,
abaixo). Recolhida (`max-width: 1280px`, mecanismo de breakpoint já
existente, reaproveitado): troca automática para
`<BrandLogo variant="symbol" surface="dark" />`. Verificado ao vivo em
375px (mobile): sidebar cai para 76px, símbolo aparece em 30px, sem
overflow horizontal (`document.body.scrollWidth === window.innerWidth`).

## PDF

`OrcamentoPdf.vue` — mecanismo antigo (`import.meta.glob` procurando um
arquivo `logo-tropical.*` que ainda não existia, da etapa
UX-PDF-ORCAMENTO-01) substituído por
`<BrandLogo variant="horizontal" surface="light" />` direto, já que o
arquivo oficial agora existe. Texto "Tropical Transportes" duplicado ao
lado da logo removido (já está na imagem); mantido só "Oficina Mecânica"
como legenda de setor, tipograficamente separada. Cores locais do
documento (que já eram hardcoded em hex, isoladas do tema dark do app de
propósito) migradas de roxo para os tokens de marca:
`var(--brand-verde-escuro)` (títulos de seção, valor do número do
orçamento, cabeçalho de tabela, total) e `var(--brand-branco-gelo)`
(bordas/fundos pálidos). Verificado ao vivo: logo carrega
(`horizontal-light.png`, 5338×1034), sem overflow em 375px.

**Achado incidental corrigido**: a rota do PDF (e as de
`os-relatorio-encerramento`/`os-relatorio-garantia`/`veiculo-historico`)
são filhas do `AppShell`, e nada escondia a sidebar/topbar na impressão
real — cada documento só reseta o próprio `.documento-papel`, sem
alcance sobre os elementos do layout pai. Corrigido com um bloco
`@media print` novo em `AppShell.vue` (`.sidebar`/`.topbar { display:
none !important }` + reset do `.shell`/`.page-bg`), compilado e
confirmado presente no CSSOM. Pré-existente, não introduzido por esta
etapa, mas relevante para o item 21 (verificação de impressão) — por
isso corrigido aqui em vez de só registrado.

## FAVICON

Símbolo oficial fundo-claro (Prancheta 1) usado como base — nenhum
redesenho. `favicon-32.png`/`favicon-16.png`/`apple-touch-icon.png`
gerados via Pillow (`LANCZOS`, sem filtro de cor) com ~14% de margem
transparente de resguardo antes do redimensionamento. `favicon.svg`
antigo (blob roxo abstrato, sem relação com a marca real) removido do
`public/` e do `index.html` — confirmado sem outras referências no
código. Paths absolutos (`/favicon-32.png` etc.) confirmados corrigidos
para `/SISTEMA-NOVO/favicon-32.png` no `dist/index.html` após
`npm run build` (Vite reescreve automaticamente por causa de
`base: '/SISTEMA-NOVO/'` no `vite.config.js`).

## DARK MODE

`--bg-page` trocado de `#262b36` (grafite neutro) para
`var(--brand-azul-miragem)` (`#1c2a3a`) — não é uma cor inventada: é o
próprio fundo escuro oficial da marca (o Manual de Marca aplica
símbolo/logotipo sobre exatamente este tom na p.20). Contraste do texto
principal (`--text-body: #e9e6f3`) contra o novo fundo: **11.85:1**
(antes: 11.53:1 — leve melhora, não regressão). Interface **não** virou
fundo verde — o verde continua só como acento (botões, links, active
state, gradiente), conforme item 13 da instrução.

## BUILD

`npm run build` — sucesso, 0 erros, 0 warnings. Chunk `BrandLogo-*.js`
(1.25 kB) gerado uma vez, reaproveitado por todas as telas que o
importam. Todos os 6 PNGs usados aparecem como arquivos hasheados
próprios em `dist/assets/`; `tropical-logo-horizontal-alt.png` (não
importado em nenhum componente ainda) corretamente **não** entra no
build — confirma que só o que é de fato usado é empacotado (item 19).

## REGRESSÃO

Smoke test real em DEV/QA (login/logout reais, dados reais de teste já
existentes da etapa anterior):

| Tela | Resultado |
|---|---|
| Login (fundo escuro) | logo horizontal-dark carrega, "ERP Oficina" + tagline presentes, fundo Azul Miragem confirmado |
| Dashboard | `--bg-page`/`--accent-1` aplicados corretamente (`#1c2a3a`/`#00c038`), sem erro de console além do aviso pré-existente do PrimeVue (não relacionado a esta etapa) |
| Clientes | carrega normalmente, nenhuma regressão funcional |
| Sidebar expandida | logo horizontal-dark + "ERP Oficina" |
| Sidebar recolhida (mobile, 375px) | símbolo isolado, sem overflow |
| Orçamentos → PDF | logo horizontal-light, sem overflow em mobile, impressão agora sem chrome do ERP ao redor |
| `npm run build` | limpo |

Nenhum path aponta para localhost/DEV depois do build (favicons/logo
resolvidos via import do Vite + `base` do `vite.config.js`, mesmo
mecanismo já usado e testado desde a etapa UX-PDF-ORCAMENTO-01).

## O que foi deliberadamente deixado de fora (não é regressão, é escopo)

- **`ClientesList.vue`** (gradientes de avatar decorativos, 4 tons de
  roxo) e **`DashboardView.vue`** (cor da série "Recebido" no gráfico,
  `#8b5cf6`) continuam roxos. Não são elementos de marca/logo — são
  paleta decorativa/semântica de dados já existente, fora do pedido
  explícito desta etapa (Login/Sidebar/PDF/favicon/tokens centrais). Um
  refactor de paleta de gráficos é trabalho à parte.
- **`statusVisual.js`** (`aberta`/`parcial`/`garantia`) e
  **`--neutral-accent`** continuam roxos, de propósito: revisados (item
  12 da instrução — "devem ser revistos", não "devem ser trocados"), e
  mantidos como um 5º hue semântico "estado especial", agora
  **desacoplado** da marca (antes `--status-aberta` era literalmente o
  mesmo valor do antigo `--accent-1`; agora referencia
  `--neutral-accent` de forma independente, só coincidência de família de
  cor, nunca mais de identidade).

## Melhorias futuras não implementadas

- **Tipografia oficial**: o Manual de Marca especifica IBM Plex Sans
  (títulos) + Maven Pro (texto) — a aplicação usa Plus Jakarta Sans +
  JetBrains Mono hoje. Os `.zip` das fontes estão disponíveis na pasta
  fornecida, mas trocar a tipografia de todo o app é uma etapa própria
  (afeta muito mais superfície que branding de logo/cor), não abordada
  aqui.
- **Grafismos oficiais** (padrões gráficos do Manual, seção 8): não
  aplicados a nenhuma tela — instrução item 9 pede só "preparar" o
  `BrandLogo` para outros documentos futuros (relatório de encerramento,
  garantia, termo de ciência), não redesenhá-los nesta etapa; mantido
  assim.
- **Assinatura horizontal alternativa** (`tropical-logo-horizontal-alt.png`,
  Modelo 03/Prancheta 21): copiada e documentada, mas sem tela usando-a
  ainda — fica disponível para uso pontual futuro.
- **`empresa_config`/dados institucionais**: já registrado como melhoria
  futura na etapa UX-PDF-ORCAMENTO-01, continua pendente (CNPJ/endereço/
  telefone/site não existem em nenhuma tabela).
- **PWA icon**: não gerado — não existe `manifest.json`/PWA configurada
  no projeto hoje, então não haveria onde referenciá-lo (evitar criar
  arquivo não utilizado).

## Dúvida registrada (não virou decisão inventada)

- **`#585E63.png`** (cinza) na pasta `Cores/` fornecida pelo dono do
  projeto, mas ausente da página oficial "Paleta de Cores RGB" do
  Manual de Marca — pode ser um experimento descartado do material bruto
  de trabalho. Não foi incorporado como token oficial. Se for de fato
  uma cor institucional válida (ex.: para textos neutros), o dono do
  projeto pode confirmar e ela entra como `--brand-cinza` numa próxima
  etapa.
- **Texto residual no Manual de Marca** (página 2, índice): menciona "a
  identidade visual da Dra. Ana Luiza Delmondes" — claramente um
  resquício de template de outro cliente não totalmente adaptado para a
  Tropical Transportes. Não afeta nenhum asset usado (logo/paleta
  conferidos visualmente, claramente da Tropical), só fica registrado
  como curiosidade a avisar o dono do projeto.
