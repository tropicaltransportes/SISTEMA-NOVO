# Regras de Negócio — ERP Oficina

## Convenções

- **DEFINIDA**: regra já estabelecida no processo.
- **PROVISÓRIA**: regra operacional sugerida para permitir testes; deve ser homologada.
- **PENDENTE**: decisão ainda não definida e não deve ser inventada pelo código.

---

## BR-001 — Tipos de cliente
**Status:** DEFINIDA (CAD-004, unicidade de documento, implementada na ETAPA 4/P1-A)

O ERP atende clientes internos e externos/terceiros. Cobrança financeira é obrigatória para clientes externos. O tratamento contábil/financeiro de clientes internos pode existir, mas não deve ser assumido como faturamento externo.

**Implementação (ETAPA 4, item B, CAD-004):** dois clientes **ativos**
(`deleted_at is null`) não podem ter o mesmo documento depois de
normalizado (`normalizar_documento()` remove tudo que não é dígito — cobre
CPF/CNPJ com máscara diferente representando o mesmo número). Documento
`NULL` é permitido e pode repetir livremente (cliente interno sem
documento). Cliente inativado (soft delete) não bloqueia reaproveitamento
do documento por um cadastro novo. Índice único parcial
`uq_clientes_documento_normalizado_ativo`. Ver
`supabase/migrations/20260812091000_p1a_cad004_documento_unico.sql`.

## BR-002 — Cadastro de veículo
**Status:** DEFINIDA

Cada atendimento, orçamento e OS deve estar vinculado a um veículo identificável. O histórico do veículo deve permanecer consultável mesmo que o cliente seja inativado.

## BR-003 — Orçamento
**Status:** DEFINIDA

O orçamento pode conter peças, serviços, quantidades, preços, descontos e condições comerciais. Não pode persistir quantidade, preço, desconto ou total inválido.

## BR-004 — Emissão de orçamento
**Status:** DEFINIDA

O orçamento pode ser enviado em PDF ou impresso. O documento emitido deve representar a versão vigente naquele momento.

## BR-005 — Aprovação de orçamento
**Status:** DEFINIDA (registro estruturado do meio implementado na ETAPA 5/P1-B — APR-004/005/006)

A aprovação pode ser registrada por botão/sistema, e-mail ou autorização verbal documentada. O ERP deve registrar responsável, data/hora e meio da aprovação.

**Implementação (ETAPA 5, item 3, APR-004/005/006):** cada item de
orçamento (`orcamento_itens`) e cada item de adicional
(`os_adicional_itens`) ganhou os campos `status_aprovacao`,
`meio_aprovacao` (`sistema`/`email`/`verbal_documentado`),
`autorizado_por_nome` (cliente/responsável — nunca confundido com quem
registrou), `autorizado_em`, `registrado_por` (usuário interno,
`auth.uid()`), `comprovante_path` e `observacao`. O meio nunca é inferido
(nome de arquivo, texto livre) — é sempre um valor estruturado explícito,
validado em `rpc_decidir_item_orcamento`/`rpc_decidir_item_os_adicional`:
`email` exige `comprovante_path` validado contra o Storage real
(`storage_objeto_existe`, reuso de DOC-005/P1-A); `verbal_documentado`
exige `observacao` com no mínimo 10 caracteres, além do nome de quem
autorizou (sempre obrigatório, qualquer meio). Ver
`supabase/migrations/20260813100100_p1b_apr002_aprovacao_item.sql` e
`20260813100200_p1b_adc_tabelas.sql`.

## BR-006 — Aprovação parcial
**Status:** DEFINIDA (implementada na ETAPA 5/P1-B — APR-002/OS-002)

O cliente pode aprovar apenas parte do orçamento. Somente itens aprovados podem ser executados/faturados sem nova autorização.

**Implementação (ETAPA 5, item 1/2, APR-002):** aprovação por item inteiro
(não fração de quantidade dentro do mesmo item — nenhuma outra regra desta
matriz determina o contrário, então mantida a leitura literal da
instrução). Cada `orcamento_itens`/`os_adicional_itens` tem
`status_aprovacao in ('pendente', 'aprovado', 'rejeitado')`. Item rejeitado
nunca é apagado (BR-026) — permanece no histórico, consultável, com sua
decisão preservada.

**Máquina de estados do orçamento** (`status_orcamento`, valor novo
`parcialmente_aprovado` — BR-035 estendida):

```
rascunho -> enviado -> { decisão item a item }
  todos os itens decididos e 100% aprovados      -> aprovado
  todos os itens decididos e 100% rejeitados      -> rejeitado
  todos os itens decididos, mistura aprovado+rejeitado -> parcialmente_aprovado
  algum item ainda sem decisão                    -> continua 'enviado'
     (aprovação NÃO é considerada concluída)
```

Recalculada de forma determinística por `recalcular_status_orcamento()`
toda vez que um item é decidido (`rpc_decidir_item_orcamento`). A mesma
máquina de estados se aplica a `os_adicionais.status`
(`aguardando_aprovacao` no lugar de `enviado`/pendente inicial —
`recalcular_status_os_adicional()`), com os mesmos 4 resultados possíveis.
`rpc_aprovar_orcamento`/`rpc_rejeitar_orcamento` (RPCs antigas, Fase 2)
viraram wrappers de conveniência que decidem TODOS os itens pendentes de
uma vez (meio `sistema`) — preservam a assinatura antiga (nenhum chamador
existente quebra), mas agora escrevem no nível do item, não mais só no
orçamento.

**Alteração após decisão (item 11/APR-008/009/ADC-005):** item já decidido
é imutável — não existe RPC de UPDATE de item decidido, e a RLS não
concede UPDATE direto a `orcamento_itens`/`os_adicional_itens` fora da
janela de rascunho (orçamento) ou nunca (adicional, só INSERT via RPC).
Tentativa de alteração direta é bloqueada (RLS filtra 0 linhas ou 403,
conforme o caso — confirmado por execução real). Alterar valor/quantidade
depois de decidido exige: para orçamento, `rpc_criar_versao_orcamento`
(nova versão, V2+, já existia desde a Fase 2); para adicional, um adicional
NOVO (`rpc_criar_os_adicional`) — a inclusão de item
(`rpc_incluir_item_os_adicional`) só é aceita enquanto NENHUM item do
adicional atual já foi decidido, forçando um novo ciclo de aprovação em vez
de reescrever histórico.

Ver `supabase/migrations/20260813100000_p1b_status_orcamento_enum.sql`,
`20260813100100_p1b_apr002_aprovacao_item.sql`,
`20260813100200_p1b_adc_tabelas.sql`,
`20260813100500_p1b_fix_idempotencia_decisao_item.sql` e
`docs/testing/TEST_REPORT_P1B.md`.

## BR-007 — Alteração após aprovação
**Status:** DEFINIDA (implementada na ETAPA 5/P1-B — ver BR-006, APR-008/009/ADC-005)

Mudanças de valor, quantidade, peça ou serviço em item já aprovado devem gerar nova versão ou nova aprovação. O histórico anterior não pode ser sobrescrito.

## BR-008 — Conversão para OS
**Status:** DEFINIDA (regra de reconversão pós-cancelamento formalizada na ETAPA 4/P1-A; conversão parcial na ETAPA 5/P1-B — OS-002)

Somente itens aprovados podem entrar na OS. O mesmo orçamento não pode gerar OS duplicada de forma acidental.

**Implementação (ETAPA 5, item 4, OS-002):** `rpc_criar_os` passou a
aceitar orçamento `aprovado` OU `parcialmente_aprovado` (antes só
`aprovado`), exigindo ao menos 1 item com `status_aprovacao = 'aprovado'`.
A OS mantém vínculo com o orçamento INTEIRO (`orcamento_id`, sem duplicar
conceito) — a elegibilidade real para execução/baixa/conclusão/cobrança é
sempre resolvida item a item nas RPCs downstream (`rpc_baixar_peca_os`,
`rpc_marcar_item_orcamento_execucao`, `rpc_concluir_os`,
`rpc_criar_cobranca`), nunca no momento da conversão. Item rejeitado
permanece no orçamento (histórico), nunca é copiado/movido para a OS, nunca
é executável nem cobrável.

**Regra de reconversão pós-cancelamento (ETAPA 4, decisão de negócio #1,
resolve o PENDENTE_DECISÃO registrado em
`docs/testing/TEST_REPORT_EXECUTION_03.md`, seção 5):**

- Nunca pode existir mais de **uma OS NÃO CANCELADA** originada pelo mesmo
  orçamento, ao mesmo tempo — independente do tipo (interna ou externa).
- Se todas as OS anteriormente originadas por um orçamento estiverem
  **canceladas**, esse orçamento pode gerar uma **nova** OS normalmente.
- Todas as OS já originadas pelo orçamento — canceladas ou não — permanecem
  no histórico, sempre consultáveis (`ordens_servico.orcamento_id`). Nenhuma
  é apagada/ocultada por essa regra.
- Implementação: `rpc_criar_os` bloqueia com "Este orçamento já foi
  convertido em uma OS ativa" quando `exists (select 1 from ordens_servico
  where orcamento_id = ... and status <> 'cancelada')`. Essa checagem existia
  desde a ETAPA 3 (P0-03) mas só rodava para `tipo = 'externa'` — a ETAPA 4
  corrigiu um achado novo (execução real mostrou uma 2ª OS **interna**
  vinculada ao mesmo orçamento sendo criada sem bloqueio) e passou a aplicar
  a checagem sempre que `p_orcamento_id` não é nulo, independente do tipo.
  Ver `supabase/migrations/20260812099000_p1a_dec1_os004_bloqueio_universal.sql`
  e `docs/testing/TEST_REPORT_P1A.md`.

## BR-009 — Serviços adicionais
**Status:** DEFINIDA (implementada na ETAPA 5/P1-B — ADC-001..008)

Serviços/peças identificados após o início da OS devem ser registrados como adicionais e submetidos a aprovação antes da execução, salvo regra excepcional explicitamente autorizada e auditada.

**Implementação (ETAPA 5, item 5/6):** entidade nova, separada do
orçamento original — nunca altera o orçamento já aprovado (não é o mesmo
conceito, não reaproveita `orcamento_itens`). `os_adicionais` (cabeçalho:
`os_id`, `numero` sequencial por OS formatado `AD-00N`, `motivo`, `status`)
+ `os_adicional_itens` (peça opcional, descrição, quantidade, valor
unitário, valor total gerado, justificativa, mesmos campos de decisão
estruturada de BR-005/BR-006, `execucao_status`).

Fluxo: OS em execução → necessidade identificada
(`rpc_criar_os_adicional`, motivo apenas) → item(ns) incluído(s) com preço
(`rpc_incluir_item_os_adicional`) → decisão por item
(`rpc_decidir_item_os_adicional`, mesma máquina de estados de BR-006) →
item aprovado fica executável/cobrável; item rejeitado/pendente nunca.
`rpc_cancelar_os_adicional` encerra formalmente um adicional ainda
`aguardando_aprovacao` (ex.: identificado por engano) — rejeita os itens
ainda pendentes com motivo obrigatório, auditado (nunca apaga).

**Split de responsabilidade (item 13 — RBAC):** identificar necessidade
(executor/encarregado/administrador_tecnico) ≠ precificar/incluir item
(encarregado/administrador_tecnico, mesma autoridade de preço de BR-010) ≠
decidir item (encarregado/suporte_administrativo/administrador_tecnico,
nunca executor). Backend é a autoridade final em todos os três — RLS
revoga INSERT/UPDATE/DELETE direto de `authenticated` nas duas tabelas
(escrita só via as RPCs acima).

Ver `supabase/migrations/20260813100200_p1b_adc_tabelas.sql`,
`20260813100300_p1b_estoque_execucao_adicional.sql`,
`20260813100600_p1b_cancelar_adicional.sql`.

## BR-010 — Preço
**Status:** DEFINIDA

O preço de peças e serviços é definido/autorizado pelo encarregado. Alterações de preço devem ser auditáveis.

## BR-011 — Desconto
**Status:** DEFINIDA

Descontos podem existir. Devem possuir valor válido, usuário responsável e rastreabilidade.

## BR-012 — Parcelamento
**Status:** DEFINIDA

Cliente externo pode ter parcelamento. O total das parcelas deve reconciliar com o valor negociado.

## BR-013 — Recebimento financeiro
**Status:** DEFINIDA (fórmula de cobrança estendida na ETAPA 5/P1-B — item 10)

A confirmação financeira do recebimento ocorre pelo financeiro fora do ERP. O ERP pode registrar a confirmação/status, mas não deve presumir pagamento sem informação autorizada.

**Implementação (ETAPA 5, item 10):** `rpc_criar_cobranca` deixou de somar
`orcamentos.valor_total` (todos os itens, aprovados ou não) e passou a
somar: itens do orçamento original com `status_aprovacao = 'aprovado'` +
itens de adicionais (de qualquer `os_adicionais` da mesma OS) com
`status_aprovacao = 'aprovado'` + acréscimos pós-aprovação já existentes
(`orcamento_acrescimos`, mecanismo independente, fora do escopo desta
etapa). Item rejeitado, pendente, ou de adicional não aprovado nunca entra
na cobrança — confirmado por execução real (E2E principal: orçamento
R$1.000, aprovado R$700, adicional R$400, aprovado do adicional R$250 →
cobrança final R$950.00 exatos). Ver
`supabase/migrations/20260813100400_p1b_con002_e_financeiro.sql`.

## BR-014 — Estoque na OS
**Status:** DEFINIDA (ATUALIZADA na ETAPA 4/P1-A — ver decisão técnica abaixo)

A baixa/comprometimento de peças ocorre quando o orçamento aprovado é convertido em OS, ou quando há venda de peça. Toda movimentação deve ser vinculada ao evento que a originou.

**Decisão técnica (ETAPA 4, item D, EST-004/E2E-003):** a baixa de peça em
OS originada de orçamento ocorre na **execução** (RPC `rpc_baixar_peca_os`),
**não** no momento da conversão em OS — a conversão (`rpc_criar_os`) nunca
baixou estoque, em nenhuma versão do sistema; o texto original desta regra
("quando o orçamento aprovado é convertido em OS") descrevia uma intenção
que o código nunca implementou dessa forma, e a ETAPA 4 formaliza o
comportamento correto em vez de forçar a baixa a acontecer na conversão.

Motivo para manter a baixa na execução (alternativa B, preferida
explicitamente pelo dono do projeto salvo motivo técnico forte em
contrário — não foi encontrado motivo para preferir a alternativa A):
baixar na conversão comprometeria fisicamente o estoque antes do serviço
realmente começar (ex.: orçamento aprovado de manhã, carro só entra para
execução dias depois — o estoque ficaria reservado/indisponível para outro
atendimento urgente sem necessidade real), e divergiria do saldo físico de
prateleira, que só deve mudar quando a peça de fato sai para ser usada.

O que mudou de fato na ETAPA 4 não foi o "quando" (sempre foi execução), e
sim o "como": agora a baixa é **obrigatoriamente vinculada ao item aprovado
do orçamento** (`orcamento_itens`), não mais uma baixa livre de qualquer
peça:

- `rpc_baixar_peca_os` exige `p_orcamento_item_id` quando a OS tem
  `orcamento_id` (ou, no caso de garantia, quando vinculada via
  `os_garantia_itens` — ver BR-024).
- A peça informada precisa bater com a peça do item; item de mão de obra
  (`peca_id is null`) não aceita baixa de peça.
- A quantidade acumulada baixada (por OS + item) nunca pode ultrapassar a
  quantidade aprovada no item — tentar exceder bloqueia com mensagem
  explícita de que é necessário um Adicional (o módulo de Adicionais em si
  continua fora de escopo; só o bloqueio/sinalização está implementado).
- Estoque insuficiente no momento real da baixa gera erro explícito e
  específico (peça, saldo disponível, quantidade solicitada) — nunca falha
  silenciosa, nunca saldo negativo.

Ver `supabase/migrations/20260812093000_p1a_est004_baixa_vinculada_item.sql`
e `docs/testing/TEST_REPORT_P1A.md` para evidência de execução real.

**Extensão a adicionais (ETAPA 5, item 8, P1-B):** `estoque_movimentos`
ganhou a coluna `os_adicional_item_id` (peça original → aponta
`orcamento_item_id`; peça de adicional → aponta `os_adicional_item_id`;
nunca os dois ao mesmo tempo — `check` de integridade dedicado). Mesmo
padrão de vínculo/bloqueio de EST-004 (item aprovado obrigatório, peça tem
que bater, cota própria por item+OS, nunca saldo negativo) aplicado ao
ramo de adicional em `rpc_baixar_peca_os`. Ver
`supabase/migrations/20260813100200_p1b_adc_tabelas.sql` e
`20260813100300_p1b_estoque_execucao_adicional.sql`.

## BR-015 — Estoque insuficiente
**Status:** DEFINIDA

O sistema não pode permitir saldo físico lógico negativo por baixa comum. Tentativas de saída acima do saldo devem ser bloqueadas ou tratadas por fluxo formal de exceção.

## BR-016 — Estorno
**Status:** PROVISÓRIA

Movimentações erradas devem ser estornadas por lançamento compensatório auditável, e não apagadas do histórico.

## BR-017 — Entrada de estoque
**Status:** DEFINIDA

Entrada de estoque ocorre por compra/NF. Deve registrar item, quantidade, custo, fornecedor/documento quando disponível, usuário e data/hora.

## BR-018 — Executores
**Status:** DEFINIDA

Uma OS pode possuir múltiplos executores. O histórico de participação deve permanecer registrado.

## BR-019 — Fotos
**Status:** DEFINIDA

A OS deve permitir fotos antes/depois. A obrigatoriedade por tipo de serviço pode ser configurável.

## BR-020 — Checklist de liberação
**Status:** DEFINIDA

Existe checklist de liberação antes da entrega do veículo. Itens obrigatórios não preenchidos devem impedir a conclusão/liberação quando configurados como mandatórios.

## BR-021 — Conclusão da OS
**Status:** PROVISÓRIA (reforçada com implementação real na ETAPA 4/P1-A)

Uma OS só deve ser concluída quando não houver itens aprovados obrigatórios pendentes de execução e os controles mandatórios estiverem atendidos.

**Implementação (ETAPA 4, item E, CON-002):** além do checklist técnico (já
existia desde a Fase 2), `rpc_concluir_os` agora também bloqueia quando a OS
tem `orcamento_id` e existe algum `orcamento_itens` com
`execucao_status in ('pendente', 'parcial')`. Cada item tem um destes 4
estados: `pendente` (nada feito), `parcial` (baixa parcial de peça),
`executado` (baixa completa, ou marcado manualmente para item de mão de
obra), `cancelado` (dispensado formalmente, com motivo obrigatório —
auditado, ver BR-027). Só `executado`/`cancelado` não bloqueiam a
conclusão. Itens de peça são sincronizados automaticamente pela baixa
(`rpc_baixar_peca_os`); itens de mão de obra (sem peça) exigem marcação
manual via `rpc_marcar_item_orcamento_execucao`. Ver
`supabase/migrations/20260812094000_p1a_con002_itens_executados.sql`.

**Extensão (ETAPA 5, item 9, P1-B):** a checagem de `orcamento_itens`
passou a filtrar por `status_aprovacao = 'aprovado'` (item rejeitado nunca
bloqueia conclusão — antes não filtrava, o que teria sido uma regressão
funcional com a chegada de itens rejeitados no mesmo orçamento). `rpc_concluir_os`
também bloqueia quando: existe item de adicional aprovado com
`execucao_status in ('pendente', 'parcial')`; OU existe `os_adicionais`
ainda `aguardando_aprovacao` (decisão do cliente em aberto — não é
possível concluir a OS "como se estivesse resolvido" com um adicional
formalmente aberto e ativo). Ver
`supabase/migrations/20260813100400_p1b_con002_e_financeiro.sql`.

## BR-022 — Liberação
**Status:** DEFINIDA

A liberação do veículo pode ser feita pelo administrativo ou encarregado.

## BR-023 — Condição financeira para liberação
**Status:** DEFINIDA

Veículo de cliente externo só pode ser liberado após:
- pagamento confirmado; **ou**
- termo de ciência de débito e comprometimento de quitação registrado.

Sem uma dessas condições, a liberação deve ser bloqueada.

## BR-024 — Garantia
**Status:** DEFINIDA (vínculo com item original implementado na ETAPA 4/P1-A)

Peças e serviços possuem garantia de 90 dias conforme regra estabelecida para a oficina. Retornos em garantia devem manter vínculo com a OS original.

**Implementação (ETAPA 4, item G, GAR-005):** o vínculo passou a existir
também no nível de **item**, não só de OS. Tabela nova
`os_garantia_itens(os_garantia_id, orcamento_item_original_id, motivo)`.
`rpc_criar_os_garantia` exige ao menos um item da OS original quando ela tem
orçamento (bloqueia abrir garantia "em branco"); os itens informados
precisam pertencer de fato ao orçamento da OS original. Na execução da OS
de garantia, `rpc_baixar_peca_os` só aceita baixar peça vinculada a um
desses itens (mesma peça do item original), com cota própria por OS de
garantia (não compartilha o que já foi consumido pela OS original). Não
permite lançar serviço/peça "totalmente sem relação com a origem". Relatório
de garantia (PDF) continua fora de escopo (P1-B/P1-C). Ver
`supabase/migrations/20260812096000_p1a_gar005_vinculo_garantia.sql`.

## BR-025 — Relatório de encerramento
**Status:** DEFINIDA

A OS deve permitir relatório de encerramento com identificação do veículo/cliente, serviços, peças, responsáveis, datas, valores aplicáveis e informações de liberação.

## BR-026 — Exclusão de histórico
**Status:** PROVISÓRIA (reforçada na ETAPA 4/P1-A — CON-007)

Registros transacionais relevantes não devem ser fisicamente apagados após produzirem efeito operacional/financeiro. Prefira inativação, cancelamento ou estorno auditável.

**Implementação (ETAPA 4, item F, CON-007):** apontamento de execução
(`os_executores`) deixou de ser editável livremente por UPDATE direto depois
que a OS está `concluida`/`liberada`/`cancelada` (policy
`os_executores_update_proprio` passou a checar perfil + status da OS, além
do dono do registro). Correção posterior, quando necessária, passa por
`rpc_corrigir_apontamento` (só encarregado/administrador_tecnico, motivo
obrigatório, sempre auditada — ver BR-027) — nunca edição silenciosa.

## BR-027 — Auditoria
**Status:** DEFINIDA (implementada na ETAPA 4/P1-A — AUD-001/002/003)

Mudanças críticas devem registrar:
- usuário;
- data/hora;
- operação;
- valor anterior;
- valor novo;
- entidade afetada.

**Implementação (ETAPA 4, item H):** tabela `auditoria_eventos` (append-only
— sem policy de UPDATE/DELETE para nenhum papel; escrita só via função
interna `registrar_auditoria`, nunca por RPC pública de escrita livre).
Cobertura automática por trigger: mudança de status de OS (inclui
conclusão/liberação/cancelamento), alteração de preço de item de orçamento,
alteração administrativa crítica (perfil/ativo de usuário), e estorno de
estoque (espelha o evento do ledger `estoque_movimentos`, que já era
auditável por natureza — BR-016). Cobertura explícita adicional em RPCs:
`rpc_marcar_item_orcamento_execucao` (cancelamento de item, motivo
obrigatório) e `rpc_corrigir_apontamento` (correção pós-encerramento, motivo
obrigatório). Leitura restrita a perfis não-executor (mesmo critério do
módulo financeiro). Ver
`supabase/migrations/20260812093500_p1a_auditoria.sql`.

**Extensão (ETAPA 5, item 12, P1-B):** eventos novos via
`registrar_auditoria()` (mesma tabela `auditoria_eventos`, mesma
imutabilidade — nenhuma policy de escrita nova foi necessária):
`decisao_item_orcamento`/`decisao_item_adicional` (aprovação/rejeição de
item, com `valor_anterior`/`valor_novo` incluindo `status_aprovacao` e
`meio_aprovacao`), `criar_adicional`, `incluir_item_adicional`,
`cancelar_adicional`/`cancelar_item_adicional_por_cancelamento_cabecalho`,
`marcar_execucao_item_adicional`. Confirmado por execução real: trilha
completa do E2E principal consultável (decisão de cada item, criação do
adicional, decisão de cada item do adicional), sempre com usuário
(`auth.uid()`) e data/hora.

## BR-028 — Permissões
**Status:** DEFINIDA (usuário inativo = bloqueio total, formalizado na ETAPA 4/P1-A)

Executores, encarregado e administrativo possuem papéis distintos. Restrições devem existir no backend, não apenas na interface.

**Decisão de negócio #2 (ETAPA 4, estende a correção AUT-004 da ETAPA 3):**
`profiles.ativo = false` é **bloqueio total** do usuário no ERP — não só
execução de RPC de escrita (corrigido na ETAPA 3, `current_perfil()` passou
a retornar NULL para inativo), mas também **leitura**: alterar registros,
inserir registros, consultar clientes, veículos, orçamentos, OS, estoque,
financeiro, documentos protegidos. O login no Supabase Auth pode
tecnicamente gerar uma sessão (GoTrue não sabe nada sobre `profiles.ativo`),
mas nenhuma informação protegida do ERP fica utilizável enquanto
`ativo=false`.

Implementação centralizada: função `current_user_ativo()` (reaproveita
`current_perfil()`, que já é fail-closed desde a ETAPA 3) — todas as
policies de SELECT que antes checavam só `auth.uid() is not null` passaram a
checar `current_user_ativo()`. As tabelas que já checavam
`current_perfil() <> 'executor'` (financeiro, bucket `comprovantes`) já
eram fail-closed automaticamente e não precisaram de nenhuma mudança
(confirmado por teste, não só por leitura de código). Frontend: `auth.js`
força logout imediato se `profiles.ativo=false` for detectado (login ou
sessão já aberta), com mensagem clara — mas o bloqueio real é o backend, que
continua negando mesmo que o frontend fosse contornado. Ver
`supabase/migrations/20260812090000_p1a_aut004_bloqueio_total_inativo.sql`.

**Item A (AUT-009/PER-006):** RBAC de frontend centralizado em
`frontend/src/lib/permissoes.js`, espelhando exatamente os perfis aceitos
por cada RPC/policy do backend. O frontend nunca é a única proteção — é só
reflexo do que o backend já impõe (confirmado por chamadas diretas à API,
não só pelo que a interface permite clicar).

**Extensão (ETAPA 5, item 13, P1-B):** novas constantes em
`permissoes.js` — `PODE_DECIDIR_ITEM_ORCAMENTO`,
`PODE_IDENTIFICAR_ADICIONAL` (inclui executor), `PODE_PRECIFICAR_ADICIONAL`
(nunca executor), `PODE_DECIDIR_ITEM_ADICIONAL` (nunca executor),
`PODE_CANCELAR_ADICIONAL`, `PODE_MARCAR_EXECUCAO_ADICIONAL`. Backend
continua sendo a autoridade final — cada RPC nova (`rpc_decidir_item_orcamento`,
`rpc_criar_os_adicional`, `rpc_incluir_item_os_adicional`,
`rpc_decidir_item_os_adicional`, `rpc_cancelar_os_adicional`,
`rpc_marcar_item_os_adicional_execucao`) valida perfil via `tem_perfil()`
independente do frontend, confirmado testando executor tentando decidir
item (bloqueado, HTTP 400 "Perfil sem permissão") e tentando precificar
adicional (bloqueado, mesma mensagem) diretamente pela API.

## BR-029 — Prazo
**Status:** DEFINIDA

O prazo de entrega é definido com base no valor/escopo do orçamento conforme regra operacional do encarregado. O critério exato de faixas ainda precisa ser parametrizado.

## BR-030 — Autorização do encarregado
**Status:** DEFINIDA

Operações comerciais/operacionais críticas definidas pelo processo dependem de autorização do encarregado.

## BR-031 — Devolução de peças
**Status:** DEFINIDA

O processo atual não contempla devolução de peças como fluxo rotineiro. Não criar automaticamente um módulo de devolução sem nova decisão de negócio.

## BR-032 — Venda avulsa de peça
**Status:** DEFINIDA

Venda de peça pode gerar baixa de estoque sem OS, desde que a movimentação permaneça vinculada à venda e auditável.

## BR-033 — Idempotência
**Status:** PROVISÓRIA (orçamento coberto na ETAPA 4/P1-A — ORC-016)

Operações críticas submetidas duas vezes por repetição de clique/rede não devem duplicar OS, baixa de estoque, pagamento, liberação ou faturamento.

**Implementação (ETAPA 4, item C, ORC-016):** criação de orçamento (V1) é
INSERT direto (não RPC) — proteção de idempotência via coluna
`orcamentos.client_request_id` (UUID gerado uma vez pelo frontend por
abertura do formulário, reenviado em qualquer retry) + índice único parcial
`ux_orcamentos_client_request_id`. Confirmado com duas requisições REAIS em
paralelo (`curl ... & curl ... & wait`): exatamente 1 orçamento criado, a 2ª
chamada recebe 409 e o frontend trata isso buscando o registro já criado em
vez de mostrar erro. Baixa de estoque (EST-009) e demais RPCs críticas já
usavam o mesmo padrão (`idempotency_key`) desde a ETAPA 3.

## BR-034 — Concorrência
**Status:** PROVISÓRIA

Operações simultâneas que disputam o mesmo saldo/registro devem preservar consistência transacional.

## BR-035 — Estados
**Status:** PROVISÓRIA (máquina de estados do orçamento implementada e determinística na ETAPA 5/P1-B — ver BR-006)

Os estados sugeridos para homologação são:

Orçamento:
`RASCUNHO -> ENVIADO -> AGUARDANDO_APROVACAO -> APROVADO | PARCIALMENTE_APROVADO | REPROVADO -> CONVERTIDO_EM_OS`

OS:
`ABERTA -> EM_EXECUCAO -> AGUARDANDO_PECA | AGUARDANDO_APROVACAO | PAUSADA -> SERVICO_CONCLUIDO -> AGUARDANDO_LIBERACAO -> LIBERADA -> ENCERRADA`

A implementação pode usar nomes diferentes, desde que preserve semântica e transições válidas.

**Implementação real do orçamento (ETAPA 5, P1-B):** `status_orcamento`
(`rascunho`, `enviado`, `aprovado`, `parcialmente_aprovado` — valor novo
desta etapa, `rejeitado`, `substituido`). Sem estado
`aguardando_aprovacao` dedicado — `enviado` já cumpre esse papel enquanto
existir item sem decisão; a transição para `aprovado`/`rejeitado`/`parcialmente_aprovado`
só acontece quando TODOS os itens têm uma decisão (ver fórmula completa em
BR-006). Sem estado `convertido_em_os` dedicado — a existência de uma OS
não cancelada vinculada (`ordens_servico.orcamento_id`, ver BR-008) já é o
sinal de conversão; o orçamento continua com seu último status de
aprovação (histórico correto, não sobrescrito).

## BR-036 — Cliente interno
**Status:** PENDENTE

Definir se cliente interno terá cobrança, centro de custo, apenas custo interno, hora interna, ou combinação desses mecanismos.

## BR-037 — Boleto
**Status:** PENDENTE

Boleto é raro no processo. Não assumir obrigatoriedade de integração bancária sem decisão posterior.

## BR-038 — Reserva de peças
**Status:** DEFINIDA

Reserva de peça separada da baixa não é usada atualmente. Não criar dependência de reserva prévia para a OS.

## BR-039 — Nota fiscal de peças
**Status:** PENDENTE

Emissão fiscal de peças/serviços não está no escopo obrigatório atual. Testes fiscais devem permanecer fora da suíte obrigatória até definição.

## BR-040 — Segurança de dados
**Status:** PROVISÓRIA (DOC-005 e AUT-007 tratados na ETAPA 4/P1-A)

Endpoints críticos devem exigir autenticação, autorização, validação de entrada e proteção contra manipulação direta de IDs quando aplicável.

**Implementação (ETAPA 4, item I, DOC-005):** `rpc_registrar_autorizacao_orcamento`
e `rpc_registrar_termo_ciencia` passaram a validar, via
`storage_objeto_existe()`, que o `comprovante_path`/`arquivo_path`
informado corresponde a um objeto real no bucket `comprovantes` antes de
aceitar a referência — path inexistente, de outro bucket, ou nunca enviado
é bloqueado com erro explícito. Mitigação prática, não garantia
transacional absoluta contra remoção concorrente entre o upload e o uso
(Storage não participa da mesma transação Postgres) — mas, neste projeto,
não existe nenhuma policy de DELETE em `storage.objects` para o bucket
`comprovantes` (usuários comuns não conseguem apagar objetos de jeito
nenhum), o que na prática fecha essa janela de race quase por completo.

**Decisão de negócio #3 (AUT-007 — logout, RISCO ACEITO, não corrigido
nesta etapa):** o token de acesso (JWT) emitido pelo Supabase Auth continua
válido e aceito pelo backend até expirar pelo próprio prazo, mesmo depois de
`/auth/v1/logout` — só o refresh token é revogado no logout. Isso é uma
característica arquitetural do modelo JWT stateless do Supabase (o
PostgREST valida só assinatura + expiração, sem consultar uma lista de
revogação a cada chamada), não um bug de implementação deste projeto.
Implementar revogação ativa de access_token exigiria checar uma lista de
tokens revogados em toda chamada (elimina a vantagem de performance do JWT
stateless) — mudança de arquitetura de autenticação, fora do escopo
controlado do P1-A. Mitigação existente/recomendada, sem alterar
arquitetura: manter o TTL do access_token curto (padrão Supabase, ~1h — não
alterado nesta rodada, decisão de configuração de projeto, não de código),
sempre chamar `signOut()` no cliente ao sair (já implementado em
`frontend/src/stores/auth.js`), e tratar "aba esquecida logada"/vazamento de
token como risco operacional conhecido (equivalente ao risco de qualquer
sessão web JWT, comunicado à diretoria). Reavaliar só se o perfil de risco
da oficina mudar (ex.: acesso público/compartilhado a estações de trabalho).
