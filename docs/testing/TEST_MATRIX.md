# Matriz Mestra de Testes — ERP Oficina

## Objetivo

Esta matriz é a referência de homologação funcional e técnica do ERP da oficina.

Cada caso deve manter o mesmo ID no relatório e, quando automatizado, preferencialmente no nome do teste.

## Status permitidos

- `PASSOU`
- `FALHOU`
- `BLOQUEADO`
- `NÃO_IMPLEMENTADO`
- `NÃO_AUTOMATIZÁVEL`
- `PENDENTE_DECISÃO`

## Criticidade

- **Crítica**: risco de perda financeira, estoque incorreto, liberação indevida, violação de permissão, corrupção de dados ou quebra grave do processo.
- **Alta**: compromete função essencial ou gera inconsistência operacional relevante.
- **Média**: comportamento incorreto com contorno operacional.
- **Baixa**: apresentação/usabilidade ou escopo não obrigatório.

## Camadas

- `Unit`: função/regra isolada
- `API`: endpoint/serviço/backend
- `Integration`: banco/transação/concorrência
- `E2E`: navegador/fluxo real
- `Manual`: inspeção humana
- `Test Infra`: infraestrutura de testes

---


# Autenticação
## AUT-001 — Login válido
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário ativo existente
- **Ação:** Autenticar com credenciais válidas
- **Resultado esperado:** Sessão/token criado e usuário identificado

## AUT-002 — Senha inválida
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário ativo existente
- **Ação:** Autenticar com senha incorreta
- **Resultado esperado:** Acesso negado sem criação de sessão

## AUT-003 — Usuário inexistente
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Nenhuma
- **Ação:** Autenticar com usuário inexistente
- **Resultado esperado:** Acesso negado sem vazamento de detalhes

## AUT-004 — Usuário inativo
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário inativado
- **Ação:** Tentar autenticar
- **Resultado esperado:** Acesso bloqueado

## AUT-005 — Endpoint protegido sem login
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Nenhuma
- **Ação:** Chamar endpoint protegido sem credencial
- **Resultado esperado:** Resposta 401/403

## AUT-006 — Token/sessão inválida
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Credencial inválida/expirada
- **Ação:** Chamar endpoint protegido
- **Resultado esperado:** Acesso negado

## AUT-007 — Logout
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Usuário autenticado
- **Ação:** Encerrar sessão
- **Resultado esperado:** Sessão deixa de permitir operações protegidas

## AUT-008 — Elevação indevida de perfil
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário executor
- **Ação:** Manipular payload/rota para se tornar encarregado
- **Resultado esperado:** Alteração bloqueada e auditável

## AUT-009 — Acesso direto por URL
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário sem permissão
- **Ação:** Abrir rota administrativa diretamente
- **Resultado esperado:** Tela/API negam acesso

## AUT-010 — Credenciais em resposta/log
- **Criticidade:** Alta
- **Camada sugerida:** Manual/API
- **Automação:** Parcial
- **Regra relacionada:** BR-040
- **Pré-condição:** Login executado
- **Ação:** Inspecionar resposta e logs de teste
- **Resultado esperado:** Senha/segredo não aparece em claro


# Cadastros
## CAD-001 — Cadastrar cliente externo válido
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-001
- **Pré-condição:** Usuário autorizado
- **Ação:** Criar cliente com campos válidos
- **Resultado esperado:** Cliente criado e classificado como externo

## CAD-002 — Cadastrar cliente interno válido
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-001
- **Pré-condição:** Usuário autorizado
- **Ação:** Criar cliente interno
- **Resultado esperado:** Cliente criado sem faturamento externo implícito

## CAD-003 — Campo obrigatório ausente
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-001
- **Pré-condição:** Usuário autorizado
- **Ação:** Salvar cliente sem campo obrigatório
- **Resultado esperado:** Validação bloqueia persistência

## CAD-004 — Duplicidade de documento
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Cliente com mesmo identificador já existente
- **Ação:** Criar novo cliente duplicado
- **Resultado esperado:** Sistema impede ou sinaliza conforme chave de unicidade definida

## CAD-005 — Cadastrar veículo
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Cliente existente
- **Ação:** Criar veículo e vinculá-lo ao cliente
- **Resultado esperado:** Veículo criado e associado corretamente

## CAD-006 — Placa duplicada
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Veículo com placa já existente
- **Ação:** Cadastrar mesma placa novamente
- **Resultado esperado:** Duplicidade impedida ou explicitamente tratada

## CAD-007 — Veículo sem cliente
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Nenhuma
- **Ação:** Tentar cadastrar veículo sem vínculo quando obrigatório
- **Resultado esperado:** Sistema aplica a regra sem criar vínculo inconsistente

## CAD-008 — Alterar dados do cliente
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Cliente existente
- **Ação:** Editar dados cadastrais
- **Resultado esperado:** Dados atualizados sem perda de histórico transacional

## CAD-009 — Inativar cliente com histórico
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Cliente com OS encerrada
- **Ação:** Inativar cliente
- **Resultado esperado:** Cliente inativo; histórico permanece consultável

## CAD-010 — Excluir cliente com histórico
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** Cliente com transações
- **Ação:** Tentar exclusão física
- **Resultado esperado:** Operação bloqueada ou convertida em inativação auditável

## CAD-011 — Troca de proprietário/vínculo
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Veículo com histórico
- **Ação:** Alterar vínculo do veículo
- **Resultado esperado:** Histórico anterior preservado e novo vínculo rastreável

## CAD-012 — Pesquisa de histórico do veículo
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Veículo com múltiplas OS
- **Ação:** Consultar veículo
- **Resultado esperado:** Sistema retorna histórico coerente


# Orçamento
## ORC-001 — Criar orçamento válido
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Cliente e veículo válidos
- **Ação:** Criar orçamento
- **Resultado esperado:** Orçamento salvo em estado inicial equivalente a RASCUNHO

## ORC-002 — Orçamento sem cliente
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Nenhuma
- **Ação:** Salvar orçamento sem cliente
- **Resultado esperado:** Operação bloqueada

## ORC-003 — Orçamento sem veículo
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Cliente válido
- **Ação:** Salvar sem veículo
- **Resultado esperado:** Operação bloqueada ou tratada conforme regra explícita; não pode ficar vínculo inconsistente

## ORC-004 — Adicionar serviço
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Adicionar serviço com quantidade/preço válidos
- **Resultado esperado:** Item incluído e total recalculado

## ORC-005 — Adicionar peça
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-014
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Adicionar peça válida
- **Resultado esperado:** Item incluído e total recalculado sem baixar estoque prematuramente

## ORC-006 — Alterar quantidade
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Item existente
- **Ação:** Alterar quantidade
- **Resultado esperado:** Subtotal e total recalculados corretamente

## ORC-007 — Aplicar desconto
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-011
- **Pré-condição:** Orçamento válido
- **Ação:** Aplicar desconto permitido
- **Resultado esperado:** Total final correto e desconto rastreável

## ORC-008 — Desconto inválido
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-011
- **Pré-condição:** Orçamento válido
- **Ação:** Inserir desconto negativo ou superior ao permitido lógico
- **Resultado esperado:** Operação bloqueada

## ORC-009 — Quantidade zero
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Adicionar item com quantidade zero
- **Resultado esperado:** Operação bloqueada ou item não persistido

## ORC-010 — Quantidade negativa
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Adicionar item com quantidade negativa
- **Resultado esperado:** Operação bloqueada

## ORC-011 — Preço negativo
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Adicionar item com preço negativo
- **Resultado esperado:** Operação bloqueada

## ORC-012 — Total consistente
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-003
- **Pré-condição:** Múltiplos itens/descontos
- **Ação:** Salvar orçamento
- **Resultado esperado:** Total persistido/retornado reconcilia com itens

## ORC-013 — Gerar PDF
- **Criticidade:** Média
- **Camada sugerida:** E2E/Manual
- **Automação:** Parcial
- **Regra relacionada:** BR-004
- **Pré-condição:** Orçamento válido
- **Ação:** Gerar documento
- **Resultado esperado:** PDF representa cliente, veículo, itens, totais e versão vigente

## ORC-014 — Marcar como enviado
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-004
- **Pré-condição:** Orçamento válido
- **Ação:** Executar ação de envio
- **Resultado esperado:** Estado atualizado e evento auditado

## ORC-015 — Editar orçamento enviado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-007
- **Pré-condição:** Orçamento enviado
- **Ação:** Alterar item
- **Resultado esperado:** Mudança controlada e rastreável; não apaga versão/evento anterior

## ORC-016 — Duplo clique ao salvar/enviar
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** Orçamento válido
- **Ação:** Submeter mesma operação duas vezes rapidamente
- **Resultado esperado:** Não duplica orçamento/evento crítico


# Aprovação
## APR-001 — Aprovação integral
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-005
- **Pré-condição:** Orçamento aguardando aprovação
- **Ação:** Aprovar todos os itens
- **Resultado esperado:** Todos os itens ficam aprovados com evidência de autorização

## APR-002 — Aprovação parcial
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Orçamento com vários itens
- **Ação:** Aprovar apenas subconjunto
- **Resultado esperado:** Somente itens selecionados ficam aprovados

## APR-003 — Reprovação integral
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Orçamento aguardando aprovação
- **Ação:** Reprovar orçamento
- **Resultado esperado:** Conversão em OS fica bloqueada

## APR-004 — Registrar aprovação por sistema
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-005
- **Pré-condição:** Orçamento enviado
- **Ação:** Aprovar via botão
- **Resultado esperado:** Usuário, data/hora e meio ficam registrados

## APR-005 — Registrar aprovação por e-mail
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-005
- **Pré-condição:** Orçamento enviado
- **Ação:** Registrar evidência de e-mail
- **Resultado esperado:** Aprovação vinculada ao orçamento e auditável

## APR-006 — Registrar aprovação verbal
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-005
- **Pré-condição:** Orçamento enviado
- **Ação:** Registrar autorização verbal/documento de áudio ou referência
- **Resultado esperado:** Responsável, data/hora e meio registrados

## APR-007 — Aprovação por usuário não autorizado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário executor
- **Ação:** Tentar aprovar orçamento
- **Resultado esperado:** Operação bloqueada

## APR-008 — Alterar preço após aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-007
- **Pré-condição:** Item aprovado
- **Ação:** Alterar preço
- **Resultado esperado:** Item exige nova aprovação/versão; aprovação anterior preservada

## APR-009 — Alterar quantidade após aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-007
- **Pré-condição:** Item aprovado
- **Ação:** Alterar quantidade
- **Resultado esperado:** Nova aprovação exigida

## APR-010 — Adicionar item após aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-009
- **Pré-condição:** Orçamento aprovado
- **Ação:** Adicionar novo item
- **Resultado esperado:** Novo item fica pendente de aprovação

## APR-011 — Apagar evidência de aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** Aprovação existente
- **Ação:** Tentar excluir evidência/histórico
- **Resultado esperado:** Histórico não desaparece; cancelamento é auditável

## APR-012 — Repetir aprovação
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** Orçamento já aprovado
- **Ação:** Submeter mesma aprovação novamente
- **Resultado esperado:** Não cria efeitos duplicados


# Ordem de Serviço
## OS-001 — Converter orçamento aprovado
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-008
- **Pré-condição:** Orçamento integralmente aprovado
- **Ação:** Converter para OS
- **Resultado esperado:** OS criada com itens aprovados

## OS-002 — Converter aprovação parcial
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Orçamento parcialmente aprovado
- **Ação:** Converter para OS
- **Resultado esperado:** Somente itens aprovados entram na OS

## OS-003 — Converter sem aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-008
- **Pré-condição:** Orçamento pendente/reprovado
- **Ação:** Tentar converter
- **Resultado esperado:** Operação bloqueada; nenhuma OS criada

## OS-004 — Conversão duplicada
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-008
- **Pré-condição:** Orçamento já convertido
- **Ação:** Converter novamente
- **Resultado esperado:** Segunda OS não é criada

## OS-005 — Herança de cliente/veículo
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-008
- **Pré-condição:** Orçamento aprovado
- **Ação:** Converter
- **Resultado esperado:** OS mantém vínculos corretos

## OS-006 — Herança de valores
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-008
- **Pré-condição:** Orçamento aprovado
- **Ação:** Converter
- **Resultado esperado:** Valores da OS reconciliam com itens aprovados

## OS-007 — Mudança de estado válida
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-035
- **Pré-condição:** OS aberta
- **Ação:** Iniciar execução
- **Resultado esperado:** Estado muda conforme fluxo permitido

## OS-008 — Pular estado obrigatório
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-035
- **Pré-condição:** OS aberta
- **Ação:** Forçar diretamente estado encerrada
- **Resultado esperado:** Operação bloqueada ou segue regra formal explícita

## OS-009 — Reabrir encerrada
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** OS encerrada
- **Ação:** Tentar voltar para execução
- **Resultado esperado:** Bloqueio ou fluxo excepcional auditável

## OS-010 — Cancelar OS com movimentação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-016
- **Pré-condição:** OS com peças baixadas
- **Ação:** Cancelar OS
- **Resultado esperado:** Sistema exige tratamento/estorno consistente das movimentações

## OS-011 — Duplo início
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** OS aberta
- **Ação:** Acionar iniciar duas vezes
- **Resultado esperado:** Não duplica eventos nem executores

## OS-012 — Excluir OS encerrada
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** OS encerrada
- **Ação:** Tentar exclusão física
- **Resultado esperado:** Operação bloqueada


# Adicionais
## ADC-001 — Criar adicional
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-009
- **Pré-condição:** OS em execução
- **Ação:** Adicionar serviço/peça não prevista
- **Resultado esperado:** Item adicional criado como pendente de aprovação

## ADC-002 — Executar adicional sem aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-009
- **Pré-condição:** Adicional pendente
- **Ação:** Marcar como executado
- **Resultado esperado:** Operação bloqueada

## ADC-003 — Aprovar adicional
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-009
- **Pré-condição:** Adicional pendente
- **Ação:** Registrar aprovação
- **Resultado esperado:** Item liberado para execução

## ADC-004 — Reprovar adicional
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Adicional pendente
- **Ação:** Reprovar
- **Resultado esperado:** Item não entra em execução/faturamento

## ADC-005 — Alterar adicional aprovado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-007
- **Pré-condição:** Adicional aprovado
- **Ação:** Alterar valor/quantidade
- **Resultado esperado:** Nova aprovação exigida

## ADC-006 — Preservar orçamento original
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** OS com adicional
- **Ação:** Consultar histórico
- **Resultado esperado:** Aprovação original e adicional aparecem separadamente

## ADC-007 — Cobrança sem adicional rejeitado
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Adicional rejeitado
- **Ação:** Calcular total final
- **Resultado esperado:** Adicional rejeitado não é cobrado

## ADC-008 — Dupla criação por clique
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** OS em execução
- **Ação:** Enviar mesma inclusão duas vezes
- **Resultado esperado:** Não duplica adicional


# Estoque
## EST-001 — Entrada por compra
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-017
- **Pré-condição:** Item existente
- **Ação:** Registrar entrada de 10 unidades
- **Resultado esperado:** Saldo aumenta 10 e movimentação é registrada

## EST-002 — Entrada com quantidade inválida
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-017
- **Pré-condição:** Item existente
- **Ação:** Registrar zero/negativo
- **Resultado esperado:** Operação bloqueada

## EST-003 — Entrada com custo inválido
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-017
- **Pré-condição:** Item existente
- **Ação:** Registrar custo negativo
- **Resultado esperado:** Operação bloqueada

## EST-004 — Baixa na conversão para OS
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-014
- **Pré-condição:** Orçamento aprovado com peça e estoque suficiente
- **Ação:** Converter em OS
- **Resultado esperado:** Peça é baixada/comprometida uma única vez conforme regra vigente

## EST-005 — Baixa vinculada à OS
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-014
- **Pré-condição:** OS gerou saída
- **Ação:** Consultar movimentação
- **Resultado esperado:** Movimento referencia OS, item, usuário e data/hora

## EST-006 — Venda avulsa
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-032
- **Pré-condição:** Estoque suficiente
- **Ação:** Registrar venda de peça
- **Resultado esperado:** Saldo reduz e movimento referencia venda

## EST-007 — Saldo insuficiente
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-015
- **Pré-condição:** Saldo 2
- **Ação:** Tentar saída de 3
- **Resultado esperado:** Operação bloqueada; saldo não fica negativo

## EST-008 — Quantidade negativa na saída
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-015
- **Pré-condição:** Estoque existente
- **Ação:** Tentar saída negativa
- **Resultado esperado:** Operação bloqueada

## EST-009 — Dupla baixa da mesma OS
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** OS já baixou peças
- **Ação:** Repetir evento de baixa/conversão
- **Resultado esperado:** Não duplica saída

## EST-010 — Estorno de baixa
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-016
- **Pré-condição:** Movimentação existente
- **Ação:** Estornar
- **Resultado esperado:** Movimento compensatório restaura saldo e preserva original

## EST-011 — Excluir movimentação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** Movimentação com efeito
- **Ação:** Tentar apagar
- **Resultado esperado:** Exclusão física bloqueada

## EST-012 — Alterar custo histórico
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Entradas anteriores existentes
- **Ação:** Alterar custo atual do item
- **Resultado esperado:** Movimentos históricos preservam seus valores

## EST-013 — Concorrência de saldo
- **Criticidade:** Crítica
- **Camada sugerida:** Integration
- **Automação:** Sim
- **Regra relacionada:** BR-034
- **Pré-condição:** Saldo 5; duas sessões
- **Ação:** Duas saídas simultâneas de 4
- **Resultado esperado:** Somente uma conclui; saldo nunca negativo

## EST-014 — Reconciliação de saldo
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/Integration
- **Automação:** Sim
- **Regra relacionada:** BR-014
- **Pré-condição:** Histórico de entradas/saídas
- **Ação:** Recalcular saldo
- **Resultado esperado:** Saldo atual = entradas - saídas + estornos válidos

## EST-015 — Sem reserva obrigatória
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-038
- **Pré-condição:** Peça disponível
- **Ação:** Criar orçamento sem reservar
- **Resultado esperado:** Orçamento não depende de reserva prévia

## EST-016 — Venda e OS concorrentes
- **Criticidade:** Crítica
- **Camada sugerida:** Integration
- **Automação:** Sim
- **Regra relacionada:** BR-034
- **Pré-condição:** Saldo limitado
- **Ação:** Venda avulsa e conversão de OS simultâneas
- **Resultado esperado:** Consistência transacional preservada


# Execução
## EXE-001 — Associar executor
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-018
- **Pré-condição:** OS em execução
- **Ação:** Adicionar executor
- **Resultado esperado:** Executor vinculado

## EXE-002 — Múltiplos executores
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-018
- **Pré-condição:** OS em execução
- **Ação:** Adicionar dois ou mais executores
- **Resultado esperado:** Todos permanecem registrados

## EXE-003 — Remover executor
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-018
- **Pré-condição:** Executor vinculado
- **Ação:** Remover da execução atual
- **Resultado esperado:** Histórico de participação não é perdido

## EXE-004 — Registrar observação
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** OS em execução
- **Ação:** Adicionar observação
- **Resultado esperado:** Observação fica vinculada à OS e autor

## EXE-005 — Foto antes
- **Criticidade:** Média
- **Camada sugerida:** E2E/API
- **Automação:** Parcial
- **Regra relacionada:** BR-019
- **Pré-condição:** OS aberta/em execução
- **Ação:** Anexar foto inicial
- **Resultado esperado:** Arquivo/referência vinculado corretamente

## EXE-006 — Foto depois
- **Criticidade:** Média
- **Camada sugerida:** E2E/API
- **Automação:** Parcial
- **Regra relacionada:** BR-019
- **Pré-condição:** OS concluível
- **Ação:** Anexar foto final
- **Resultado esperado:** Arquivo/referência vinculado corretamente

## EXE-007 — Upload inválido
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** OS existente
- **Ação:** Enviar formato/tamanho inválido
- **Resultado esperado:** Sistema rejeita com mensagem adequada

## EXE-008 — Executor altera preço
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário executor
- **Ação:** Tentar editar preço
- **Resultado esperado:** Operação bloqueada no backend

## EXE-009 — Executor aprova orçamento
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário executor
- **Ação:** Chamar endpoint de aprovação
- **Resultado esperado:** Operação bloqueada

## EXE-010 — Registrar serviço executado
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Item aprovado
- **Ação:** Marcar execução
- **Resultado esperado:** Registro mantém executor/data/hora


# Conclusão
## CON-001 — Concluir OS válida
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-021
- **Pré-condição:** Itens obrigatórios executados
- **Ação:** Concluir serviço
- **Resultado esperado:** Estado muda para serviço concluído

## CON-002 — Concluir com item aprovado pendente
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-021
- **Pré-condição:** Item obrigatório não executado
- **Ação:** Tentar concluir
- **Resultado esperado:** Bloqueio

## CON-003 — Checklist completo
- **Criticidade:** Alta
- **Camada sugerida:** E2E/API
- **Automação:** Sim
- **Regra relacionada:** BR-020
- **Pré-condição:** Checklist obrigatório configurado
- **Ação:** Preencher e concluir
- **Resultado esperado:** Conclusão permitida

## CON-004 — Checklist incompleto
- **Criticidade:** Alta
- **Camada sugerida:** E2E/API
- **Automação:** Sim
- **Regra relacionada:** BR-020
- **Pré-condição:** Checklist obrigatório configurado
- **Ação:** Tentar concluir/liberar
- **Resultado esperado:** Bloqueio

## CON-005 — Gerar relatório
- **Criticidade:** Média
- **Camada sugerida:** E2E/Manual
- **Automação:** Parcial
- **Regra relacionada:** BR-025
- **Pré-condição:** OS concluída
- **Ação:** Gerar relatório final
- **Resultado esperado:** Documento contém dados coerentes

## CON-006 — Relatório com múltiplos executores
- **Criticidade:** Média
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-018
- **Pré-condição:** OS com vários executores
- **Ação:** Gerar relatório
- **Resultado esperado:** Todos os responsáveis pertinentes aparecem

## CON-007 — Alterar execução após conclusão
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** OS concluída
- **Ação:** Editar item executado
- **Resultado esperado:** Bloqueio ou reabertura formal auditada

## CON-008 — Conclusão repetida
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** OS já concluída
- **Ação:** Enviar ação novamente
- **Resultado esperado:** Não duplica eventos/efeitos


# Financeiro
## FIN-001 — Calcular total externo
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-001
- **Pré-condição:** OS externa válida
- **Ação:** Calcular fechamento
- **Resultado esperado:** Total corresponde aos itens aprovados/executados cobrados

## FIN-002 — Não cobrar item rejeitado
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Item rejeitado
- **Ação:** Fechar conta
- **Resultado esperado:** Item não compõe total

## FIN-003 — Aplicar desconto final autorizado
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-011
- **Pré-condição:** Usuário autorizado
- **Ação:** Aplicar desconto válido
- **Resultado esperado:** Total e auditoria corretos

## FIN-004 — Parcelamento
- **Criticidade:** Crítica
- **Camada sugerida:** Unit/API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-012
- **Pré-condição:** Cliente externo
- **Ação:** Criar parcelas
- **Resultado esperado:** Soma das parcelas = total negociado

## FIN-005 — Parcelamento inconsistente
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-012
- **Pré-condição:** Total conhecido
- **Ação:** Salvar parcelas cuja soma diverge
- **Resultado esperado:** Operação bloqueada ou exige ajuste explícito

## FIN-006 — Registrar pagamento confirmado
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-013
- **Pré-condição:** Confirmação financeira disponível
- **Ação:** Registrar pagamento
- **Resultado esperado:** Status financeiro atualizado com autor/data

## FIN-007 — Presumir pagamento
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-013
- **Pré-condição:** OS concluída sem confirmação
- **Ação:** Tentar marcar automaticamente como pago por conclusão
- **Resultado esperado:** Sistema não presume pagamento

## FIN-008 — Pagamento parcial
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-012
- **Pré-condição:** Parcelamento existente
- **Ação:** Registrar parte do valor
- **Resultado esperado:** Saldo remanescente correto

## FIN-009 — Alterar valor após pagamento
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Pagamento confirmado
- **Ação:** Editar valor base
- **Resultado esperado:** Bloqueio ou ajuste formal auditável

## FIN-010 — Cliente interno
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Parcial
- **Regra relacionada:** BR-036
- **Pré-condição:** Cliente interno
- **Ação:** Fechar OS
- **Resultado esperado:** Não gerar faturamento externo automaticamente; caso fica pendente da regra interna


# Liberação
## LIB-001 — Liberar após pagamento
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-023
- **Pré-condição:** OS externa concluída e paga
- **Ação:** Liberar veículo
- **Resultado esperado:** Liberação permitida por usuário autorizado

## LIB-002 — Liberar com termo de débito
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-023
- **Pré-condição:** OS externa concluída sem pagamento; termo válido
- **Ação:** Liberar
- **Resultado esperado:** Liberação permitida e termo vinculado

## LIB-003 — Sem pagamento e sem termo
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-023
- **Pré-condição:** OS externa concluída
- **Ação:** Tentar liberar
- **Resultado esperado:** Liberação bloqueada

## LIB-004 — Executor tenta liberar
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-022
- **Pré-condição:** OS elegível; usuário executor
- **Ação:** Tentar liberar
- **Resultado esperado:** Bloqueio de permissão

## LIB-005 — Encarregado libera
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-022
- **Pré-condição:** OS elegível
- **Ação:** Liberar como encarregado
- **Resultado esperado:** Permitido

## LIB-006 — Administrativo libera
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-022
- **Pré-condição:** OS elegível
- **Ação:** Liberar como administrativo
- **Resultado esperado:** Permitido

## LIB-007 — Liberar com checklist incompleto
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-020
- **Pré-condição:** OS financeiramente elegível; checklist pendente
- **Ação:** Tentar liberar
- **Resultado esperado:** Bloqueio quando checklist for obrigatório

## LIB-008 — Dupla liberação
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** OS já liberada
- **Ação:** Enviar ação novamente
- **Resultado esperado:** Não duplica evento nem documentos


# Garantia
## GAR-001 — Iniciar garantia
- **Criticidade:** Alta
- **Camada sugerida:** Unit/API
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** OS encerrada
- **Ação:** Consultar garantia
- **Resultado esperado:** Prazo de 90 dias calculado a partir do marco definido

## GAR-002 — Retorno dentro de 90 dias
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** OS dentro do prazo
- **Ação:** Abrir retorno
- **Resultado esperado:** Sistema identifica elegibilidade potencial e vincula OS original

## GAR-003 — Retorno após 90 dias
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** Prazo expirado
- **Ação:** Abrir retorno
- **Resultado esperado:** Sistema sinaliza fora do prazo padrão

## GAR-004 — Vínculo com OS original
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** Retorno em garantia
- **Ação:** Consultar registro
- **Resultado esperado:** OS original acessível

## GAR-005 — Item não relacionado
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** OS original possui serviço A
- **Ação:** Abrir garantia para serviço B
- **Resultado esperado:** Sistema não trata automaticamente item sem vínculo como garantia

## GAR-006 — Alterar data para forçar garantia
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Usuário comum
- **Ação:** Tentar editar datas críticas
- **Resultado esperado:** Bloqueio/permissão e auditoria

## GAR-007 — Relatório de garantia
- **Criticidade:** Média
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-025
- **Pré-condição:** Retorno vinculado
- **Ação:** Gerar relatório
- **Resultado esperado:** Documento mostra OS original e retorno

## GAR-008 — Garantia duplicada por clique
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** Retorno em criação
- **Ação:** Submeter duas vezes
- **Resultado esperado:** Não cria ocorrências duplicadas


# Auditoria
## AUD-001 — Alteração de preço
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Item existente
- **Ação:** Alterar preço
- **Resultado esperado:** Auditoria contém antes/depois/usuário/data

## AUD-002 — Mudança de status
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Registro transacional
- **Ação:** Alterar status
- **Resultado esperado:** Evento auditado

## AUD-003 — Cancelamento
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Registro cancelável
- **Ação:** Cancelar
- **Resultado esperado:** Motivo/responsável preservados

## AUD-004 — Estorno de estoque
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-016
- **Pré-condição:** Movimentação existente
- **Ação:** Estornar
- **Resultado esperado:** Original e compensatório ficam visíveis

## AUD-005 — Alteração de aprovação
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-027
- **Pré-condição:** Aprovação existente
- **Ação:** Modificar/cancelar
- **Resultado esperado:** Histórico anterior permanece

## AUD-006 — Tentativa de exclusão histórica
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-026
- **Pré-condição:** Registro crítico
- **Ação:** Excluir
- **Resultado esperado:** Bloqueio ou trilha completa conforme política


# Permissões
## PER-001 — Executor altera preço
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Executor autenticado
- **Ação:** Chamar endpoint diretamente
- **Resultado esperado:** 403/negação equivalente

## PER-002 — Executor cancela OS
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Executor autenticado
- **Ação:** Chamar cancelamento
- **Resultado esperado:** Bloqueio

## PER-003 — Encarregado altera preço
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-010
- **Pré-condição:** Encarregado autenticado
- **Ação:** Alterar preço permitido
- **Resultado esperado:** Operação permitida e auditada

## PER-004 — Usuário sem perfil tenta liberar
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-022
- **Pré-condição:** Perfil sem permissão
- **Ação:** Chamar endpoint
- **Resultado esperado:** Bloqueio

## PER-005 — Manipulação de ID
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Usuário autenticado sem acesso ao registro
- **Ação:** Trocar ID na URL/payload
- **Resultado esperado:** Acesso negado sem exposição indevida

## PER-006 — Botão oculto e API protegida
- **Criticidade:** Alta
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Usuário sem permissão
- **Ação:** Ver tela e chamar endpoint
- **Resultado esperado:** UI não oferece ação e API também bloqueia


# Documentos
## DOC-001 — PDF orçamento versão correta
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-004
- **Pré-condição:** Orçamento versionado
- **Ação:** Gerar PDF da versão atual
- **Resultado esperado:** Documento corresponde exatamente à versão selecionada

## DOC-002 — PDF após alteração
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-007
- **Pré-condição:** Orçamento alterado
- **Ação:** Gerar novo PDF
- **Resultado esperado:** Novo documento reflete nova versão; anterior permanece rastreável

## DOC-003 — Relatório encerramento
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-025
- **Pré-condição:** OS encerrada
- **Ação:** Gerar relatório
- **Resultado esperado:** Dados de cliente, veículo, itens, executores e datas corretos

## DOC-004 — Termo de débito vinculado
- **Criticidade:** Crítica
- **Camada sugerida:** API/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-023
- **Pré-condição:** Liberação via termo
- **Ação:** Consultar OS
- **Resultado esperado:** Termo/evidência está associado à liberação

## DOC-005 — Documento órfão
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Registro relacionado inexistente/inválido
- **Ação:** Tentar anexar documento
- **Resultado esperado:** Sistema impede associação inválida

## DOC-006 — Acesso a anexo por usuário indevido
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Anexo existente
- **Ação:** Acessar URL/endpoint sem permissão
- **Resultado esperado:** Acesso negado


# Fluxo E2E
## E2E-001 — Cliente externo normal
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-001
- **Pré-condição:** Ambiente limpo com estoque
- **Ação:** Cadastrar cliente/veículo, orçar, aprovar, converter, executar, concluir, pagar e liberar
- **Resultado esperado:** Fluxo completo encerra com dados reconciliados

## E2E-002 — Aprovação parcial + adicional rejeitado
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-006
- **Pré-condição:** Orçamento com múltiplos itens
- **Ação:** Aprovar parte, converter, criar adicional e rejeitá-lo
- **Resultado esperado:** Cobrança contém apenas itens autorizados

## E2E-003 — Sem estoque suficiente
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-015
- **Pré-condição:** Orçamento aprovado com peça sem saldo
- **Ação:** Converter para OS
- **Resultado esperado:** Sistema bloqueia/encaminha sem gerar saldo negativo

## E2E-004 — Liberação por termo
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-023
- **Pré-condição:** OS externa concluída sem pagamento
- **Ação:** Registrar termo e liberar
- **Resultado esperado:** Liberação válida e auditada

## E2E-005 — Bloqueio financeiro
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-023
- **Pré-condição:** OS externa concluída sem pagamento/termo
- **Ação:** Tentar liberar
- **Resultado esperado:** Fluxo para no bloqueio

## E2E-006 — Garantia dentro do prazo
- **Criticidade:** Alta
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-024
- **Pré-condição:** OS encerrada
- **Ação:** Abrir retorno em até 90 dias
- **Resultado esperado:** Retorno vinculado à OS original

## E2E-007 — Múltiplos executores
- **Criticidade:** Alta
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-018
- **Pré-condição:** OS válida
- **Ação:** Associar executores, executar e encerrar
- **Resultado esperado:** Histórico e relatório preservam participantes

## E2E-008 — Cancelamento com estoque
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-016
- **Pré-condição:** OS com baixa
- **Ação:** Cancelar via fluxo permitido
- **Resultado esperado:** Estoque e auditoria ficam consistentes

## E2E-009 — Dupla submissão
- **Criticidade:** Crítica
- **Camada sugerida:** E2E
- **Automação:** Sim
- **Regra relacionada:** BR-033
- **Pré-condição:** Operação crítica disponível
- **Ação:** Simular clique duplo/retry de rede
- **Resultado esperado:** Sem duplicação de OS/baixa/liberação

## E2E-010 — Permissão ponta a ponta
- **Criticidade:** Crítica
- **Camada sugerida:** E2E/API
- **Automação:** Sim
- **Regra relacionada:** BR-028
- **Pré-condição:** Executor autenticado
- **Ação:** Tentar ações comerciais/administrativas
- **Resultado esperado:** Todas as ações não autorizadas são bloqueadas na UI e API


# Não funcional
## NFR-001 — Transação atômica na conversão
- **Criticidade:** Crítica
- **Camada sugerida:** Integration
- **Automação:** Sim
- **Regra relacionada:** BR-034
- **Pré-condição:** Orçamento aprovado com peças
- **Ação:** Forçar falha durante conversão
- **Resultado esperado:** Não fica OS parcial nem estoque inconsistente

## NFR-002 — Transação atômica no estorno
- **Criticidade:** Crítica
- **Camada sugerida:** Integration
- **Automação:** Sim
- **Regra relacionada:** BR-034
- **Pré-condição:** Movimentação existente
- **Ação:** Forçar falha parcial
- **Resultado esperado:** Estado anterior permanece consistente

## NFR-003 — Resposta a payload inesperado
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Endpoint crítico
- **Ação:** Enviar campos extras/tipos errados
- **Resultado esperado:** Validação rejeita sem erro 500 indevido

## NFR-004 — IDs inexistentes
- **Criticidade:** Média
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Endpoint de OS/orçamento
- **Ação:** Usar ID inexistente
- **Resultado esperado:** Resposta 404/erro de domínio coerente

## NFR-005 — Referência cruzada inválida
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-002
- **Pré-condição:** Cliente A/veículo B
- **Ação:** Forçar vínculo incompatível
- **Resultado esperado:** Sistema rejeita vínculo inconsistente

## NFR-006 — Repetibilidade da suíte
- **Criticidade:** Alta
- **Camada sugerida:** Test Infra
- **Automação:** Sim
- **Regra relacionada:** —
- **Pré-condição:** Banco de teste limpo
- **Ação:** Executar suíte duas vezes
- **Resultado esperado:** Resultados equivalentes e sem dependência de ordem

## NFR-007 — Isolamento entre testes
- **Criticidade:** Alta
- **Camada sugerida:** Test Infra
- **Automação:** Sim
- **Regra relacionada:** —
- **Pré-condição:** Testes paralelos/serializados
- **Ação:** Executar suíte
- **Resultado esperado:** Um teste não contamina outro

## NFR-008 — Seed determinístico
- **Criticidade:** Média
- **Camada sugerida:** Test Infra
- **Automação:** Sim
- **Regra relacionada:** —
- **Pré-condição:** Ambiente de teste
- **Ação:** Recriar dados
- **Resultado esperado:** Dados conhecidos e reproduzíveis

## NFR-009 — Logs sem segredo
- **Criticidade:** Alta
- **Camada sugerida:** Manual/Integration
- **Automação:** Parcial
- **Regra relacionada:** BR-040
- **Pré-condição:** Operações autenticadas
- **Ação:** Inspecionar logs
- **Resultado esperado:** Sem senha/token sensível em claro

## NFR-010 — Erro controlado de arquivo
- **Criticidade:** Média
- **Camada sugerida:** API/E2E
- **Automação:** Sim
- **Regra relacionada:** BR-040
- **Pré-condição:** Upload/download
- **Ação:** Simular arquivo ausente/corrompido
- **Resultado esperado:** Erro tratado sem quebrar transação principal


# Decisão pendente
## PEN-001 — Cobrança de cliente interno
- **Criticidade:** Alta
- **Camada sugerida:** Manual/API
- **Automação:** Não
- **Regra relacionada:** BR-036
- **Pré-condição:** Cliente interno
- **Ação:** Tentar fechar financeiramente
- **Resultado esperado:** Classificar como PENDENTE_DECISÃO se não houver regra explícita

## PEN-002 — Hora interna
- **Criticidade:** Média
- **Camada sugerida:** Manual
- **Automação:** Não
- **Regra relacionada:** BR-036
- **Pré-condição:** Cliente/OS interna
- **Ação:** Procurar cálculo de hora interna
- **Resultado esperado:** Não inventar critério; registrar necessidade de definição

## PEN-003 — Faixas de prazo por valor
- **Criticidade:** Média
- **Camada sugerida:** Manual/API
- **Automação:** Não
- **Regra relacionada:** BR-029
- **Pré-condição:** Orçamento válido
- **Ação:** Calcular prazo automaticamente
- **Resultado esperado:** Se faixas não existirem, registrar PENDENTE_DECISÃO

## PEN-004 — Integração de boleto
- **Criticidade:** Baixa
- **Camada sugerida:** Manual
- **Automação:** Não
- **Regra relacionada:** BR-037
- **Pré-condição:** Cliente externo
- **Ação:** Buscar fluxo de boleto
- **Resultado esperado:** Não exigir integração sem definição

## PEN-005 — Emissão fiscal
- **Criticidade:** Média
- **Camada sugerida:** Manual
- **Automação:** Não
- **Regra relacionada:** BR-039
- **Pré-condição:** OS externa encerrada
- **Ação:** Buscar emissão NF
- **Resultado esperado:** Fora do escopo obrigatório até definição

## PEN-006 — Obrigatoriedade de fotos por serviço
- **Criticidade:** Média
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-019
- **Pré-condição:** OS de diferentes tipos
- **Ação:** Concluir sem fotos
- **Resultado esperado:** Se regra não estiver configurada, registrar decisão pendente

## PEN-007 — Limite de desconto
- **Criticidade:** Alta
- **Camada sugerida:** Manual/API
- **Automação:** Não
- **Regra relacionada:** BR-011
- **Pré-condição:** Orçamento
- **Ação:** Aplicar descontos em faixas
- **Resultado esperado:** Se não houver política de limite, não inventar teto; registrar decisão

## PEN-008 — Campos obrigatórios do termo de débito
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Parcial
- **Regra relacionada:** BR-023
- **Pré-condição:** Liberação por termo
- **Ação:** Criar termo
- **Resultado esperado:** Validar apenas campos explicitamente configurados; registrar lacunas

---

## SERV-001 — Criar serviço
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Perfil suporte_administrativo ou administrador_tecnico
- **Ação:** `rpc_criar_servico` sem informar código
- **Resultado esperado:** Serviço criado com código gerado automaticamente no padrão `SV-XXX`

## SERV-002 — Código duplicado bloqueado
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Já existe serviço com código X
- **Ação:** Criar novo serviço informando o mesmo código X
- **Resultado esperado:** Bloqueado por UNIQUE (23505)

## SERV-003 — Preço negativo bloqueado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** —
- **Ação:** Criar serviço com `preco_referencia` negativo
- **Resultado esperado:** Bloqueado pela RPC antes do INSERT

## SERV-004 — Inativar serviço
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço ativo
- **Ação:** `rpc_inativar_servico`
- **Resultado esperado:** `ativo=false` (soft-disable, sem exclusão física)

## SERV-005 — Serviço inativo não aparece em nova seleção
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço inativado (SERV-004)
- **Ação:** Consultar catálogo filtrando `ativo=true` (mesmo filtro usado pelo frontend ao popular a seleção do orçamento)
- **Resultado esperado:** Serviço inativo não aparece

## SERV-006 — Serviço inativo continua visível em histórico
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço inativado (SERV-004)
- **Ação:** Consultar catálogo sem filtro de `ativo`
- **Resultado esperado:** Serviço continua visível (RLS de SELECT não filtra por `ativo`)

## SERV-007 — Executor não altera catálogo
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Perfil executor
- **Ação:** Chamar `rpc_criar_servico`
- **Resultado esperado:** Bloqueado (P0001)

## SERV-008 — Encarregado/admin conforme permissão consegue alterar
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Perfil suporte_administrativo (RBAC espelha Peças — encarregado só consulta/seleciona, não cadastra)
- **Ação:** Chamar `rpc_criar_servico`
- **Resultado esperado:** Permitido

## SERV-009 — Anon bloqueado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Sem sessão (anon)
- **Ação:** Chamar `rpc_criar_servico` e fazer SELECT em `servicos`
- **Resultado esperado:** RPC bloqueada (P0001); SELECT retorna 0 linhas (RLS)

## SERV-010 — Usuário inativo bloqueado
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Usuário autenticado com `profiles.ativo=false`
- **Ação:** Chamar `rpc_criar_servico`
- **Resultado esperado:** Bloqueado (P0001) — `current_perfil()` já retorna NULL para inativo (ETAPA 3/AUT-004)

## SERV-ORC-001 — Snapshot imutável ao alterar o catálogo
- **Criticidade:** Crítica
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço R$450 adicionado a um item de orçamento
- **Ação:** Alterar `preco_referencia` do serviço para R$520 via `rpc_atualizar_servico`
- **Resultado esperado:** Item de orçamento já salvo continua com `valor_unitario`=R$450

## SERV-ORC-002 — Preço editável no item, independente do catálogo
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço com `preco_referencia`=R$450
- **Ação:** Lançar o serviço no orçamento com `valor_unitario`=R$480 (divergente da referência)
- **Resultado esperado:** Item salvo com R$480; `servicos.preco_referencia` permanece R$450

## SERV-ORC-003 — Serviço avulso continua funcionando
- **Criticidade:** Alta
- **Camada sugerida:** API
- **Automação:** Sim
- **Regra relacionada:** BR-044
- **Pré-condição:** Orçamento em rascunho
- **Ação:** Inserir item de mão de obra sem `servico_id` nem `peca_id`
- **Resultado esperado:** Aceito; `natureza` computa `servico_avulso` automaticamente

## SERV-ORC-004 — Aprovação parcial com peça + serviço cadastrado + avulso
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Não
- **Regra relacionada:** BR-044, BR-042
- **Pré-condição:** Orçamento com 1 peça, 1 serviço cadastrado, 1 serviço avulso
- **Ação:** Aprovar peça + serviço cadastrado, rejeitar avulso, converter em OS
- **Resultado esperado:** OS contém só os 2 itens aprovados — não testado nesta rodada; o mecanismo de aprovação parcial/conversão (`rpc_decidir_item_orcamento`, `rpc_criar_os`) não foi alterado por esta feature (só ganhou uma FK adicional em `orcamento_itens` que ele não lê), então o comportamento já validado nos testes ORC-*/APR-* existentes deve se aplicar sem mudança — mas não houve um caso combinando os 3 tipos de item na mesma OS

## SERV-GAR-001 — Garantia não é afetada por mudança futura no catálogo
- **Criticidade:** Alta
- **Camada sugerida:** Manual/E2E
- **Automação:** Não
- **Regra relacionada:** BR-044
- **Pré-condição:** Serviço cadastrado aprovado/executado, depois alterado no catálogo
- **Ação:** Abrir garantia sobre a OS original
- **Resultado esperado:** Identificação histórica do item não muda — não testado ponta a ponta nesta rodada; por construção, `os_garantia_itens` referencia `orcamento_item_original_id` (a linha já salva de `orcamento_itens`, com seu snapshot), nunca `servicos` diretamente, então mudar o catálogo depois não tem caminho para alcançar o registro de garantia

---

**Total de casos:** 191
