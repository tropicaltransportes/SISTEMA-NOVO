# Regras de Negócio — ERP Oficina

## Convenções

- **DEFINIDA**: regra já estabelecida no processo.
- **PROVISÓRIA**: regra operacional sugerida para permitir testes; deve ser homologada.
- **PENDENTE**: decisão ainda não definida e não deve ser inventada pelo código.

---

## BR-001 — Tipos de cliente
**Status:** DEFINIDA

O ERP atende clientes internos e externos/terceiros. Cobrança financeira é obrigatória para clientes externos. O tratamento contábil/financeiro de clientes internos pode existir, mas não deve ser assumido como faturamento externo.

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
**Status:** DEFINIDA

A aprovação pode ser registrada por botão/sistema, e-mail ou autorização verbal documentada. O ERP deve registrar responsável, data/hora e meio da aprovação.

## BR-006 — Aprovação parcial
**Status:** DEFINIDA

O cliente pode aprovar apenas parte do orçamento. Somente itens aprovados podem ser executados/faturados sem nova autorização.

## BR-007 — Alteração após aprovação
**Status:** DEFINIDA

Mudanças de valor, quantidade, peça ou serviço em item já aprovado devem gerar nova versão ou nova aprovação. O histórico anterior não pode ser sobrescrito.

## BR-008 — Conversão para OS
**Status:** DEFINIDA

Somente itens aprovados podem entrar na OS. O mesmo orçamento não pode gerar OS duplicada de forma acidental.

## BR-009 — Serviços adicionais
**Status:** DEFINIDA

Serviços/peças identificados após o início da OS devem ser registrados como adicionais e submetidos a aprovação antes da execução, salvo regra excepcional explicitamente autorizada e auditada.

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
**Status:** DEFINIDA

A confirmação financeira do recebimento ocorre pelo financeiro fora do ERP. O ERP pode registrar a confirmação/status, mas não deve presumir pagamento sem informação autorizada.

## BR-014 — Estoque na OS
**Status:** DEFINIDA

A baixa/comprometimento de peças ocorre quando o orçamento aprovado é convertido em OS, ou quando há venda de peça. Toda movimentação deve ser vinculada ao evento que a originou.

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
**Status:** PROVISÓRIA

Uma OS só deve ser concluída quando não houver itens aprovados obrigatórios pendentes de execução e os controles mandatórios estiverem atendidos.

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
**Status:** DEFINIDA

Peças e serviços possuem garantia de 90 dias conforme regra estabelecida para a oficina. Retornos em garantia devem manter vínculo com a OS original.

## BR-025 — Relatório de encerramento
**Status:** DEFINIDA

A OS deve permitir relatório de encerramento com identificação do veículo/cliente, serviços, peças, responsáveis, datas, valores aplicáveis e informações de liberação.

## BR-026 — Exclusão de histórico
**Status:** PROVISÓRIA

Registros transacionais relevantes não devem ser fisicamente apagados após produzirem efeito operacional/financeiro. Prefira inativação, cancelamento ou estorno auditável.

## BR-027 — Auditoria
**Status:** DEFINIDA

Mudanças críticas devem registrar:
- usuário;
- data/hora;
- operação;
- valor anterior;
- valor novo;
- entidade afetada.

## BR-028 — Permissões
**Status:** DEFINIDA

Executores, encarregado e administrativo possuem papéis distintos. Restrições devem existir no backend, não apenas na interface.

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
**Status:** PROVISÓRIA

Operações críticas submetidas duas vezes por repetição de clique/rede não devem duplicar OS, baixa de estoque, pagamento, liberação ou faturamento.

## BR-034 — Concorrência
**Status:** PROVISÓRIA

Operações simultâneas que disputam o mesmo saldo/registro devem preservar consistência transacional.

## BR-035 — Estados
**Status:** PROVISÓRIA

Os estados sugeridos para homologação são:

Orçamento:
`RASCUNHO -> ENVIADO -> AGUARDANDO_APROVACAO -> APROVADO | PARCIALMENTE_APROVADO | REPROVADO -> CONVERTIDO_EM_OS`

OS:
`ABERTA -> EM_EXECUCAO -> AGUARDANDO_PECA | AGUARDANDO_APROVACAO | PAUSADA -> SERVICO_CONCLUIDO -> AGUARDANDO_LIBERACAO -> LIBERADA -> ENCERRADA`

A implementação pode usar nomes diferentes, desde que preserve semântica e transições válidas.

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
**Status:** PROVISÓRIA

Endpoints críticos devem exigir autenticação, autorização, validação de entrada e proteção contra manipulação direta de IDs quando aplicável.
