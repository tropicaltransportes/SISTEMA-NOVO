# UX-ORCAMENTOS-01 — Redesign da tela de Orçamentos

Data: 2026-08-13
Escopo: redesign visual da listagem de Orçamentos, criação, itens, desconto, decisão por item, autorização, acréscimo e visualização/PDF, seguindo a linguagem já aplicada em Login, Dashboard, Clientes, Veículos e Solicitações. Sem alteração de backend, banco, RPCs, regras de negócio, permissões, cálculos, estados ou versionamento.

---

## Arquivos alterados

- `frontend/src/views/orcamentos/OrcamentosList.vue` — reescrita de template/estilo e reorganização de 1 função de carregamento (ver LISTAGEM). Toda a lógica de negócio (`carregar`, `criarRascunho`, `salvarItens`, `enviar`, `confirmarAprovacao`, `confirmarRejeicao`, `novaVersao`, `criarOs`, `salvarAutorizacao`, `salvarAcrescimo`, `salvarDesconto`, `decidirItem`) permanece com as mesmas condições, os mesmos parâmetros de RPC e as mesmas validações.
- `frontend/src/views/orcamentos/OrcamentoPdf.vue` — reescrita completa do documento (era HTML técnico sem estilo, virou um documento comercial). Fonte de dados (`rpc_dados_pdf_orcamento`) e campos usados são exatamente os mesmos.
- `frontend/src/constants/statusVisual.js` — novo `STATUS_ITEM_ORCAMENTO` (pendente/aprovado/rejeitado), mesmas severidades que já existiam nos mapas locais `tagDecisao` (List) e `tagSeveridade` (Pdf); `STATUS_ORCAMENTO` já existia (criado em UX-DASHBOARD-01) e foi reaproveitado sem alteração.

## LISTAGEM

Reorganizada para reduzir a "parede" de 9 colunas + botões soltos. Título "Orçamentos" + subtítulo + CTA "Novo Orçamento" (mesmo padrão de Clientes/Veículos/Solicitações, mesma condição `podeGerir()` de antes). `.panel` com `overflow-x: auto` para telas menores.

## BUSCA

**Adicionada** — não existia nenhum campo de busca antes. Mesmo mecanismo client-side (`:filters` + `globalFilterFields`) das telas irmãs, sobre os dados já buscados — zero query nova. Campos: `cliente.nome`, `veiculo.placa`, `numero_legivel` (ver IDENTIFICAÇÃO abaixo). Placeholder "Buscar por cliente, veículo, número ou placa" — os 4 critérios citados realmente funcionam.

## FILTROS

**Botão "Filtros" não implementado.** Não existe hoje nenhum filtro real (por status, período, cliente, veículo) além da busca por texto — confirmado lendo o arquivo original, que não tinha nenhum estado de filtro além da tabela completa. Criar o botão sem filtro real atrás violaria a instrução explícita do item 6.

## IDENTIFICAÇÃO DO ORÇAMENTO (Nº Orçamento)

Adicionada a coluna "Nº Orçamento" (ex: `ORC-a1b2c3d4-V1`). **Não é um número novo, nem inventado**: é a mesma fórmula que o backend já usa em `rpc_dados_pdf_orcamento` (`supabase/migrations/20260814111000_p1c_relatorios.sql:33` — `'ORC-' || substr(o.id::text, 1, 8) || '-V' || o.versao`), replicada em JS (`numeroLegivel()`) usando `id`/`versao`, campos que a listagem já buscava. Não chamei a RPC por linha (ela é feita para 1 orçamento) — só recalculei localmente a mesma string, com o mesmo `id`/`versao` que já vinham na consulta.

## STATUS

Badge padronizado via `STATUS_ORCAMENTO` (já existente desde UX-DASHBOARD-01, sem alteração): `rascunho` cinza, `enviado` azul, `aprovado` verde, `parcialmente_aprovado` violeta, `rejeitado` vermelho, `substituido` cinza-contraste. Rótulo em PT-BR em vez do enum cru. **"CANCELADO" (mencionado no item 10 do roteiro) não existe no enum real de orçamento** (`status_orcamento`: rascunho/enviado/aprovado/parcialmente_aprovado/rejeitado/substituido — confirmado em `supabase/migrations/20260806130100_orcamentos.sql` + `20260813100000_p1b_status_orcamento_enum.sql`) — não foi criado, conforme "usar somente estados reais já existentes".

## VALORES

Valores monetários alinhados à direita (`bodyClass="col-numero"/"col-valor"` + CSS `text-align:right`), formatação brasileira mantida (`formatarMoeda`, sem alteração). Cores diferenciadas com os tokens do design system em vez de hex hardcoded que existiam no código original (`#15803d`, `#b91c1c`): Original = `var(--text-body)` (neutro), Aprovado = `var(--success)`, Rejeitado = `var(--danger)`, Acréscimos = `var(--accent-text)` (violeta discreto). **Nenhum cálculo foi alterado** — `valorAprovado()`/`valorRejeitado()` continuam somando `quantidade × valor_unitario` por `status_aprovacao`, exatamente como antes.

## AÇÕES

Reorganização mais significativa desta etapa. Antes: até 4-7 botões simultâneos na mesma linha, dependendo de status/perfil (Itens, Desconto, Enviar, PDF, Autorização, Decidir Itens, Aprovar tudo, Rejeitar tudo, Ver decisões, Acréscimo, Criar OS, Nova Versão). Agora: no máximo 2 botões primários visíveis por status + PDF (sempre) + menu de três pontos com o resto — **exatamente como pedido no item 12**.

Primários visíveis (mesmas condições de antes):
- `rascunho && podeGerir()`: **Itens**, **Enviar**
- `enviado && podeAutorizar()`: **Decidir Itens** (já era a ação em destaque no código original)
- `['aprovado','parcialmente_aprovado'] && podeGerir()`: **Criar OS**
- sempre: **PDF** (ícone, sem gate de permissão — igual ao original)

No menu de três pontos (mesmas condições de antes, só reagrupadas): Aplicar desconto (`rascunho && podeGerir()`), Registrar autorização (`enviado && podeAutorizar()`), Aprovar tudo / Rejeitar tudo (`enviado && podeGerir()`), Ver decisões / Registrar acréscimo (`['aprovado','parcialmente_aprovado'] && podeGerir()` / só se `aprovado`), Nova versão (`['enviado','aprovado','parcialmente_aprovado','rejeitado'] && podeGerir()`).

O botão de menu **só aparece se houver pelo menos 1 ação disponível** para aquela linha (`construirMenuAcoes(data).length`), evitando um menu vazio. **Nenhuma condição de permissão/status foi alterada** — cada `v-if` do código original foi movido, não reescrito.

## NOVO ORÇAMENTO

Mesmo único campo (Veículo), mesmo rodapé (Cancelar / Criar Rascunho), mesma lógica de idempotência (`clientRequestId`) intocada. Adicionado: quando um veículo é selecionado, mostra "Cliente: {{ nome }}" como informação — dado derivado do mesmo `veiculo.cliente_id` que `criarRascunho()` já usa (não é uma consulta nova, é o mesmo array `veiculos` já carregado com `cliente:clientes(nome, tipo)`).

## ITENS

Reestruturado de "N linhas todas editáveis inline" para "formulário de adicionar item + tabela de itens incluídos", conforme o item 18 pedia em detalhe. Modal alargado (`width: 92vw; max-width: 820px`, era 680px fixo). Fluxo: escolher Tipo (Peça/Mão de obra) → se Peça, selecionar peça (opcional, autopreenche descrição) → descrição/quantidade/valor unitário → "Adicionar" empurra para a tabela "Itens incluídos" (com badge Peça/Mão de obra, subtotal, remover). Total do orçamento exibido no rodapé do modal.

**O array `itens` (mesmo formato: `{id, peca_id, descricao, quantidade, valor_unitario}`) e a função `salvarItens()` (delete-all + insert, mesma validação) não mudaram nem um pouco** — só a forma de montar esse array no frontend antes de salvar. O badge "Peça"/"Mão de obra" é inferido de `peca_id` (presente = Peça, ausente = Mão de obra), o mesmo critério que já distinguia implicitamente as duas antigas funções `adicionarItemPeca`/`adicionarItemMaoDeObra` — não é um campo novo.

## DESCONTO

Mantido como modal (mesmos campos: Modo, Percentual/Valor, Motivo). Adicionado "Valor atual: {{ valor_total }}" como contexto (dado já conhecido, zero risco). **Não adicionei uma prévia de "valor após desconto"** — o item 21 só permite isso "se os dados/cálculos já existirem no frontend de forma segura", e não existem: o cálculo do valor final (respeitando teto, nunca abaixo de zero, etc.) é feito inteiramente por `rpc_aplicar_desconto_orcamento`; qualquer prévia client-side seria uma fórmula divergente da real, o que o item 21 proíbe explicitamente. O texto corrido de regras virou uma caixa "ℹ Regras do desconto" com lista — mesmo texto/regras reais já existentes (teto, motivo obrigatório, nunca abaixo de zero, exige nova versão se já enviado/aprovado), nenhuma política nova.

## DECISÃO POR ITEM / AUTORIZAÇÃO / ACRÉSCIMO

Restilizados (blocos com título, tabela dark, badges via `STATUS_ITEM_ORCAMENTO`) sem alterar nenhuma validação, nenhum parâmetro de RPC, nenhuma condição de habilitação (`temItemPendente`, `podeAutorizar`, meios de aprovação sistema/e-mail/verbal documentado com seus respectivos campos obrigatórios).

## PDF

Reescrita completa (era HTML sem nenhum estilo — `<h2>`/`<h3>`/`<p>` crus e uma tabela com bordas genéricas). Agora: card branco tipo "papel" (mesmo em cima do fundo dark do app), letterhead com o monograma Tropical (mesmo estilo do resto do app) + `d.empresa.nome` (string real, só quebrada visualmente em 2 linhas onde já existe um "—"), número do orçamento em destaque, blocos Cliente/Veículo, tabela de itens, resumo financeiro (Valor bruto, Desconto, **Valor aprovado**, **Valor rejeitado** — novos, somando `valor_liquido` dos itens por `status_aprovacao`, mesma técnica de agregação já usada na listagem — e Valor total), aviso de versão como caixa informativa.

**"Acréscimos" não aparece no resumo financeiro** — `rpc_dados_pdf_orcamento` não retorna esse dado (conferido lendo a função inteira; não há `orcamento_acrescimos` em lugar nenhum do jsonb retornado). Mostrar seria inventar um número. Registrado como melhoria futura.

**"Contato" do cliente** (mencionado como "se disponível" no item 23) também não existe no retorno da RPC (`cliente`: apenas `id, nome, documento, tipo`) — omitido, não inventado.

O documento continua com fundo branco tanto na tela quanto na impressão (`@media print` só remove os botões de ação e a sombra do card) — não há inversão de cor entre tela e impressão, porque o "papel" já é branco nos dois casos, conforme item 27 ("dark mode é para a interface... PDF/impresso deve continuar apropriado para impressão").

## VERSIONAMENTO

Preservado sem mudança de comportamento: "Versão N" no cabeçalho do documento e na listagem (`V{{ versao }}`), aviso de imutabilidade da versão mantido (mesmo texto real, só estilizado como caixa informativa).

## RESPONSIVIDADE

Não validado ao vivo nesta sessão (ver limitação abaixo). Medidas tomadas: `.panel` com scroll horizontal na listagem; modal de Itens usa `width: 92vw` (nunca ultrapassa a viewport, inclusive em 1366px); documento PDF com breakpoint próprio (`max-width: 640px`) empilhando os blocos Cliente/Veículo em coluna única.

## INVALID PRIMEUI LICENSE

Confirmado que continua aparecendo, mesma causa raiz documentada nas 4 etapas anteriores (não resolvida por decisão sua, adiada 2 vezes) — verificado nesta sessão ao carregar a tela de login, sem regressão nova, sem tentativa de mascarar via CSS.

## BUILD

```
npm run build
```
executado em `frontend/` — **sucesso**, sem erros, nas duas rodadas (após `OrcamentosList.vue` e depois `OrcamentoPdf.vue`).

## REGRESSÃO

- **Mesma limitação das etapas anteriores:** sem credenciais válidas de DEV/QA nesta sessão, não foi possível validar visualmente ao vivo o fluxo completo (listagem com dados reais, criar rascunho, adicionar itens, aplicar desconto, decidir itens, enviar, aprovar, criar OS, abrir PDF).
- **O que foi validado:**
  - `npm run build` completo sem erros, duas vezes.
  - Tela de login carrega normalmente, sem novo erro de console.
  - Revisão linha a linha de `OrcamentosList.vue`: grep confirmando que nenhuma função antiga (`adicionarItemPeca`, `adicionarItemMaoDeObra`, `selecionouPeca`, `severidadeStatus`, `tagDecisao`) ficou órfã; toda função de negócio existente (`enviar`, `confirmarAprovacao`, `confirmarRejeicao`, `novaVersao`, `criarOs`, `salvarAutorizacao`, `salvarAcrescimo`, `salvarDesconto`, `decidirItem`) confirmada presente e intocada.
  - `construirMenuAcoes()` conferida item a item contra as condições `v-if` originais — nenhuma condição de status/permissão foi adicionada, removida ou trocada.
  - `numeroLegivel()` conferida caractere a caractere contra a expressão SQL real em `rpc_dados_pdf_orcamento`.

## MELHORIAS FUTURAS NÃO IMPLEMENTADAS

1. **Acréscimos no documento PDF** — `rpc_dados_pdf_orcamento` não retorna esse dado hoje; para exibir, seria preciso alterar a RPC (fora de escopo desta etapa, que é "não alterar backend").
2. **Contato do cliente (telefone/e-mail) no documento** — não retornado pela RPC atual.
3. **Prévia de "valor após desconto"** no modal de desconto — precisaria replicar a lógica de teto/arredondamento da RPC no frontend, com risco real de divergir do resultado oficial; melhor deixar só no backend.
4. **Centralizar CSS compartilhado entre telas de listagem** (Clientes, Veículos, Solicitações, Orçamentos) — continua duplicado por não tocar em arquivos de etapas já entregues (mesma nota das etapas anteriores).
5. **Botão "Filtros"** — só faz sentido quando existir um filtro real além da busca (ex: por status, por período).
6. **Downgrade do PrimeVue** (5→4.5.5) para eliminar o aviso "Invalid PrimeUI License" — mapeado, ainda aguardando autorização (adiado 2x, sem mudança nesta etapa).
7. **Validação visual ao vivo** do fluxo completo — pendente de credenciais de teste válidas do ambiente DEV/QA.
