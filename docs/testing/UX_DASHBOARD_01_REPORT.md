# UX-DASHBOARD-01 — Redesign do Dashboard Executivo

Data: 2026-08-13
Escopo: redesign visual do Dashboard e refinamento visual do AppShell (sidebar/header), sem alteração de backend, banco, RPCs, regras de negócio ou permissões.

---

## TELAS ALTERADAS

- `frontend/src/views/dashboard/DashboardView.vue` — reescrita completa do template/estilo. Toda a lógica de dados (queries Supabase, cálculos de KPI, filtro de período, `calcularMargemPeriodo`) foi preservada; a única mudança funcional é a adição de tratamento de erro visível (ver seção ERROS) e de uma consulta extra somente-leitura já existente no backend (`rpc_status_configuracao_sistema`, ver KPIs/Alertas).
- `frontend/src/layouts/AppShell.vue` — iniciais do usuário no avatar do rodapé da sidebar (antes era um círculo vazio) e responsividade (sidebar colapsa para ícone-only em telas ≤1280px). Navegação, permissões (`itensMenu`) e lógica de logout **não foram tocadas**.
- `frontend/src/style.css` — tokens de design adicionados (não substituídos).

## COMPONENTES CRIADOS/REUTILIZADOS

- **Criado:** `frontend/src/constants/statusVisual.js` — mapa único de cor/rótulo/severidade por status de OS, orçamento e cobrança, para o Dashboard não duplicar mais uma 4ª cópia do mapa `severidadeStatus` que já existe (com pequenas variações) em `OrdensServicoList.vue`, `OrcamentosList.vue` e `CobrancasList.vue`. Os valores foram conferidos contra o enum real do banco (`status_os`, `status_orcamento`, `status_cobranca`) e contra os mapas locais já existentes nas 3 telas citadas — não foi inventado nenhum status novo.
- **Reutilizados (já existentes no app):** `primevue/chart` (bar + doughnut), `primevue/datatable`, `primevue/datepicker`, `primevue/tag`, `primevue/message`, `primevue/skeleton` (novo uso neste ticket, componente já instalado).
- Nenhum componente novo de terceiros foi instalado.

## DESIGN TOKENS

Adicionados em `frontend/src/style.css` (`:root`), todos como **aliases/extensões** dos tokens já existentes — nada foi renomeado, então nenhuma tela que já usa os tokens antigos foi afetada:

```
--surface: var(--panel-card-bg)
--surface-hover: rgba(255,255,255,0.09)
--primary: var(--accent-1)
--primary-hover: #7c4de8

--status-rascunho, --status-enviado, --status-aguardando, --status-aprovado,
--status-parcial, --status-rejeitado, --status-aberta, --status-em-execucao,
--status-em-diagnostico, --status-aguardando-teste, --status-concluida,
--status-liberada, --status-cancelada, --status-garantia
```

Os mesmos valores hex de status também existem em `frontend/src/constants/statusVisual.js` (comentado como fonte espelhada), porque gráficos Chart.js precisam de string de cor em JS e não conseguem ler `var()` do CSS diretamente.

**Limitação registrada:** a centralização de cores de status descrita no roteiro (item 12/13) foi feita como uma nova fonte única (`statusVisual.js` + tokens CSS) consumida pelo Dashboard, mas as 3 telas de listagem (`OrdensServicoList.vue`, `OrcamentosList.vue`, `CobrancasList.vue`) continuam com seus mapas locais próprios — migrá-las para a fonte única está fora do escopo desta etapa (seria uma alteração em telas fora do Dashboard/login, com risco de regressão sobre um roteiro que não é este). Ver MELHORIAS FUTURAS.

## KPIs UTILIZADOS

Todos calculados a partir de dados já buscados pelo Dashboard atual — nenhum cálculo novo, nenhum número fixo. A faixa de KPIs (Bloco A) é dinâmica: só aparece o que o perfil logado tem permissão de ver, respeitando os mesmos 3 flags que já existiam (`podeVerServicos`, `podeVerFinanceiro`, `podeVerEstoque`):

| KPI | Origem do dado |
|---|---|
| OS em aberto | `ordensServico` filtrado por status ≠ liberada/cancelada (já existia) |
| Liberadas no período | `ordensServico` filtrado por status=liberada + `dentroDoPeriodo` (já existia) |
| Tempo médio até liberação | média de `data_liberacao - data_abertura` das liberadas no período (já existia) |
| A receber | soma de saldo de `parcelas` pendentes (já existia) |
| Recebido no período | soma de `recebimentos` no período (já existia) |
| Valor total em estoque | `saldo_atual × custo_medio` de `pecas` (já existia) |

Nenhum KPI mostra "+X% vs período anterior" — o sistema não calcula período anterior em nenhum lugar hoje, então essa comparação foi omitida integralmente (não inventada), conforme instrução explícita do roteiro.

Métricas que já existiam mas foram **realocadas** (não removidas) para os blocos B/C, para não lotar a faixa de KPI: Vencido, Margem no período, Peças em ruptura, Peças abaixo do mínimo.

**Nova métrica adicionada** (Bloco C — Financeiro): "Ticket médio (OS externas, no período)" = receita externa do período ÷ quantidade de OS externas liberadas no período. Os dois valores (`receitaExternaPeriodo`, `qtdOsExternasPeriodo`) já eram computados internamente por `calcularMargemPeriodo()` para calcular a margem — só passaram a ser expostos como refs; nenhuma query nova foi criada para isso.

## KPIs NÃO DISPONÍVEIS

- **Comparação percentual vs. período anterior** (ex: "+12% vs período anterior") — omitida. Exigiria computar o mesmo conjunto de métricas para um segundo intervalo de datas; hoje isso não existe em nenhuma tela do sistema.
- **"Top serviços" (item 10 do roteiro)** — **bloco não renderizado**. O Dashboard hoje não busca nenhum dado em nível de item/serviço (`orcamento_itens` ou catálogo de serviços) — só busca OS, parcelas, recebimentos e peças. Construir esse ranking exigiria uma consulta nova (join com itens de orçamento + agregação por serviço), o que é mais do que "reaproveitar dados já buscados". Registrado como MELHORIA FUTURA.
- **Checklist incompleto (alerta, item 11)** — **omitido**. Não existe, em lugar nenhum do backend, uma consulta agregada de "OS com checklist incompleto" — só existe o detalhe por OS individual. Registrado como MELHORIA FUTURA.
- **Custo de manutenção interna** (exemplo do item 5) — **omitido**. O Dashboard atual não busca `estoque_movimentos`/custos de OS internas de forma agregada (só busca isso pontualmente, por OS, dentro de `calcularMargemPeriodo`, e só para OS externas). Construir isso exigiria nova lógica de agregação, não reaproveitamento direto.

## GRÁFICOS

1. **"OS por status"** (barra) — já existia; mantido com os mesmos dados (`ordensServico` agrupado por status), agora com rótulos em português e cor individual por status (via `statusVisual.js`) em vez de uma cor roxa única para todas as barras.
2. **"OS por situação"** (doughnut, novo — item 8 do roteiro) — mesmos dados do gráfico de barra (nenhuma busca nova), com total no centro e legenda lateral (quantidade + percentual real, calculado client-side a partir da mesma lista já carregada).
3. **"Recebido por mês (últimos 6 meses)"** (linha) — já existia; mantido sem alteração de lógica, só restilizado.
4. **Estado vazio** (item 7/15) — se `ordensServico.length === 0`, os dois gráficos de OS são substituídos por "Nenhuma Ordem de Serviço encontrada." em vez de um gráfico vazio.

## ALERTAS

Bloco D novo, construído só com sinais que o sistema já consegue identificar hoje, cada um com navegação para a tela correspondente (rotas já existentes no `router`, sem rota nova):

- **Cobranças vencidas** (crítico) — `totalVencido > 0` → `/financeiro/cobrancas`
- **Peças em ruptura** (crítico) — `pecasRuptura.length > 0` → `/estoque/pecas`
- **Peças abaixo do mínimo** (atenção) — `pecasAbaixoMinimo.length > 0` → `/estoque/pecas`
- **Configuração inicial pendente** (informativo) — usa a RPC já existente `rpc_status_configuracao_sistema()` (mesma usada por `StatusConfiguracaoView.vue`), restrita aos mesmos perfis que a própria RPC já aceita (`encarregado`, `suporte_administrativo`, `administrador_tecnico` — não inclui `diretoria`, replicando a regra do backend) → `/admin/status-configuracao`

Se nenhum alerta estiver ativo, mostra estado "Tudo em dia" (verde), em vez de simplesmente não mostrar nada ou mostrar uma seção vazia estranha.

**Nota sobre item 20 (não alterar backend):** adicionar a chamada a `rpc_status_configuracao_sistema()` no Dashboard **não** é uma RPC nova — é a mesma função já existente, só passou a ser consultada de um segundo lugar (leitura, mesma política de permissão que ela já aplica internamente).

## RESPONSIVIDADE

Testado via build + inspeção de código (ver limitação de validação visual abaixo). Breakpoints adicionados:

- `AppShell.vue`: ≤1280px — sidebar colapsa para ícone-only (76px, sem rótulos de texto), preservando todos os links/permissões.
- `DashboardView.vue`: ≤1180px — o par de gráficos (barra + donut) empilha em coluna única. ≤720px — cabeçalho e filtro de período empilham, legenda do donut fica abaixo do gráfico em vez de ao lado.
- Grades de KPI e mini-KPI usam `repeat(auto-fit, minmax(...))`, então já quebram sozinhas em qualquer largura intermediária (1920/1440/1366/notebook) sem precisar de um breakpoint específico para cada uma.

## INVALID PRIMEUI LICENSE

**Causa raiz confirmada (igual à identificada na etapa UX-LOGIN-01):** o pacote `primevue@5.0.1`, usado em todo o app (não é específico do Dashboard), depende de `@primeui/license-manager`. Sem uma chave de licença configurada em `app.use(PrimeVue, { license: ... })` (`frontend/src/main.js`), esse pacote dispara, na inicialização do app:
- `console.warn('[PrimeUI] PrimeUI license is not configured.')`
- Um banner fixo vermelho "Invalid PrimeUI License" injetado via shadow DOM fechado no canto da tela.

**Investigação adicional feita nesta etapa:** confirmei via `npm view` que `primevue@4.5.5` (última versão da major anterior) **não tem** `@primeui/license-manager` como dependência — é a única forma real de eliminar o aviso sem comprar uma licença em primeui.store. Levantei o caminho completo do downgrade (`primevue` 5.0.1→4.5.5 + pacote de tema `@primeuix/themes`→`@primevue/themes@4.5.4`).

**Decisão:** perguntei novamente se deveria executar esse downgrade agora, deixando claro que é uma troca de dependência core que afeta o app inteiro (não só o Dashboard) e contraria o próprio item 20 do roteiro ("baixo risco"). Você optou por **registrar e adiar de novo**. Não ocultei o aviso com CSS (isso violaria explicitamente o item 18) — ele continua aparecendo, sem tentativa de mascaramento, exatamente como antes desta etapa.

## BUILD

```
npm run build
```
executado em `frontend/` — **sucesso**, sem erros de compilação/tipo. Saída completa gerada em `frontend/dist/` (todas as telas do app, incluindo `DashboardView`, `AppShell`, `LoginView` etc., empacotadas sem falha).

## REGRESSÃO

- **Login → Dashboard (fluxo completo):** não foi possível validar visualmente de ponta a ponta nesta sessão — as credenciais de teste do ambiente DEV/QA fornecidas retornaram "E-mail ou senha inválidos" e você optou por não reenviar novas credenciais. **Isso é uma limitação de validação, não uma falha encontrada.**
- **O que foi validado de fato:**
  - `npm run build` completo sem erros (compila todas as ~50 telas do app, prova que não há erro de sintaxe/import quebrado em nenhuma delas, incluindo as que não foram tocadas).
  - Tela de login renderiza normalmente após as mudanças em `style.css` (tokens compartilhados) — sem novo erro de console além do aviso PrimeUI já conhecido.
  - Nenhuma regra de negócio, RLS, RPC ou fluxo de dado foi alterado — toda a lógica de `<script setup>` do Dashboard permaneceu com os mesmos cálculos, só reorganizando *onde* os resultados são lidos (refs em vez de índice posicional de array) e adicionando tratamento de erro que antes não existia.
  - Revisão de código linha a linha de `DashboardView.vue` e `AppShell.vue` após a reescrita, conferindo que nenhuma referência a `statusOrdem`/`severidadeStatus` (removidos) ficou órfã.
- **Não validado nesta sessão (requer credenciais reais):** Clientes, Veículos, Orçamentos, OS, Financeiro — nenhum desses arquivos foi alterado nesta etapa, então o risco de regressão neles é o mesmo de antes (zero mudança), mas não houve confirmação visual ao vivo.

## MELHORIAS FUTURAS NÃO IMPLEMENTADAS

1. **Downgrade de `primevue` 5→4** para eliminar de vez o aviso "Invalid PrimeUI License" em todo o app — decisão adiada por você nesta etapa (ver seção acima). Requer testar todas as telas do app antes de aplicar.
2. **"Top serviços"** — precisa de uma consulta nova agregando `orcamento_itens`/catálogo de serviços por quantidade/faturamento. Não existe hoje nenhuma consulta desse tipo em nenhuma tela do app.
3. **Alerta de "checklist incompleto"** — precisa de uma consulta agregada nova (contagem de OS com checklist pendente); hoje só existe o detalhe por OS individual.
4. **Comparação "% vs. período anterior"** em qualquer KPI — precisa computar o mesmo conjunto de métricas para um segundo intervalo de datas (dobra o número de queries do Dashboard). Fora do escopo de uma etapa "baixo risco".
5. **Centralizar de fato as cores de status** — hoje existem *duas* fontes (a nova `statusVisual.js`, usada só pelo Dashboard, e os 3 mapas locais em `OrdensServicoList.vue`/`OrcamentosList.vue`/`CobrancasList.vue`, inalterados). Migrar essas 3 telas para importar de `statusVisual.js` eliminaria a duplicação de vez, mas está fora do escopo desta etapa (login/dashboard).
6. **Custo de manutenção interna** como KPI — exigiria agregar `estoque_movimentos` por OS interna de forma sistemática (hoje só é feito pontualmente para OS externas, dentro de `calcularMargemPeriodo`).
7. **Validação visual ao vivo do fluxo logado completo** — pendente de credenciais de teste válidas do ambiente DEV/QA.
