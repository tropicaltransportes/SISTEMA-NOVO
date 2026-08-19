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
**Status:** DEFINIDA (histórico dedicado implementado na ETAPA 6/P1-C — CAD-012)

Cada atendimento, orçamento e OS deve estar vinculado a um veículo identificável. O histórico do veículo deve permanecer consultável mesmo que o cliente seja inativado.

**Implementação (ETAPA 6, item 7, CAD-012):** `rpc_historico_veiculo(p_veiculo_id)`
consolida (sem duplicar dado — só agrega o que já existe em `ordens_servico`/
`orcamentos`/`cobranca_origens`) todas as OS do veículo em ordem
cronológica, com tipo, status, datas, orçamento vinculado, custo (interna)
ou valor faturado (externa), executores e indicação de quando a OS é
garantia de outra. Quilometragem não é rastreada em nenhuma tabela do
sistema hoje (não existe coluna de odômetro em `veiculos` nem por OS) — o
campo é omitido em vez de inventado; ver `docs/testing/TEST_REPORT_P1C.md`.
Ver `supabase/migrations/20260814111000_p1c_relatorios.sql`.

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
**Status:** DEFINIDA (estruturado e auditável na ETAPA 6/P1-C — Decisão 7, ORC-007/ORC-008/FIN-003/PEN-007)

Descontos podem existir. Devem possuir valor válido, usuário responsável e rastreabilidade.

**Implementação (ETAPA 6, item 9):** `orcamentos` ganha
`valor_bruto`/`desconto_percentual`/`desconto_valor`/`desconto_motivo`/
`desconto_por`/`desconto_em`/`valor_liquido`. `orcamento_itens` ganha
`desconto_rateado` + `valor_liquido` (gerada). `rpc_aplicar_desconto_orcamento`
(encarregado/administrador_tecnico — mesma autoridade de preço, BR-010) só
atua em orçamento `rascunho`, exige motivo, aceita percentual OU valor
(nunca os dois), nunca permite valor final negativo, e é bloqueada acima do
teto configurado em `desconto_config` (Decisão 7, só administrador_tecnico
define o teto). O desconto é **rateado proporcionalmente** a cada item
(instrução explícita: "preferir aplicar aos itens aos quais ele efetivamente
pertence"), com o último item (ordenado por id) absorvendo o resíduo de
arredondamento — `sum(desconto_rateado) = desconto_valor` sempre, sem
centavo divergente entre orçamento → item → cobrança → PDF.
`rpc_criar_cobranca` passa a somar `valor_liquido` dos itens aprovados em
vez de `valor_total`. Se o orçamento já foi aprovado pelo cliente, alterar o
desconto exige nova versão (`rpc_criar_versao_orcamento`, já existente) —
nunca altera silenciosamente um valor comercial já apresentado/aprovado. Ver
`supabase/migrations/20260814110200_p1c_desconto_orcamento.sql`.

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
**Status:** DEFINIDA (remoção formal implementada na ETAPA 6/P1-C — EXE-003)

Uma OS pode possuir múltiplos executores. O histórico de participação deve permanecer registrado.

**Implementação (ETAPA 6, item 8, EXE-003):** distingue encerrar
participação futura de apagar histórico. `os_executores` ganha
`ativo`/`removido_por`/`removido_em`/`motivo_remocao`. `rpc_remover_executor_os`
(encarregado/administrador_tecnico, motivo obrigatório, auditado) só marca
`ativo=false` — nunca apaga/edita `inicio`/`fim`/`observacao` já registrados,
nunca permite remoção após a OS encerrada (a participação já acabou por
si só nesse ponto). Ver `supabase/migrations/20260814110700_p1c_executor_remocao.sql`.

## BR-019 — Fotos
**Status:** DEFINIDA (implementada na ETAPA 6/P1-C — Decisão 6, PEN-006, EXE-005/006/007)

A OS deve permitir fotos antes/depois. A obrigatoriedade por tipo de serviço pode ser configurável.

**Implementação (ETAPA 6, itens 2/3):** bucket próprio `os-fotos` (Storage),
tabela `os_fotos` (os_id, tipo antes/depois/outro, arquivo_path, enviado_por,
enviado_em, observacao, mime_type, tamanho_bytes). `rpc_registrar_foto_os`
valida: objeto existe de fato no Storage (DOC-005), MIME/tamanho a partir
dos METADADOS REAIS gravados pelo Storage no upload (não confia no que o
cliente alega), path pertence à OS informada (bloqueia vincular foto de
outra OS), e RBAC (executor só na OS em que está atuando — `os_executores`).
Limites configuráveis em `anexos_config` (histórico, só administrador_tecnico
altera). Obrigatoriedade é por `checklist_templates.foto_antes_obrigatoria`/
`foto_depois_obrigatoria` — **nunca global** — e bloqueia `rpc_concluir_os`
quando exigida e ausente. Ver
`supabase/migrations/20260814110300_p1c_fotos_os.sql` e
`20260814110400_p1c_concluir_os_fotos.sql`.

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
**Status:** DEFINIDA (Termo de Ciência de Débito estruturado na ETAPA 6/P1-C — Decisão 8, PEN-008)

Veículo de cliente externo só pode ser liberado após:
- pagamento confirmado; **ou**
- termo de ciência de débito e comprometimento de quitação registrado.

Sem uma dessas condições, a liberação deve ser bloqueada.

**Implementação (ETAPA 6, Decisão 8):** `termos_ciencia_debito` ganha
`cliente_id`, `valor_reconhecido`, `responsavel_nome`,
`responsavel_documento`, `registrado_por`, `observacao`, `criado_em` (as OS
relacionadas continuam derivadas de `cobranca_origens`, N:N já existente —
sem duplicar o vínculo). `rpc_registrar_termo_ciencia` continua reusando
`storage_objeto_existe` (DOC-005) e agora exige nome do responsável. O termo
continua sendo alternativa válida para liberação (`rpc_liberar_os`, regra
inalterada). Ver `supabase/migrations/20260814110900_p1c_termo_ciencia_extensao.sql`.

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
permite lançar serviço/peça "totalmente sem relação com a origem". Ver
`supabase/migrations/20260812096000_p1a_gar005_vinculo_garantia.sql`.

**Extensão a itens de adicional + relatório de garantia (ETAPA 6, item
5/6, GAR-007):** `os_garantia_itens` passa a aceitar item do orçamento
ORIGINAL **ou** item de ADICIONAL aprovado da OS original — nunca os dois
juntos no mesmo registro (`orcamento_item_original_id`/
`os_adicional_item_original_id`, CHECK `num_nonnulls(...) = 1`).
`rpc_criar_os_garantia` ganha `p_itens_adicionais_originais`, validando que
o item pertence à OS de origem e está `aprovado` (item rejeitado nunca gera
garantia, para qualquer uma das duas origens). `rpc_relatorio_garantia_os`
consolida OS de garantia, OS original, prazo, itens originais e de
adicional objeto da garantia, execução realizada, responsáveis e conclusão.

**Regressão real encontrada e corrigida nesta rodada:** a reescrita de
`rpc_baixar_peca_os` feita no P1-B
(`20260813100300_p1b_estoque_execucao_adicional.sql`, para acrescentar o
ramo de item de adicional) não considerou o ramo de GARANTIA introduzido no
P1-A (baseado em `os_origem_id`) — a função nova nem sequer selecionava mais
essa coluna. Resultado: desde o P1-B, **baixar peça em uma OS de garantia
falhava silenciosamente com "baixa avulsa sem vínculo não é permitida"**
(caía no ramo de orçamento por engano, sem checar `os_origem_id`). Corrigido
em `supabase/migrations/20260814110600_p1c_garantia_adicional_fix.sql`, que
reintroduz o ramo de garantia (agora cobrindo item original e item de
adicional) ao lado dos dois ramos do P1-B — confirmado por execução real
(ver `docs/testing/TEST_REPORT_P1C.md`).

## BR-025 — Relatório de encerramento
**Status:** DEFINIDA (implementada na ETAPA 6/P1-C — CON-005/CON-006/DOC-003)

A OS deve permitir relatório de encerramento com identificação do veículo/cliente, serviços, peças, responsáveis, datas, valores aplicáveis e informações de liberação.

**Implementação (ETAPA 6, item 4):** `rpc_relatorio_encerramento_os`
(security invoker — respeita a RLS de cada tabela para quem chama, não é um
jeito novo de contornar permissão) consolida OS, cliente, veículo, datas,
previsão, executores (com horas apontadas), orçamento original com decisão
por item, adicionais com seus itens, checklist, fotos, peças
utilizadas/custo unitário no momento da baixa, custo interno OU cobrança
vinculada (conforme tipo), e garantia aberta a partir desta OS quando
houver. Não modifica a OS — é só leitura/consolidação; a geração do
documento/PDF fica a cargo do frontend a partir destes dados. Ver
`supabase/migrations/20260814111000_p1c_relatorios.sql`.

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
**Status:** DEFINIDA (ETAPA 6/P1-C, Decisão 3 — resolve PEN-003)

O prazo de entrega é definido MANUALMENTE pelo encarregado nesta etapa —
**sem** faixas automáticas por valor (decisão explícita: não implementar
essa automação agora). `ordens_servico.previsao_conclusao` +
`previsao_definida_por`/`previsao_definida_em`, com histórico completo em
`os_prazo_historico`. `rpc_definir_previsao_conclusao`
(encarregado/administrador_tecnico) exige motivo quando é uma ALTERAÇÃO de
prazo já definido (não na 1ª definição), permitida enquanto a OS estiver em
andamento (bloqueada após concluída/liberada/cancelada). Ver
`supabase/migrations/20260814110100_p1c_prazo_os.sql`.

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
**Status:** DEFINIDA (ETAPA 6/P1-C, Decisão 1 — resolve FIN-010/PEN-001/PEN-002)

OS de cliente interno NUNCA gera cobrança financeira (nenhuma cobrança,
parcela ou recebimento fictício). Apura CUSTO TOTAL = custo real das peças
efetivamente consumidas + custo de mão de obra (horas apontadas × custo/hora
vigente, Decisão 2) + centro de custo quando informado (cadastro simples,
não hardcoded — tabela `centro_custo`). Ver seção "Decisões ETAPA 6 (P1-C)"
abaixo e `supabase/migrations/20260814110500_p1c_cliente_interno_custo.sql`.

## BR-037 — Boleto
**Status:** DECIDIDO — FORA_DO_ESCOPO_ATUAL (ETAPA 6/P1-C, Decisão 4 — resolve PEN-004)

Integração bancária real (emissão/registro de boleto) permanece fora do
escopo controlado. Nenhum mock, tabela fictícia ou código incompleto foi
criado para este item.

## BR-038 — Reserva de peças
**Status:** DEFINIDA

Reserva de peça separada da baixa não é usada atualmente. Não criar dependência de reserva prévia para a OS.

## BR-039 — Nota fiscal de peças
**Status:** DECIDIDO — FORA_DO_ESCOPO_ATUAL (ETAPA 6/P1-C, Decisão 5 — resolve PEN-005)

Emissão fiscal de venda/serviço (NF-e/NFS-e real) permanece fora do escopo
controlado — nenhuma integração fiscal fictícia foi criada. A NF de
ENTRADA de peças já existente no módulo de estoque (`notas_fiscais_entrada`
/ `nf_entrada_itens`, recebimento/compra de peça) é um conceito
completamente diferente e continua válida — não deve ser confundida com
emissão fiscal de saída/venda.

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

## BR-041 — PDF de orçamento
**Status:** DEFINIDA (ETAPA 6/P1-C — ORC-013/DOC-001/DOC-002)

O orçamento pode ser emitido em documento (PDF) contendo identificação da
empresa, número/versão legível, cliente, veículo, data, itens (quantidade,
valor unitário, subtotal), desconto quando houver, valor total, observações
e situação. Para orçamento com aprovação parcial, o documento apresenta
claramente item aprovado/rejeitado/pendente, valor original, valor aprovado
e valor rejeitado por item.

**Implementação:** `rpc_dados_pdf_orcamento(p_orcamento_id)` (leitura,
security invoker) devolve todos os dados de UMA versão específica do
orçamento. Versionamento: cada versão é uma linha própria e imutável em
`orcamentos` (já era assim desde a Fase 2 — `rpc_criar_versao_orcamento`
nunca edita a versão anterior, só marca `status='substituido'` e insere uma
linha nova) — chamar a função com o id da versão 1 continua reproduzindo o
documento da versão 1 mesmo depois de existir versão 2+. A renderização em
PDF em si acontece no frontend, a partir destes dados do backend. Ver
`supabase/migrations/20260814111000_p1c_relatorios.sql`.

**Nota de implementação (BUG-PDF-EXPORT-02, 2026-08-18):** o mecanismo de
emissão passou a ser dois caminhos distintos, ambos a partir dos mesmos
dados de `rpc_dados_pdf_orcamento` — nenhum dos dois recalcula nada:
1. **Imprimir** — continua `window.print()` (impressão do navegador).
2. **Baixar PDF** — geração vetorial direta em `frontend/src/lib/pdfOrcamento.js`
   (jsPDF + jspdf-autotable), sem depender do diálogo de impressão do
   navegador — por isso não herda URL, data/hora do navegador, título da
   aba nem numeração de página que o navegador injetaria sozinho nesse
   mecanismo. Não muda o status DEFINIDA desta regra nem o conteúdo exigido
   acima — só documenta o segundo mecanismo de emissão. Ver
   `docs/testing/BUG_PDF_EXPORT_02_REPORT.md`.

## BR-042 — Cancelamento formal de item aprovado (orçamento e adicional)
**Status:** DEFINIDA (ETAPA 6/P1-C, item 11 — estende BR-009/BR-026)

Item já EXECUTADO (total ou parcialmente) nunca pode ser apagado ou
transformado em cancelado/rejeitado — exigiria um procedimento formal de
estorno de estoque, fora desta correção pontual. Item APROVADO mas ainda
NÃO executado pode ser cancelado formalmente, com motivo obrigatório e
auditoria. Item ainda PENDENTE de decisão pode ser rejeitado/cancelado pelo
fluxo de decisão já existente (`rpc_decidir_item_orcamento`/
`rpc_decidir_item_os_adicional`, ou `rpc_cancelar_os_adicional` para encerrar
um adicional inteiro ainda aguardando aprovação). O valor da cobrança
reflete só o que permanece aprovado e não cancelado
(`execucao_status <> 'cancelado'`, filtrado tanto para item de orçamento
quanto de adicional).

**Implementação:** `rpc_marcar_item_orcamento_execucao` e
`rpc_marcar_item_os_adicional_execucao` passam a bloquear a transição para
`cancelado` quando `execucao_status` já é `executado` ou `parcial`.
`rpc_criar_cobranca` exclui item com `execucao_status = 'cancelado'` da
soma, para as duas origens. Ver
`supabase/migrations/20260814110800_p1c_cancelamento_item_aprovado.sql`
(e o lado do adicional, introduzido junto com o rateio de desconto, em
`20260814110200_p1c_desconto_orcamento.sql`).

---

## Decisões formalizadas — ETAPA 6 (P1-C)

Texto das 8 decisões de negócio do dono do projeto para esta etapa,
preservado na íntegra (cada uma referenciada pela(s) BR(s) que resolve
acima — esta seção é a fonte única para os 9 PENDENTE_DECISÃO fechados
nesta rodada: **FIN-010, PEN-001, PEN-002, PEN-003, PEN-004, PEN-005,
PEN-006, PEN-007, PEN-008**).

**Decisão 1 — Cliente interno / OS interna** (resolve FIN-010, PEN-001, PEN-002; ver BR-036).
OS de cliente interno NÃO gera cobrança financeira contra a própria
empresa. Fluxo: OS INTERNA → execução → peças utilizadas → mão de obra →
custo interno → centro de custo/apropriação gerencial. Não criar
cobrança/parcela/recebimento fictício. A OS interna deve permitir apurar
seu CUSTO TOTAL (custo das peças efetivamente utilizadas + mão de obra
interna + outros custos internos estruturados no futuro se existirem). Não
misturar custo interno com faturamento externo.

**Decisão 2 — Custo da hora interna** (suporta BR-036/Decisão 1).
Configuração administrativa para custo/hora interno da oficina (não
hardcode). Configurável por administrador técnico conforme RBAC. Registra
valor hora, vigência, alterado por, data/hora, histórico (nunca apaga
valores históricos). O cálculo considera os apontamentos reais dos
executores. Exemplo de referência: 2h30 × R$40,00/hora = R$100,00 de custo
de mão de obra. Mudança futura no custo/hora não recalcula retroativamente
uma OS já encerrada (snapshot do valor usado na hora).

**Decisão 3 — Prazo da OS** (resolve PEN-003; ver BR-029).
Sem faixas automáticas por valor nesta etapa. Prazo definido MANUALMENTE
pelo encarregado. Campo estruturado (`previsao_conclusao`) registrando
prazo/data prevista, definido_por, definido_em, alteração e motivo da
alteração quando houver. Atualização auditada permitida enquanto a OS
estiver em andamento.

**Decisão 4 — Boleto** (resolve PEN-004; ver BR-037).
Fora do escopo atual. PEN-004 registrado como `DECIDIDO —
FORA_DO_ESCOPO_ATUAL`. Nenhum mock, tabela fictícia ou código incompleto
criado.

**Decisão 5 — Emissão fiscal/NF** (resolve PEN-005; ver BR-039).
Fora do escopo atual. PEN-005 registrado como `DECIDIDO —
FORA_DO_ESCOPO_ATUAL`. Nenhuma integração fiscal fictícia criada. A NF de
ENTRADA de peças já existente permanece válida e não deve ser confundida
com emissão fiscal de venda/serviço.

**Decisão 6 — Fotos** (resolve PEN-006; ver BR-019).
Fotos antes/depois da execução, permitidas para todas as OS;
configuravelmente obrigatórias por tipo de serviço (nunca obrigatoriedade
global). Configuração de tipo de serviço/checklist determina foto-antes-
obrigatória (sim/não) e foto-depois-obrigatória (sim/não). Se obrigatória,
conclusão bloqueia enquanto ausente; se não, conclui sem foto.

**Decisão 7 — Descontos** (resolve PEN-007; ver BR-011).
Desconto estruturado e auditável, sem hardcode de percentual máximo.
Configuração: desconto habilitado, percentual máximo permitido, alterado
por, vigência. Perfis autorizados a conceder desconto: encarregado,
administrador_tecnico. Desconto exige percentual ou valor, motivo
obrigatório, usuário, data/hora. Nunca valor final negativo. Dentro do teto
→ permitido; acima do teto → bloqueado. Sem aprovação hierárquica adicional
nesta etapa. Se o orçamento já foi aprovado pelo cliente e uma alteração de
desconto modifica o valor comercial aprovado, exige nova versão/reaprovação
— nunca altera silenciosamente valor previamente aprovado.

**Decisão 8 — Termo de Ciência de Débito** (resolve PEN-008; ver BR-023).
Estruturado formalmente: cliente_id, cobranca_id, OS relacionada(s), valor
total reconhecido, responsável do cliente, documento/identificação do
responsável quando informado, data de assinatura, registrado_por,
arquivo_path, observação, criado_em. O arquivo deve existir no Storage
antes do registro (DOC-005, reusado). O termo continua sendo alternativa
válida para liberação quando pagamento não confirmado + termo válido
registrado.

## BR-043 — Política de exclusão de arquivos (Storage)
**Status:** DEFINIDA (ETAPA 8/RC2, seção 4 — formalização de comportamento
já existente desde BR-040/DOC-005/DOC-006, não é funcionalidade nova)

**Regra:** arquivos operacionais (comprovantes no bucket `comprovantes`,
fotos de OS no bucket `os-fotos`) **não devem ser apagados fisicamente pelo
usuário — nenhum perfil, inclusive administrador_tecnico.** A ausência de
exclusão física preserva rastreabilidade/evidência: um comprovante de
autorização de orçamento, um termo de ciência de débito, ou uma foto de
antes/depois de OS são evidência de uma decisão de negócio já tomada
(BR-040), e apagar o objeto quebraria a garantia (mitigada, não absoluta —
ver BR-040) de que todo `comprovante_path`/`arquivo_path` referenciado por
um registro no banco continua correspondendo a um objeto real no Storage.

**Estado atual confirmado nesta rodada (RC2):** nenhuma migration deste
projeto cria policy de `DELETE` em `storage.objects` para os buckets
`comprovantes` ou `os-fotos` — a ausência de policy de DELETE é, por padrão
do Supabase Storage (RLS fail-closed), equivalente a proibir a exclusão
para todos os papéis, incluindo `administrador_tecnico`. Isso já era descrito
en passant em BR-040 (linha "não existe nenhuma policy de DELETE em
`storage.objects` para o bucket `comprovantes`"); esta seção estende
explicitamente a mesma regra para `os-fotos` e a eleva a decisão de negócio
formal, não só efeito colateral de RLS.

**Se uma remoção lógica futura for necessária** (ex.: LGPD, erro de upload
grosseiro, pedido do cliente): não deve ser exclusão física. Precisa de:
motivo obrigatório, usuário responsável, data/hora, registro de auditoria
(`registrar_auditoria`, mesmo padrão de BR-018/BR-042), e o registro
original (linha em `os_fotos`/`comprovante_path` referenciado) preservado —
uma remoção lógica marca o registro como invalidado (ex.: campo
`invalidado_em`/`invalidado_por`/`motivo_invalidacao`), nunca faz
`DELETE`/apaga a linha nem o objeto do Storage. **Isso não foi implementado
nesta rodada** — é proibido implementar funcionalidade de negócio nova na
ETAPA 8/RC2; fica registrado aqui como decisão de arquitetura para uma
rodada futura que precise dela, e como item explícito em
`docs/PRODUCTION_READINESS_CHECKLIST.md`.

---

## BR-044 — Catálogo de Serviços e snapshot imutável no orçamento
**Status:** DEFINIDA (FEATURE-SERVICOS-01, DEV/QA — migrations
`20260817140000_p2_servicos_catalogo.sql` e
`20260817140100_p2_fix_natureza_gerada.sql`, projeto `jzjbiejmcaygwycvqggm`)

**Regra:** existe um catálogo estruturado de serviços/mão de obra
(`servicos`, com `codigo` único, `nome`, `categoria_id` opcional
referenciando `servico_categorias`, `preco_referencia`,
`tempo_estimado_minutos` opcional, `garantia_dias` — default 90,
referência de BR-024, sem alterar o literal fixo de 90 dias já usado em
`rpc_criar_os_garantia` — e `checklist_template_id` opcional reutilizando
`checklist_templates` já existente). `preco_referencia` é **preço
comercial de referência**, distinto e independente de `custo_hora_config`
(custo interno da hora trabalhada, ver BR relacionada à Decisão 2/ETAPA
6/P1-C) — nenhum dos dois cálculos lê o outro.

`orcamento_itens` ganhou `servico_id` (nullable, FK para `servicos`) e três
colunas de snapshot (`codigo_servico_snapshot`,
`tempo_estimado_minutos_snapshot`, `garantia_dias_snapshot`), preenchidas
no momento do lançamento e nunca recalculadas. `descricao`/`valor_unitario`
já eram, por construção, o próprio snapshot (copiados no insert, sem join
vivo) — a extensão só torna explícitos os campos que o catálogo acrescenta.
**Alterar o preço/dados de um serviço no catálogo depois nunca modifica um
item de orçamento já salvo, o PDF já emitido, nem a OS originada dele** —
confirmado por teste (`SERV-ORC-001`) e por leitura de código
(`OrcamentoPdf.vue`/`rpc_dados_pdf_orcamento` só leem colunas de
`orcamento_itens`, nunca fazem join vivo com `servicos`/`pecas`).

`orcamento_itens.natureza` é coluna **gerada** (`generated always as`,
stored), derivada de `peca_id`/`servico_id` — nunca gravável diretamente:
`peca` quando `peca_id` preenchido, `servico_cadastrado` quando
`servico_id` preenchido, `servico_avulso` quando nenhum dos dois (mão de
obra livre, sem vínculo a catálogo — comportamento anterior preservado
integralmente). Um CHECK (`orcamento_itens_peca_ou_servico_nao_ambos`)
impede as duas FKs preenchidas ao mesmo tempo. O preço de referência do
catálogo **não bloqueia** edição do valor lançado no item (encarregado/
suporte_administrativo/administrador_tecnico continuam podendo digitar um
valor diferente, como já era possível para peças/mão de obra avulsa).

Escrita no catálogo (`rpc_criar_servico`/`rpc_atualizar_servico`/
`rpc_ativar_servico`/`rpc_inativar_servico`) é restrita a
`suporte_administrativo`/`administrador_tecnico` — espelha a RBAC já
existente de `pecas` (catálogo comercial irmão), não a de
`checklist_templates`. Inativação é sempre soft-disable
(`ativo=false`, nunca `DELETE`); um serviço inativo some da lista de opções
para **novos** lançamentos, mas continua acessível em itens/orçamentos já
existentes via snapshot. Toda mutação do catálogo é auditada via
`registrar_auditoria` (mesmo mecanismo único de auditoria do projeto,
BR-027) — por isso a escrita passa por RPC `SECURITY DEFINER` em vez de
INSERT/UPDATE direto via RLS (diferente do padrão de `orcamento_itens`),
já que `registrar_auditoria` está com `REVOKE EXECUTE FROM anon,
authenticated`.

**Migração de dados históricos:** nenhuma. Itens de mão de obra lançados
antes desta etapa continuam como `servico_avulso` (a mesma coisa que já
eram, agora só com rótulo explícito) — não há tentativa de inferir
correspondência retroativa com o novo catálogo (risco de inferência
incorreta, deliberadamente evitado).

**Corrigido durante a própria rodada:** a primeira versão da migration
definia `natureza` como coluna manual com `default 'peca'` + CHECK de
consistência — isso quebrou fixtures/uso existentes que inserem
`orcamento_itens` sem `peca_id` e sem informar `natureza` (pgTAP
`030_orcamento.sql`/`040_liberacao.sql`, e o próprio frontend, que nunca
enviava essa coluna). Corrigido trocando `natureza` por coluna gerada
(migration de fix same-day), eliminando a classe de bug inteira em vez de
só o caso encontrado — nenhum código cliente precisa (nem pode) enviar
`natureza` manualmente.

**Fora de escopo nesta etapa (registrado como melhoria futura):**
automação `Serviço → Checklist → OS` (hoje só existe o vínculo no
catálogo); extensão do mesmo conceito a Adicionais da OS
(FEATURE-SERVICOS-02); relatórios de serviços mais vendidos, faturamento
por serviço, tempo estimado × real, margem de mão de obra e retornos em
garantia por serviço (o modelo de dados já está apto — `tempo_estimado_minutos`
e os snapshots existem — mas nenhum novo dashboard/indicador foi
implementado).

## BR-045 — Exclusão lógica de orçamento em rascunho
**Status:** DEFINIDA (FEATURE-ORCAMENTO-EXCLUSAO-01, DEV/QA — migration
`20260818150000_p2b_orcamento_exclusao_rascunho.sql`, projeto
`jzjbiejmcaygwycvqggm`)

**Regra:** um orçamento só pode ser excluído logicamente enquanto
`status = 'rascunho'` **e** não existir `ordens_servico` não-cancelada
vinculada a ele (mesmo predicado de bloqueio de BR-008/OS-004, reutilizado
verbatim de `rpc_criar_os` dentro de `rpc_excluir_orcamento_rascunho`).
Nunca há `DELETE` físico: `orcamentos` ganhou `deleted_at`/`deleted_by`/
`deleted_reason` (mesma convenção já usada em `clientes`/`veiculos`/`pecas`).
Motivo obrigatório, mínimo de 5 caracteres, validado no backend (não confia
no frontend) — mesmo padrão de `desconto_motivo` (BR relacionada a
`rpc_aplicar_desconto_orcamento`).

**Itens preservados, sem coluna própria de exclusão:** `orcamento_itens`
**não** ganhou `deleted_at`. Os itens continuam fisicamente presentes no
banco (`ORC-DEL-002`, confirmado por teste) — ficam ocultos apenas
transitivamente, porque a RLS de `orcamento_itens` já depende da RLS do
orçamento pai (BR-026: preservar histórico, nunca apagar).

**RLS, não frontend, é quem esconde o excluído:** `orcamentos_select_autenticado`
passou a exigir `deleted_at is null or tem_perfil('administrador_tecnico')`
— mesmo o encarregado que acabou de excluir o próprio rascunho perde a
visibilidade dele imediatamente (`ORC-DEL-001c`, confirmado por teste); só
`administrador_tecnico` continua vendo, para fins de auditoria/restauração.
Um cliente adulterando a query no navegador nunca traz a linha de volta,
porque o filtro está no banco, não em `.is('deleted_at', null)` do
frontend.

**Interação com versionamento (decisão formalizada, não inventada):**
excluir uma versão V2 recém-criada por `rpc_criar_versao_orcamento` (que já
marcou a V1 original como `'substituido'` no momento em que a V2 nasceu)
**não restaura V1 automaticamente**. Decisão confirmada com o dono do
projeto: reverter o status de uma segunda linha que o usuário não tocou
diretamente seria uma mutação silenciosa adicional — evitada de propósito.
O estado é reversível a qualquer momento: `rpc_restaurar_orcamento_excluido`
traz a V2 de volta, ou uma nova versão pode ser criada a partir da V1
normalmente.

**Restrições de um rascunho excluído:** não pode receber item (RLS),
desconto, nem ser enviado (`rpc_aplicar_desconto_orcamento`/
`rpc_enviar_orcamento` ganharam a guarda `deleted_at is not null`). Como
`status` continua `'rascunho'` mesmo depois de excluído (`deleted_at` é
ortogonal a `status`), toda RPC/policy que antes só checava
`status = 'rascunho'` precisou da guarda extra — as demais RPCs (aprovação,
versionamento, criação de OS, acréscimo) nunca aceitam `'rascunho'`
diretamente, então não precisaram mudar.

**Idempotência e concorrência:** repetir a exclusão do mesmo orçamento é
bloqueado com mensagem específica, sem reprocessar nem duplicar evento de
auditoria (`ORC-DEL-BONUS-01`). `select ... for update` dentro da RPC
serializa qualquer corrida com `rpc_enviar_orcamento` sobre o mesmo
orçamento — o estado final nunca é `status='enviado'` com `deleted_at`
preenchido ao mesmo tempo, testado nas duas ordens possíveis
(`ORC-CONC-001a/b`; concorrência real de duas sessões HTTP simultâneas fica
em `docs/testing/scripts/etapa8_orcexclusao_concorrencia.sh`, mesmo padrão
de `etapa7_concorrencia_*.sh` — pgTAP roda numa única sessão, não modela
contenção real de lock).

## BR-046 — Cancelamento formal de orçamento pós-rascunho
**Status:** DEFINIDA (FEATURE-ORCAMENTO-EXCLUSAO-01, DEV/QA — migrations
`20260818150100_p2b_status_orcamento_cancelado_enum.sql` e
`20260818150200_p2b_orcamento_cancelamento.sql`)

**Regra:** orçamento em `enviado`, `aprovado`, `rejeitado` ou
`parcialmente_aprovado` pode ser cancelado formalmente via
`rpc_cancelar_orcamento`, transição para o novo valor de enum
`status_orcamento = 'cancelado'` — nunca revertida (cancelamento é
definitivo; não existe "reabrir" nesta etapa). Bloqueado se existir
`ordens_servico` não-cancelada vinculada (mesmo predicado de bloqueio de
BR-008/BR-045). Motivo obrigatório, mínimo de 5 caracteres, validado no
backend. Diferente da exclusão de rascunho, o cancelamento grava colunas
próprias em `orcamentos` (`cancelado_em`/`cancelado_por`/
`cancelamento_motivo`), espelhando `desconto_motivo/desconto_por/desconto_em`,
em vez de depender só de `auditoria_eventos` — necessário porque `orcamentos`
é legível por todo perfil ativo (inclusive `executor`), e `auditoria_eventos`
não é (`auditoria_select_gestao` exclui `executor`).

**Nenhuma outra RPC precisou mudar por causa do cancelamento** (confirmado
lendo cada corpo antes de escrever a migration): `rpc_aprovar_orcamento`/
`rpc_rejeitar_orcamento` exigem `status = 'enviado'`;
`rpc_criar_versao_orcamento` exige `status in ('enviado','aprovado','rejeitado')`;
`rpc_criar_os` exige `status in ('aprovado','parcialmente_aprovado')`;
`rpc_registrar_acrescimo` exige `status = 'aprovado'`;
`rpc_decidir_item_orcamento` exige `orc.status = 'enviado'` — `'cancelado'`
nunca aparece em nenhum desses allow-lists, então um orçamento cancelado é
automaticamente recusado em todos esses caminhos sem checagem adicional
(confirmado por teste: `ORC-CAN-002` a `ORC-CAN-005`). PDF/histórico
continuam disponíveis e mostram o status `cancelado` (`ORC-CAN-006`,
BR-026/BR-043: nunca remover acesso ao histórico, só bloquear nova mutação
comercial).

**Idempotência:** cancelar um orçamento já cancelado é bloqueado com
mensagem específica (`ORC-CAN-BONUS-01`).

## BR-047 — Restauração administrativa de orçamento excluído
**Status:** DEFINIDA (FEATURE-ORCAMENTO-EXCLUSAO-01, DEV/QA — migration
`20260818150000_p2b_orcamento_exclusao_rascunho.sql`)

**Regra:** `rpc_restaurar_orcamento_excluido` é restrito a
`administrador_tecnico` — mais restrito que a própria exclusão (permitida
a `encarregado` e `administrador_tecnico`), decisão deliberada: reverter
uma ação destrutiva já auditada exige autoridade máxima, não a mesma
autoridade que a praticou (`ORC-REST-002`, confirmado por teste: o próprio
encarregado que excluiu não consegue restaurar). Restauração limpa
`deleted_at`/`deleted_by`/`deleted_reason`; motivo de restauração é
**opcional** (o histórico completo de quando/por quem/por que foi excluído
já está integralmente em `auditoria_eventos`, evento `ORCAMENTO_EXCLUIDO` —
não duplicado em novas colunas). Restaurar um orçamento que não está
excluído é bloqueado, não silenciosamente ignorado (`ORC-REST-003`).

## BR-048 — Exclusão lógica de OS "virgem"
**Status:** DEFINIDA (FEATURE-OS-CANCELAMENTO-01, DEV/QA — migration
`20260818170000_p2d_os_exclusao_logica.sql`, projeto `jzjbiejmcaygwycvqggm`)

**Regra:** uma OS só pode ser excluída logicamente enquanto
`status = 'aberta'` **e** não existir nenhum rastro operacional: apontamento
(`os_executores` — qualquer linha, já que `inicio` é `NOT NULL` na tabela
real, não existe "atribuído sem iniciar" hoje), movimento de estoque
(`estoque_movimentos.origem_tipo='os'`), foto (`os_fotos`), adicional
(`os_adicionais`, qualquer status), resposta de checklist real
(`os_checklist_respostas` — `checklist_template_id` sozinho na OS não
bloqueia, é só seleção do template) ou cobrança vinculada
(`cobranca_origens`). OS de garantia (`os_origem_id is not null`) nunca é
excluída por este caminho, só cancelada (BR-049 reverte a origem para
`liberada`). Mesma convenção de soft delete de `orcamentos`
(`deleted_at`/`deleted_by`/`deleted_reason`) — `DELETE` físico nunca ocorre.
Motivo obrigatório, mínimo de 5 caracteres, validado no backend
(`rpc_excluir_os_rascunho`), nunca confiando só no frontend.

**RLS, não frontend, é quem esconde a excluída:** `os_select_autenticado`
passa a exigir `deleted_at is null or tem_perfil('administrador_tecnico')`
— mesmo quem excluiu perde a visibilidade imediatamente (`OS-DEL-001b`,
confirmado por teste); só `administrador_tecnico` continua vendo, para a
tela de restauração.

**Guardas adicionais de `deleted_at`** em RPCs/policies que só checavam
`status` (a coluna não existia antes desta migration): inserção de
apontamento (`os_executores_insert_proprio`), resposta de checklist
(`os_checklist_insert_resposta`/`_update_resposta`), `rpc_registrar_foto_os`
e `rpc_criar_os_adicional` — sem isso, uma OS excluída (que continua
`status='aberta'`) ainda aceitaria atividade operacional nova por engano.

Ver `docs/testing/TEST_REPORT_OS_CANCELAMENTO01.md` (`OS-DEL-001..009`).

## BR-049 — Cancelamento formal de OS
**Status:** DEFINIDA (FEATURE-OS-CANCELAMENTO-01, DEV/QA — migration
`20260818170100_p2d_os_cancelamento.sql`)

**Regra:** `rpc_cancelar_os` (RPC dedicada — `rpc_transicionar_os` passa a
**rejeitar** `p_novo_status='cancelada'`, redirecionando para esta) permite
cancelar de `aberta`, `em_diagnostico`, `aguardando_aprovacao`,
`em_execucao`, `aguardando_teste` ou `concluida`. Motivo obrigatório,
mínimo de 5 caracteres. Dentro de uma única transação (uma função PL/pgSQL
— `raise` = rollback automático de tudo, nunca estado parcial):

1. encerra todo apontamento em aberto (`os_executores.fim is null` vira
   `now()`, auditado como `APONTAMENTO_ENCERRADO_POR_CANCELAMENTO`);
2. fecha formalmente todo adicional `aguardando_aprovacao` (reaproveita o
   núcleo de `rpc_cancelar_os_adicional`, extraído para o helper interno
   `cancelar_os_adicional_interno` — mesmo comportamento de sempre, sem
   inventar um terceiro vocabulário de "cancelado" no cabeçalho de
   adicional: o header vira `'rejeitado'`, precedente já existente);
3. estorna toda saída de estoque não estornada da OS (`origem_tipo='os'`) —
   mesmo mecanismo já existente e idempotente por construção
   (`estornar_saida_estoque_interno`, guarda contra estorno duplo via
   `estornado_de`), cobre peça de orçamento **e** de adicional (ambos usam
   `origem_tipo='os', origem_id=os_id`) sem lógica extra; o próprio estorno
   já resincroniza `execucao_status` do item vinculado de volta a
   `'pendente'`;
4. item de **mão de obra** (sem `peca_id`, portanto sem `estoque_movimentos`
   para o estorno resincronizar sozinho) que estava `'parcial'` volta a
   `'pendente'` explicitamente — nunca `'cancelado'`: esse valor é um
   override manual permanente (`sincronizar_execucao_item_orcamento` nunca
   reabre um item `'cancelado'` automaticamente), e marcá-lo assim travaria
   para sempre a execução de uma OS reconvertida do mesmo orçamento (BR-008);
5. se a OS é uma OS de **garantia** (`os_origem_id is not null`), a origem
   volta de `'reaberta_garantia'` para `'liberada'` — sem isso, cancelar uma
   garantia aberta por engano prende a origem permanentemente (nenhum outro
   caminho de volta existe);
6. só então transiciona para `'cancelada'`, grava
   `cancelado_em/cancelado_por/cancelamento_motivo` (colunas separadas de
   `deleted_*`, mesmo racional de BR-046: motivo precisa estar na própria
   linha, legível por todo perfil ativo, não só em `auditoria_eventos` que
   exclui `executor`) e um evento `OS_CANCELADA` explícito com o motivo real
   (o trigger genérico `audit_trg_os_status` já grava `mudanca_status` com
   motivo sempre `null`).

**Idempotência:** cancelar uma OS já cancelada é bloqueado
(`OS-CAN-003`) — o estorno de estoque também é independentemente idempotente
(`estornado_de`), então mesmo um retry hipotético nunca duplica devolução.

**Concorrência:** `for update` no início de `rpc_cancelar_os` serializa
contra outra chamada de cancelamento. `rpc_baixar_peca_os` (única RPC
operacional relevante que ainda lia `status`/`orcamento_id`/`os_origem_id`
sem lock) ganhou `for update` na mesma leitura (migration
`20260818170200_p2d_os_concorrencia_e_correcoes.sql`) — sem isso, uma baixa
concorrente com o cancelamento poderia gravar depois do estorno já ter
rodado, sem ser incluída nele.

Ver `docs/testing/TEST_REPORT_OS_CANCELAMENTO01.md` (`OS-CAN-001..009`,
`OS-CONC-001/002`).

## BR-050 — Bloqueios de cancelamento (financeiro, liberação, garantia)
**Status:** DEFINIDA (FEATURE-OS-CANCELAMENTO-01, DEV/QA — migration
`20260818170100_p2d_os_cancelamento.sql`)

**Regra:** `rpc_cancelar_os` bloqueia incondicionalmente se existir
recebimento confirmado vinculado (via `cobranca_origens → parcelas →
recebimentos`) — nunca desfeito por cancelamento de OS. Bloqueia também se
existir qualquer cobrança vinculada com `status <> 'cancelada'`, **mesmo
sem recebimento** — decisão deliberada de **não** auto-cancelar a cobrança
dentro da transação: `rpc_cancelar_cobranca` é uma RPC pública separada,
auditada, com gate de perfil próprio (`suporte_administrativo`/
`administrador_tecnico` — diferente do gate de `rpc_cancelar_os`,
`encarregado`/`administrador_tecnico`); emprestar essa autoridade financeira
implicitamente concederia a `encarregado` um poder que o sistema financeiro
nunca concede a esse perfil. Fluxo correto: cancelar a cobrança primeiro
(tela existente), só então cancelar a OS (`OS-FIN-CAN-004`, confirmado por
teste).

Bloqueia com mensagem específica se `status in ('liberada',
'reaberta_garantia')` — não existe status "encerrada" literal no enum
`status_os`; estes dois são os estados consolidados equivalentes, histórico
operacional que só um fluxo administrativo futuro (fora do escopo desta
feature) poderia reverter. Se a própria OS já gerou uma garantia
(`exists (... where os_origem_id = p_os_id)`), o cancelamento também é
bloqueado — checagem mantida como defesa em profundidade, embora
estruturalmente já impossível dado o bloqueio de `liberada`/
`reaberta_garantia` acima (só se chega a gerar garantia a partir de
`liberada`).

Ver `docs/testing/TEST_REPORT_OS_CANCELAMENTO01.md` (`OS-FIN-CAN-001..004`,
`OS-CAN-002`).

## BR-051 — Restauração administrativa de OS excluída
**Status:** DEFINIDA (FEATURE-OS-CANCELAMENTO-01, DEV/QA — migrations
`20260818170000_p2d_os_exclusao_logica.sql` e
`20260818170300_p2d_os_reconversao_apos_exclusao.sql`)

**Regra:** `rpc_restaurar_os_excluida` é restrita a `administrador_tecnico`
— mais restrita que a própria exclusão (`encarregado`/`administrador_tecnico`),
mesmo racional de BR-047. Bloqueada se o orçamento da OS já foi convertido
em outra OS ativa nesse meio-tempo (mesmo predicado de BR-008/BR-045:
`status <> 'cancelada' and deleted_at is null`). Nunca restaura OS
`cancelada` — cancelamento é evento histórico, não "lixeira".

**Achado durante a implementação:** exclusão lógica não muda `status` (só
`deleted_at`), então o predicado de bloqueio de reconversão de BR-008
(`rpc_criar_os`) e o predicado espelho desta RPC, que originalmente só
olhavam `status <> 'cancelada'`, não sabiam que `deleted_at` existe —
excluir uma OS "por engano" **não liberava** o orçamento para nova
conversão (a OS excluída, com `status='aberta'` intacto, continuava
contando como "OS ativa" para o bloqueio), contradizendo o propósito da
própria exclusão lógica. Corrigido em
`20260818170300_p2d_os_reconversao_apos_exclusao.sql`: os dois predicados
agora ignoram OS soft-deleted, do mesmo jeito que a RLS de `SELECT` já
ignora (`OS-REST-004a/b`, confirmado por teste).

Ver `docs/testing/TEST_REPORT_OS_CANCELAMENTO01.md` (`OS-REST-001..004`).
