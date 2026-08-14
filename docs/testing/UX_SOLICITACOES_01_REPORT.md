# UX-SOLICITACOES-01 — Redesign da tela de Solicitações

Data: 2026-08-13
Escopo: redesign visual da tela de Solicitações, seguindo a linguagem já aplicada em Login, Dashboard, Clientes e Veículos. Sem alteração de backend, banco, RPCs, regras de negócio ou permissões.

---

## TELA ALTERADA

`frontend/src/views/solicitacoes/SolicitacoesList.vue` — template e estilo reescritos. Lógica preservada integralmente: consulta Supabase (mesmos campos, mesma ordenação por `criado_em desc`), criação de solicitação (mesmo payload, mesma validação client-side de veículo+descrição obrigatórios), transições de status (`marcarEmAnalise`, `confirmarCancelamento`, `converterEmOrcamento`) e a checagem de permissão `podeGerir()` — **nenhuma delas foi alterada**, só a apresentação ao redor.

Também estendido (sem quebrar nada existente): `frontend/src/constants/statusVisual.js` ganhou `STATUS_SOLICITACAO`, com as **mesmas severidades** que já existiam no mapa local `severidadeStatus` deste arquivo (`aberta:info, em_analise:warn, convertida_orcamento:success, convertida_os:success, cancelada:danger`) — só centralizei e acrescentei rótulo em PT-BR; nenhuma regra de transição foi tocada.

## COMPONENTES REUTILIZADOS

Nenhum componente novo de terceiros. `IconField`/`InputIcon`/`InputText` (mesmo padrão de busca de Clientes/Veículos), `Tag` (já estava em uso, só passou a mostrar rótulo em vez do enum cru). AppShell/sidebar/header **não foram tocados** — item 25 do roteiro.

## BUSCA

**Adicionada** — a tela não tinha nenhum campo de busca antes desta etapa. Isso não é uma funcionalidade de backend nova: é o mesmo mecanismo de filtro client-side (`:filters` + `globalFilterFields` do `DataTable`) já usado em Clientes e Veículos, aplicado sobre os dados que a tela já buscava do Supabase — nenhuma query nova. Placeholder exatamente como pedido: "Buscar por veículo, cliente ou descrição", e os 4 campos (`veiculo.placa`, `veiculo.prefixo`, `veiculo.cliente.nome`, `descricao`) realmente participam da busca — o placeholder não promete nada que não funcione.

**Botão "Filtros" não implementado** — não existe nenhum filtro adicional real (por status, por período, etc.) além da busca por texto, então criar o botão seria simular uma funcionalidade inexistente (item 6 do roteiro é explícito sobre isso).

## TABELA

- **Veículo** (item 8): mesma prioridade visual dada à placa em Veículos — fonte monoespaçada + `font-weight: 600`. Prefixo mantido entre parênteses, sem inventar recombinação de dados.
- **Cliente** (item 9): nome do cliente preservado; adicionado um badge INTERNO/EXTERNO (mesmo componente visual criado em Clientes) ao lado do nome — o campo `tipo` **já era buscado** pela query (`cliente:clientes(id, nome, tipo)`) mas nunca era exibido. Exibi-lo aqui é "preservar a informação já disponível", exatamente como pedido no item 9, sem criar nova classificação.
- **Descrição** (item 10): truncamento com `ellipsis` (CSS, `max-width: 320px`) + tooltip nativo do navegador via atributo `title` — mesma solução "simples" já usada em Modelo (Veículos), sem registrar a diretiva `v-tooltip` do PrimeVue (não usada em nenhum outro lugar do app).
- **Criado em** (item 7): coluna nova, usando `criado_em`, campo que **já era buscado** pela query mas nunca era mostrado em nenhuma coluna. Zero impacto de backend — só passou a aparecer.
- **Status** (item 11): badge padronizado via `Tag` + `STATUS_SOLICITACAO`, mostrando rótulo em PT-BR (ex: "Em análise") em vez do valor cru do enum (ex: `em_analise`). Cores mantidas fiéis às severidades já existentes (violeta/azul=aberta, amarelo=em análise, verde=convertida, vermelho=cancelada). **Nenhum status novo, nenhuma mudança de regra de transição.**
- **Linhas** (item 13): confirmado que a tabela **nunca teve** comportamento de clique na linha (sem `@row-click`) — mantido assim, sem sugerir link onde não existe.
- **Ordenação** (item 14): a tabela original **não tinha nenhuma coluna ordenável** (nem `field`+`sortable` em nenhuma coluna) — diferente do que o item 14 supõe ("se alguma coluna já for ordenável"). Como nenhuma já era, nenhuma ordenação foi adicionada, para não implementar uma funcionalidade nova.

## AÇÕES

**Decisão consciente de não replicar o padrão `[editar] [⋮]`** usado em Clientes/Veículos. Motivo: Solicitações não tem uma ação "editar" — as ações reais são transições de fluxo condicionadas por status e por permissão (`Em Análise`, `Converter em Orçamento`, `Cancelar`), e já eram exibidas como botões com texto (não "ícones soltos sem contexto", que é o problema que o item 12 pede para evitar). Esconder "Converter em Orçamento" — a ação principal da tela — atrás de um menu de três pontos reduziria a agilidade que o próprio roteiro pede como resultado esperado. Em vez disso: os botões existentes foram padronizados visualmente (tamanho `small` consistente, espaçamento uniforme, `flex-wrap` para não quebrar layout), e o botão de cancelar (antes `pi-times` solto) passou a usar `pi-ban` — o mesmo ícone/padrão de "inativar" usado em Clientes/Veículos, para reforçar a linguagem visual comum. Nenhuma ação foi criada, removida ou teve sua condição (`podeGerir()`, status permitido) alterada.

## PAGINAÇÃO

Mesmo padrão de Clientes/Veículos: `currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} solicitações"`, total real calculado pelo `DataTable` a partir dos dados carregados.

## MODAL

Reorganizado em 2 blocos visuais (Veículo, Descrição), com subtítulo discreto "Preencha os dados abaixo para registrar a solicitação." — exatamente a estrutura sugerida nos itens 19-20. Mesmos 2 campos (nenhum novo), mesma validação (toast de aviso se veículo ou descrição estiverem vazios — não foi adicionada validação inline nova, para não inventar uma regra de validação que não existia). Placeholder discreto adicionado ao textarea ("Descreva o serviço solicitado"). Select de veículo mantém a mesma origem de dados e mesmo comportamento de carregamento (`filter`, `optionLabel="placa"`) — só herda o visual dark padrão do tema.

## RESPONSIVIDADE

Não validado ao vivo nesta sessão (ver limitação abaixo). Medidas tomadas: `.panel` com `overflow-x: auto`; abaixo de 720px, cabeçalho empilha e a busca perde largura máxima fixa — mesmo padrão de Clientes/Veículos.

## ESTADO VAZIO

Slot `#empty` customizado (antes a tabela sem dados mostrava só o cabeçalho das colunas, exatamente o problema descrito no item 16):
1. **Erro de carregamento** → "Não foi possível carregar as solicitações."
2. **Busca ativa sem resultado** → "Nenhuma solicitação encontrada para os critérios informados."
3. **Nenhuma solicitação cadastrada** → "Nenhuma solicitação registrada." + botão "Nova Solicitação"

## INVALID PRIMEUI LICENSE

**Confirmado que ainda aparece**, mesma causa raiz documentada nas 3 etapas anteriores (não resolvida por decisão sua, adiada 2 vezes). Verificado nesta sessão que continua idêntico ao carregar a tela de login — não é regressão nova, não foi mascarado com CSS.

## BUILD

```
npm run build
```
executado em `frontend/` — **sucesso**, sem erros.

## REGRESSÃO

- **Mesma limitação das etapas anteriores:** sem credenciais válidas de DEV/QA nesta sessão, não foi possível validar visualmente ao vivo (lista com dados, estado vazio, busca, modal, seleção de veículo, salvar, cancelar, paginação, ações por status).
- **O que foi validado:**
  - `npm run build` completo sem erros.
  - Tela de login carrega normalmente, sem novo erro de console.
  - Revisão linha a linha do arquivo reescrito: `erro`/`temFiltroAtivo`/`formatarData` usados corretamente; `carregar()`, `salvar()`, `marcarEmAnalise()`, `confirmarCancelamento()`, `converterEmOrcamento()` permanecem idênticas, só ganharam o flag `erro` em `carregar()`.
  - `STATUS_SOLICITACAO` conferido contra o mapa local `severidadeStatus` original — mesmas 5 chaves, mesmas severidades.

## MELHORIAS FUTURAS NÃO IMPLEMENTADAS

1. **Extrair CSS compartilhado entre telas de listagem** (Clientes, Veículos, Solicitações) para uma folha comum — continua duplicado por não tocar em arquivos de etapas já entregues (mesma nota já registrada em UX-VEICULOS-01).
2. **Botão "Filtros"** — só faz sentido quando existir um filtro real além da busca (ex: por status).
3. **Ordenação de colunas** — a tabela nunca teve nenhuma coluna ordenável; se isso vier a ser pedido, é uma decisão de produto (quais colunas fazem sentido ordenar), não só uma mudança visual.
4. **Downgrade do PrimeVue** (5→4.5.5) para eliminar o aviso "Invalid PrimeUI License" — mapeado, ainda aguardando autorização (adiado 2x, sem mudança nesta etapa).
5. **Validação visual ao vivo** do fluxo completo — pendente de credenciais de teste válidas do ambiente DEV/QA.
