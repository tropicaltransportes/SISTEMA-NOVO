# OS-UX-01 — Reestruturação da tela de detalhe da Ordem de Serviço

Reorganização de UI/UX de `frontend/src/views/os/OrdemServicoDetalhe.vue`
(era 1252 linhas, rolagem única, sem hierarquia visual, CSS com hex fixo
não alinhado ao dark premium do resto do app) em cabeçalho-resumo + barra
de etapas + 6 abas + cards. **Nenhuma RPC, cálculo, permissão ou estado da
OS foi alterado** — as únicas mudanças de dado são leituras adicionais
(read-only) descritas abaixo. Ambiente: DEV/QA (`jzjbiejmcaygwycvqggm`).
Nada promovido a produção nesta rodada.

## ESTRUTURA ANTERIOR

Um único `<script setup>` de 1252 linhas com toda a lógica (checklist,
apontamento, peças, fotos, adicionais, garantia) e um único `<template>`
em rolagem vertical contínua: cabeçalho simples → parágrafos de info →
botões de transição de status misturados com "Relatório de Encerramento"/
"Relatório de Garantia" → 5 seções (`Checklist Técnico`, `Apontamento de
Execução`, `Itens de Mão de Obra`, `Peças Utilizadas`, `Fotos`,
`Adicionais`) empilhadas com `<h3>` + `border-top`, sem cards, sem estado
vazio tratado (`<p class="hint">Nenhuma foto anexada ainda.</p>`), CSS com
cores hex fixas (`#e5e7eb`, `#6b7280`) — nunca migrado pro design system
dark do resto do app (`--surface`/`--card-radius`/`--border-panel`, já
usados em `DashboardView.vue`/`OrcamentosList.vue`). Sem componentes
filhos, sem abas, sem trilha de histórico.

## NOVA ESTRUTURA

Cabeçalho-resumo (2 colunas) → barra de etapas (ou badge terminal quando
cancelada) → `Tabs`/`TabList`/`Tab`/`TabPanels`/`TabPanel` do PrimeVue 5
(composable API — primeira vez usada no app; confirmado no código-fonte do
componente que todos os painéis ficam montados e só o inativo recebe
`display:none` via `v-show` interno, então **nenhuma ref/computed/função
mudou de escopo** — toda a lógica original permanece intocada no mesmo
arquivo, só o `<template>` foi reorganizado). Todos os 15 `supabase.rpc(...)`
e toda leitura/escrita `.from()`/`.storage.from()` originais mantiveram
nome, parâmetros e ordem idênticos — conferido linha a linha contra o
arquivo original durante a implementação, não de memória.

**Achado real durante a implementação, corrigido na hora:** a barra de
etapas do estado `aguardando_aprovacao` não tinha posição óbvia no grafo
real (`aberta → em_diagnostico → [aguardando_aprovacao opcional] →
em_execucao → aguardando_teste → concluida → liberada`) — o mockup de
referência sugeria esse estado depois de "Execução", o que está errado
frente ao state machine real (`transicoesDisponiveis`, linha 216-228 do
arquivo original): ele existe só entre Diagnóstico e Execução. Resolvido
tratando `aguardando_aprovacao` como selo secundário no passo "Diagnóstico"
(index 1), não como passo próprio — evita afirmar uma ordem de estados que
o backend não segue.

## CABECALHO

Duas colunas: esquerda com código/nome (placa+prefixo), cliente, veículo,
tipo (badge Interna/Externa), abertura, previsão de conclusão (com botão
de edição inline, ícone-lápis); direita com o badge de status (agora vindo
de `constants/statusVisual.js` — `STATUS_OS[status].label/severidade` —
em vez do mapa local `severidadeStatus` que só mostrava `os.status` cru
em minúsculas; removido do script por ter ficado sem uso) e o grupo de
ações. Testado ao vivo em 8 status reais diferentes (aberta,
em_diagnostico, em_execucao, aguardando_teste, concluida, liberada,
cancelada, reaberta_garantia) — badge e ações batem exatamente com cada
um.

## AÇÕES

Ação primária (`.btn-gradiente`, mesmo gradiente já usado em
`OrcamentoPdf.vue`) quando existe só UMA transição não-destrutiva
disponível (`aberta`→Iniciar Diagnóstico, `aguardando_aprovacao`→Iniciar
Execução, `em_execucao`→Enviar p/ Teste, mais os botões dedicados Concluir/
Liberar/Abrir Garantia). Quando há duas transições empatadas
(`em_diagnostico`: "Enviar p/ Aprovação" x "Iniciar Execução" — o state
machine não codifica preferência entre elas), as duas ficam `outlined`,
peso igual — decisão derivada diretamente do array `transicoesDisponiveis`
(`length === 1` → gradiente; `length > 1` → outlined), não de uma lista
hardcoded, então continua correta se o mapa de transições mudar no futuro.
"Cancelar" sempre renderizado à parte, `severity="danger" outlined`, nunca
competindo com a ação primária — confirmado visualmente em `aberta`,
`em_diagnostico` e `aguardando_aprovacao` (os 3 status onde ele existe).
"Relatório de Encerramento"/"Relatório de Garantia" continuam `text`
(peso mínimo), mesma condição `v-if` de antes.

## BARRA DE ETAPAS

6 passos reais (Aberta/Diagnóstico/Execução/Teste/Concluída/Liberada — um
por status que o backend de fato produz, sem inventar nem colapsar
nenhum). Testado: `aberta` mostra passo 1 ativo, nenhum concluído;
`em_execucao` mostra passos 1-2 concluídos (ícone check) e passo 3 ativo;
`liberada` mostra todos concluídos até o passo 6 ativo — todos verificados
via inspeção real de classe CSS (`.etapa-atual`/`.etapa-concluida`), não
só visual. `cancelada` substitui a barra inteira por um badge terminal
("OS cancelada") — confirmado ao vivo. `reaberta_garantia` (status
vestigial — nenhuma transição neste arquivo o produz; toda garantia é uma
OS nova via `rpc_criar_os_garantia`) cai graciosamente pra nenhuma barra e
nenhum badge, só o Tag de status — confirmado ao vivo, sem erro.

## ABAS

6 abas via PrimeVue 5 `Tabs`: Visão Geral, Execução, Peças, Fotos,
Adicionais, Histórico (esta última só quando `podeVerHistorico`, RLS
espelhada). Testado clique real em todas — troca de painel confirmada por
inspeção de conteúdo renderizado. Nenhuma aba tem lógica nova de
carregamento — todas usam os mesmos arrays já carregados por `carregar()`.

**Visão Geral**: card "Garantia" (contextual, só quando aplicável),
"Custo Interno" (só OS interna com custo calculado), "Previsão de
Conclusão" (dedicado, além do atalho no cabeçalho — mesma ação,
`abrirPrazo()`, dois pontos de entrada), "Checklist Técnico" (com estado
vazio novo quando não há checklist definido e o usuário não pode definir
um), "Mão de Obra Prevista" (só quando há itens), e um card novo "Resumo
da OS" — contagens operacionais (apontamentos ativos, movimentações de
peça + custo, fotos, adicionais aguardando decisão) calculadas 100% a
partir de arrays já carregados, zero fetch novo. **"Observações Gerais"
(item 8 do pedido) foi omitido de propósito** — `ordens_servico` não tem
nenhuma coluna de observação livre (o único `observacao` existente é por
apontamento, em `os_executores`, já mostrado na aba Execução); mostrar um
card permanentemente vazio seria pior que não ter o card, e inventar a
coluna estaria fora do escopo desta etapa (proibido mexer em banco).

**Execução / Peças / Fotos / Adicionais**: conteúdo movido sem alteração
de lógica — mesmos formulários, mesmas `DataTable`, mesmo
`v-if`/RBAC/parâmetros de RPC. `DataTable` de Execução e Peças ganharam
slot `#empty` (não tinham nenhum antes, caíam no texto padrão do
PrimeVue) — melhoria puramente visual. Fotos/Adicionais ganharam o
padrão `.estado-vazio-card` (ícone + título + descrição curta) no lugar
do antigo `<p class="hint">Nenhuma foto anexada ainda.</p>`/`Nenhum
adicional identificado nesta OS ainda.`. Testado ao vivo com dados reais:
peças baixadas (2 movimentações, R$110,00), adicionais com itens
decididos/executados (AD-001/AD-002) — tabela de decisão renderiza
corretamente.

**Histórico (nova)**: junta um evento real de auditoria
(`auditoria_eventos`, tabela que já existe — populada por trigger em toda
mudança de `ordens_servico.status`, ver
`supabase/migrations/20260812093500_p1a_auditoria.sql`) com eventos já
reconstituíveis a partir de arrays já carregados (abertura da OS,
início/fim/remoção de apontamento, envio de foto, identificação de
adicional, abertura de garantia, definição de previsão), tudo ordenado por
data. É uma **leitura adicional read-only** (`select` numa tabela
existente, atrás de `podeVerHistorico` que espelha a mesma RLS da tabela
— `perfil !== 'executor'` — pra nunca disparar um select que voltaria
vazio); não é RPC nova nem migration. Testado ao vivo numa OS real com
histórico de verdade (`TST0A02`/QA02): timeline mostrou corretamente "OS
aberta" → "Status alterado: Aberta → Em diagnóstico" (por
TESTE_Encarregado) → "Status alterado: Em diagnóstico → Em execução" →
"Adicional AD-001 identificado" → "Adicional AD-002 identificado", todos
com timestamp certo, ordenados do mais recente pro mais antigo. Testado
também o caso ao vivo (ver seção REGRESSAO): salvar uma nova previsão de
conclusão via diálogo populou corretamente um novo evento "Previsão de
conclusão definida/alterada" na timeline após recarregar — confirma que a
leitura nova reage a escritas reais, não é estática.

## RESPONSIVIDADE

Testado em 375×812 (mobile) numa OS real: `.cabecalho-os` muda para
`flex-direction: column` (confirmado via `getComputedStyle`), sem nenhum
overflow horizontal a nível de página (`document.documentElement.scrollWidth
=== window.innerWidth === 375`, confirmado). A barra de 6 etapas e a lista
de 6 abas — ambas mais largas que a viewport em mobile — rolam
horizontalmente dentro do próprio container (`barraScrollWidth: 684` vs
`barraClientWidth: 220`; mesmo padrão no `TabList` do PrimeVue, nativo do
componente), sem quebrar o layout da página.

## BUILD

`npm run build` (modo produção padrão) — **0 erros**, build limpo em
~12s. Build de teste (`--mode development`, aponta pra DEV/QA) também
limpo, usado para toda a verificação ao vivo abaixo.

## REGRESSAO

Verificação ao vivo via Browser pane, login real
(`teste.admin@qa.local`, credencial do próprio `supabase/seed.sql`),
`vite preview` sobre o build de produção:

- Abrir OS em 8 status reais diferentes (aberta, em_diagnostico,
  em_execucao, aguardando_teste, concluida, liberada, cancelada,
  reaberta_garantia) — cabeçalho, badge, ações e barra de etapas
  corretos em todos.
- Navegar entre as 6 abas — troca de conteúdo confirmada.
- **Ação de escrita real testada ponta a ponta**: abrir o diálogo
  "Definir Prazo" (pelo atalho do cabeçalho), preencher data/hora, salvar
  — `rpc_definir_previsao_conclusao` executou com sucesso, o cabeçalho
  atualizou o valor exibido, e a aba Histórico (recarregada) mostrou o
  novo evento correspondente. Ponta a ponta: clique → RPC → recarga →
  reflexo em duas telas diferentes (cabeçalho e histórico) — tudo
  consistente.
- Checklist técnico, Mão de Obra Prevista, Peças (com movimentações
  reais), Fotos (estado vazio), Adicionais (com itens decididos/
  executados reais) — todos verificados com dados reais, não só
  estruturalmente.
- `read_console_messages` limpo durante toda a sessão (só o aviso
  conhecido e não relacionado do PrimeUI license, já documentado em
  tarefas anteriores).

**Não testado nesta rodada** (fora do escopo do pedido, que era só
reestruturação de UI): upload real de foto via `File`/`DataTransfer`
sintético (o padrão já documentado em sessões anteriores) e uma transição
de status real (`Iniciar Diagnóstico`/`Enviar p/ Teste` etc.) — evitado
de propósito pra não consumir permanentemente o estado de fixtures de
teste reutilizáveis; a wiring desses botões foi conferida estruturalmente
(mesmo array `transicoesDisponiveis`, mesma função `confirmarTransicao`/
`transicionar`, mesmo RPC `rpc_transicionar_os` — nenhuma linha alterada)
e a escrita real testada (previsão de conclusão) já prova que o padrão
clique→RPC→recarga continua funcionando ponta a ponta neste arquivo
reestruturado.
