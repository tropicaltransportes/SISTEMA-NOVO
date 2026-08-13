# UX-CLIENTES-01 — Redesign da tela de Clientes

Data: 2026-08-13
Escopo: redesign visual da tela de Clientes, seguindo a linguagem já definida em Login (UX-LOGIN-01) e Dashboard (UX-DASHBOARD-01). Sem alteração de backend, banco, RPCs, regras de negócio ou permissões.

---

## TELA ALTERADA

`frontend/src/views/clientes/ClientesList.vue` — template e estilo reescritos. Lógica preservada integralmente: consulta Supabase (mesmos campos, mesmo filtro `deleted_at is null`, mesma ordenação), criação/edição via `Dialog` (inalterado), inativação (mesma regra — só clientes `tipo !== 'interno'` podem ser inativados), busca (`globalFilterFields`, só ganhou `email` na lista de campos buscáveis — texto do placeholder já prometia "ou e-mail" e o campo `email` já era buscado visualmente na tabela, então incluí no filtro para a busca corresponder ao que o placeholder diz).

## COMPONENTES REUTILIZADOS

Nenhum componente novo de terceiros. Reaproveitados: `primevue/datatable`, `column`, `button`, `dialog`, `inputtext`, `select`, `iconfield`/`inputicon` (já em uso) e `primevue/menu` (já instalado no projeto, usado pela primeira vez aqui para o menu de três pontos). AppShell/sidebar/header são exatamente os mesmos do redesign do Dashboard — **nenhuma linha de `AppShell.vue` foi tocada nesta etapa**, conforme item 21 do roteiro.

## TABS

Mantidas as mesmas 3 (Todos/Internos/Externos), mesma variável `filtroTipo`, nenhuma lógica nova. Visual: tab ativa agora com preenchimento sólido `var(--primary)` + texto branco (antes era um fundo violeta translúcido); tabs inativas sem caixa, hover sutil (`--surface-hover`).

## BUSCA

Restilizada com os tokens do design system (fundo `--surface`, borda `--border-panel`, foco `--primary`) em vez do estilo padrão do PrimeVue sem override. Mesma lógica de busca (`filtro` + `globalFilterFields`), só a apresentação mudou.

**Botão "Filtros" do item 7 do roteiro — não implementado.** Hoje a tela só tem dois mecanismos de filtragem reais: as tabs (tipo) e a busca por texto. Não existe nenhum filtro adicional funcional (por status, por período, etc.) para colocar atrás de um botão "Filtros" — criar esse botão sem nenhum filtro real atrás dele seria simular uma funcionalidade que não existe, o que o próprio roteiro proíbe explicitamente ("Se hoje não existe filtro adicional real: não inventar apenas para imitar a referência"). Registrado como melhoria futura caso um filtro real (por status, por período de cadastro etc.) venha a ser implementado.

## TABELA

- **Avatar com iniciais** (item 10): antes era um círculo colorido sem letras; agora mostra as iniciais reais extraídas do campo `nome` (primeira letra do primeiro e do último nome). Paleta reduzida a 4 variações de violeta (antes usava roxo/azul/verde/amarelo/vermelho misturados) para reforçar a identidade única da marca.
- **Badge de Tipo** (item 11): trocado de `Tag` do PrimeVue (que não tem uma severidade "violeta" nativa) por um badge customizado com os tokens do app — Interno = azul (`--info`/`--info-bg`), Externo = violeta (`--accent-text`/`--accent-soft-bg`), exatamente como pedido.
- **Coluna Status — não adicionada.** A consulta atual (`'.is('deleted_at', null)'`) já filtra clientes inativos *fora* da lista inteira — ou seja, hoje a tela nunca mostra um cliente inativo, sempre. Uma coluna "Status" nessas condições sempre mostraria "Ativo" (informação vazia/enganosa) ou exigiria mudar a consulta para também trazer inativos — o que é uma mudança de comportamento funcional (o que aparece na listagem), não uma mudança visual, e está fora do escopo desta etapa. Registrado como melhoria futura (ver seção final) porque é uma decisão de produto, não só de estilo.
- **Ações** (item 14): "Editar" continua como ícone de lápis. A ação "Inativar" (que já existia, restrita a clientes `tipo !== 'interno'`) foi movida para um menu de três pontos (`primevue/menu`) em vez de um ícone vermelho solto ao lado do lápis — nenhuma ação nova foi criada, só reorganizada visualmente, e ainda com a mesma confirmação (`confirm.require`) de antes.
- **Ordenação** (item 15): mantida a mesma (`sortable sortField="nome"` já existia); ícone/estado é o padrão do PrimeVue, que já indica coluna ordenável e direção — nada customizado além disso.

## PAGINAÇÃO

Adicionado `currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} clientes"` — usa o total real calculado pelo próprio `DataTable` a partir dos dados já carregados (client-side, como já era), sem nenhuma contagem inventada. Paginador visual (primeira/anterior/páginas/próxima/última) mantido nos componentes padrão do PrimeVue, agora herdando os tokens do tema.

## ESTADOS VAZIOS

Adicionado slot `#empty` customizado que distingue 3 casos (nenhum existia antes — a tabela só mostrava o texto genérico padrão do PrimeVue):
1. **Erro de carregamento** → "Não foi possível carregar os clientes." (ver seção ERROS)
2. **Filtro/busca ativos sem resultado** → "Nenhum cliente corresponde aos filtros informados."
3. **Nenhum cliente cadastrado** → "Nenhum cliente encontrado." + botão "Novo Cliente"

## ERROS

Antes: se a consulta falhasse, só aparecia um toast e a tabela ficava com o array vazio anterior — indistinguível visualmente de "não há clientes". Agora: um `erro` (ref) é setado em caso de falha e o slot `#empty` mostra explicitamente "Não foi possível carregar os clientes." em vez do texto genérico de lista vazia (o toast de erro, que já existia, foi mantido).

## RESPONSIVIDADE

Não validado ao vivo nesta sessão (ver limitação abaixo). Medidas tomadas via CSS: `.panel` (contêiner da tabela) ganhou `overflow-x: auto`, então em telas estreitas a tabela rola horizontalmente em vez de quebrar o layout — cobre o caso descrito no item 20 ("permitir scroll horizontal controlado"). Abaixo de 720px, o cabeçalho (tabs + busca + botão) empilha em coluna única e a busca deixa de ter `max-width` fixo.

## INVALID PRIMEUI LICENSE

**Sem mudança de status nesta etapa.** Mesma causa raiz já identificada e documentada em UX-LOGIN-01/UX-DASHBOARD-01 (`primevue@5.0.1` → `@primeui/license-manager`, afeta o app inteiro). Você já decidiu duas vezes adiar o downgrade que resolveria isso de fato (a única forma real, sem comprar licença). Não tentei mascarar o aviso com CSS aqui também. Se quiser que eu execute o downgrade agora, é só avisar — o caminho já está mapeado (`primevue` 5.0.1→4.5.5 + `@primevue/themes@4.5.4`).

## BUILD

```
npm run build
```
executado em `frontend/` — **sucesso**, sem erros.

## REGRESSÃO

- **Limitação (igual às duas etapas anteriores):** não consegui autenticar no ambiente DEV/QA nesta sessão (mesmas credenciais fornecidas anteriormente retornaram "E-mail ou senha inválidos"), então não validei visualmente ao vivo: filtro Todos/Internos/Externos, busca, Novo Cliente, editar, paginação, cliente com/sem veículo, estado vazio.
- **O que foi validado:**
  - `npm run build` completo sem erros.
  - Tela de login carrega normalmente após a mudança (sem novo erro de console).
  - Revisão linha a linha do arquivo reescrito: nenhuma referência órfã ao `Tag` removido, `erro`/`temFiltroAtivo` usados corretamente, `menuAcoes`/`clienteMenuAtual` seguem o padrão padrão do PrimeVue `Menu` popup.
  - Nenhuma alteração em `carregar()`, `salvar()`, `inativar()`, `confirmarInativacao()` além da adição do flag `erro` — toda a regra de negócio e chamadas ao Supabase permanecem idênticas.

## MELHORIAS FUTURAS NÃO IMPLEMENTADAS

1. **Botão "Filtros"** — só faz sentido depois que existir algum filtro real além de tipo/busca (ex: por status, por período de cadastro, por presença de veículos). Hoje não haveria nada para colocar dentro dele.
2. **Coluna "Status" (Ativo/Inativo)** — decisão de produto pendente: a consulta atual só busca clientes ativos (`deleted_at is null`); mostrar status exigiria decidir se a listagem passa a trazer também os inativos (mudança de comportamento, não só visual).
3. **Downgrade do PrimeVue** (5→4) para eliminar de vez o aviso "Invalid PrimeUI License" — mapeado, aguardando autorização (adiado 2x).
4. **Validação visual ao vivo** do fluxo completo — pendente de credenciais de teste válidas do ambiente DEV/QA.
