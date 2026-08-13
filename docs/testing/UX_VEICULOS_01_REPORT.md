# UX-VEICULOS-01 — Redesign da tela de Veículos

Data: 2026-08-13
Escopo: redesign visual da tela de Veículos, replicando a linguagem já aplicada em Login, Dashboard e Clientes. Sem alteração de backend, banco, RPCs, regras de negócio ou permissões.

---

## TELA ALTERADA

`frontend/src/views/veiculos/VeiculosList.vue` — template e estilo reescritos. Lógica preservada integralmente: consulta Supabase (mesmos campos `id, placa, prefixo, modelo, ano, cliente_id, cliente:clientes(nome)`, mesmo filtro `deleted_at is null`, mesma ordenação por `placa`), criação/edição via `Dialog` (mesmos campos, mesmo payload), inativação (mesma regra, sem restrição por tipo — igual a antes), navegação para histórico do veículo (rota já existente `/veiculos/:id/historico`).

## COMPONENTES REUTILIZADOS

Nenhum componente novo de terceiros. `primevue/menu` (mesmo componente já usado pela primeira vez em `ClientesList.vue`) para o menu de três pontos. AppShell/sidebar/header **não foram tocados** — item 23 do roteiro.

## BUSCA

Restilizada com os mesmos tokens/overrides usados em Clientes (fundo `--surface`, borda `--border-panel`, foco `--primary`). Placeholder alterado para "Buscar por placa, prefixo ou modelo" (era "...ou proprietário"), conforme pedido no item 5. Para o placeholder não prometer uma busca que não existe, `modelo` foi adicionado a `globalFilterFields` (antes só buscava `placa`, `prefixo`, `cliente.nome`) — é uma extensão de um array já usado pelo mecanismo de busca existente, não uma funcionalidade nova; a busca por nome do proprietário (`cliente.nome`) foi mantida funcionando, só não é mais anunciada no placeholder.

## FILTROS

**Botão "Filtros" não implementado**, pelo mesmo motivo já registrado em UX-CLIENTES-01: não existe hoje nenhum filtro adicional real na tela de Veículos além da busca por texto — não há tabs, não há filtro por proprietário interno/externo, tipo de veículo, etc. Criar o botão sem filtro real atrás violaria o item 6 do próprio roteiro ("Se atualmente não houver filtros adicionais implementados: manter apenas a busca, sem botão fictício").

## TABELA

- **Placa** (item 8): destaque moderado — fonte monoespaçada (`var(--font-mono)`, já existente no design system) + `font-weight: 600` + leve `letter-spacing`, sem virar badge.
- **Prefixo** (item 9): mostra `—` quando vazio/nulo, em vez de célula em branco.
- **Modelo** (item 10): sem largura fixa/truncamento forçado — a coluna ocupa o espaço que precisar. Como concessão simples para nomes muito longos em telas estreitas, o texto recebeu o atributo HTML nativo `title` (tooltip do próprio navegador ao passar o mouse) — não foi registrada a diretiva `v-tooltip` do PrimeVue porque ela não está instalada/registrada em `main.js` em nenhum outro lugar do app, e registrá-la globalmente para isso seria uma mudança maior do que o item 10 pede ("somente se o componente já suportar isso de forma simples").
- **Ano** (item 11): mantido simples, sem badge/ícone, só centralizado (`bodyClass="col-numero"`) para melhor leitura de um número curto.
- **Proprietário** (item 12): mantido `data.cliente?.nome` (com fallback `—` se por algum motivo vier vazio). Confirmado que **não existia** navegação da célula/linha para o cliente antes desta etapa — nada foi adicionado, conforme "não criar nova relação apenas no frontend".
- **Linhas** (item 14): confirmado que a tabela de Veículos **nunca teve** `@row-click` (diferente de Clientes, que navega para o detalhe do cliente ao clicar na linha). Por isso as linhas **não** receberam `cursor: pointer` nem qualquer estilo de "link" — só o hover padrão de leitura (`stripedRows` + hover do tema), exatamente para não sugerir um clique que não existe (item 14: "Não transformar toda linha em link se isso não existir hoje").
- **Ordenação** (item 15): mantida (`sortable` em Placa e Prefixo, como já era); ícone é o padrão do PrimeVue, que já indica coluna ordenável e direção.

## AÇÕES

Reduzidas visualmente ao padrão `[editar] [⋮]` de Clientes. Antes eram 3 ícones soltos na linha (Histórico, Editar, Inativar — o de Inativar em vermelho). Agora: "Editar" continua como botão de lápis; "Histórico" e "Inativar" (as duas ações extras, ambas já existentes e sempre disponíveis para qualquer veículo, sem restrição de tipo) foram movidas para o menu de três pontos. Nenhuma ação foi criada ou removida.

## PAGINAÇÃO

Mesmo padrão de Clientes: `currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} veículos"`, usando o total real calculado pelo próprio `DataTable`. **Seletor de itens por página não adicionado** — não existia (`rowsPerPageOptions`) antes desta etapa e o item 16 é explícito: "só deve existir se já houver suporte funcional."

## FORMULÁRIO

O modal de criação/edição (mesmos campos: placa, prefixo, modelo, ano, proprietário) foi reorganizado em 3 blocos visuais, exatamente como sugerido no item 21: **Identificação** (placa, prefixo), **Veículo** (modelo, ano), **Vínculo** (proprietário). Nenhum campo novo. Labels que antes usavam uma cor cinza hardcoded (`#4b5563`, resquício do tema claro anterior) agora usam o token `--text-muted`, consistente com o resto do app.

## RESPONSIVIDADE

Não validado ao vivo nesta sessão (mesma limitação das etapas anteriores — ver REGRESSÃO). Medidas tomadas: `.panel` com `overflow-x: auto` (scroll horizontal controlado em vez de quebra de layout); abaixo de 720px, o bloco título+botão empilha em coluna e a busca perde a largura máxima fixa — mesmo padrão de `ClientesList.vue`.

## ESTADO VAZIO

Slot `#empty` customizado (não existia — antes, sem dados, a tabela mostrava só o cabeçalho das colunas, exatamente o problema descrito no item 17):
1. **Erro de carregamento** → "Não foi possível carregar os veículos."
2. **Busca ativa sem resultado** → "Nenhum veículo encontrado para esta busca."
3. **Nenhum veículo cadastrado** → "Nenhum veículo cadastrado." + botão "Novo Veículo"

(Não há caso de "filtros" separado da busca, porque não existe filtro adicional nesta tela — ver seção FILTROS.)

## INVALID PRIMEUI LICENSE

**Ainda presente, mesma causa raiz já documentada e não resolvida por decisão sua** (adiada em UX-LOGIN-01 e UX-DASHBOARD-01). Confirmei que continua aparecendo, idêntico, ao carregar a tela de login nesta sessão — não é uma regressão nova desta etapa nem foi mascarado com CSS. Segue pendente da mesma decisão (downgrade `primevue` 5→4.5.5, já mapeado).

## BUILD

```
npm run build
```
executado em `frontend/` — **sucesso**, sem erros.

## REGRESSÃO

- **Mesma limitação das duas etapas anteriores:** não foi possível autenticar no ambiente DEV/QA nesta sessão para validar visualmente ao vivo (veículo existente, busca por placa/prefixo/modelo, ordenação, paginação, Novo Veículo, editar, veículo de frota própria vs. externo, estado vazio).
- **O que foi validado:**
  - `npm run build` completo sem erros.
  - Tela de login carrega normalmente após a mudança, sem novo erro de console (só o aviso PrimeUI já conhecido e o 400 esperado da tentativa de login).
  - Revisão linha a linha do arquivo reescrito: `erro`/`temFiltroAtivo` usados corretamente, `menuAcoes`/`veiculoMenuAtual`/`itensMenuAcoes` seguem exatamente o mesmo padrão já usado (e já revisado) em `ClientesList.vue`.
  - Nenhuma alteração em `carregar()` (além do flag `erro`), `salvar()`, `abrirEdicao()`, `inativar()`, `confirmarInativacao()` — mesma regra de negócio, mesmas queries.

## MELHORIAS FUTURAS NÃO IMPLEMENTADAS

1. **Extrair CSS compartilhado entre telas de listagem** (Clientes, Veículos e futuras telas irmãs) para uma folha comum, em vez de duplicar o mesmo bloco de estilo em cada `<style scoped>`. Não foi feito nesta etapa para não precisar tocar `ClientesList.vue`, de uma etapa já entregue, fora do escopo desta ficha. Baixo risco, puramente organizacional.
2. **Botão "Filtros"** — só faz sentido quando existir algum filtro real além da busca (ex: por proprietário interno/externo, por ano, por modelo).
3. **Seletor de itens por página** — não existe hoje; se vier a ser implementado, também deve seguir o padrão visual já definido.
4. **Downgrade do PrimeVue** (5→4.5.5) para eliminar o aviso "Invalid PrimeUI License" — mapeado, ainda aguardando autorização (adiado 2x nas etapas anteriores, sem mudança nesta).
5. **Validação visual ao vivo** do fluxo completo — pendente de credenciais de teste válidas do ambiente DEV/QA.
