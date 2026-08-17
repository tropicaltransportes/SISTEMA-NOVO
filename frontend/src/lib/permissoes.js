// ETAPA 4 (P1-A) — item A: RBAC de frontend centralizado.
//
// Espelha EXATAMENTE os perfis aceitos pelas RPCs/policies do backend (ver
// migrations em supabase/migrations/*.sql — cada constante abaixo tem a RPC
// ou policy correspondente citada no comentário). O frontend NUNCA é a
// autoridade real: mesmo que este arquivo fique desatualizado por engano, o
// backend (RLS + tem_perfil()/current_perfil()) continua bloqueando de
// verdade — este arquivo só evita que a interface OFEREÇA uma ação que o
// backend vai recusar, para uma experiência coerente (ver
// docs/testing/TEST_REPORT_P1A.md, item A / AUT-009 / PER-006).
//
// Um usuário com profiles.ativo=false não deve ver NENHUMA ação — isso é
// tratado à parte (auth.js força logout quando ativo=false), não por perfil.

export const PERFIS = {
  EXECUTOR: 'executor',
  ENCARREGADO: 'encarregado',
  SUPORTE_ADMINISTRATIVO: 'suporte_administrativo',
  DIRETORIA: 'diretoria',
  ADMINISTRADOR_TECNICO: 'administrador_tecnico',
}

// Cadastros (clientes/veículos) — clientes_insert_cadastro / clientes_update_cadastro
export const PODE_GERIR_CADASTROS = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]

// Orçamento: criar/enviar/versionar — rpc_enviar_orcamento / rpc_criar_versao_orcamento
export const PODE_GERIR_ORCAMENTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Orçamento: registrar autorização/comprovante do cliente — rpc_registrar_autorizacao_orcamento
export const PODE_AUTORIZAR_ORCAMENTO = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
// Orçamento: aprovar/rejeitar — rpc_aprovar_orcamento / rpc_rejeitar_orcamento
export const PODE_APROVAR_ORCAMENTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Preço de item de orçamento — orcamento_itens_update_rascunho (mesmos perfis de gerir orçamento)
export const PODE_EDITAR_PRECO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// OS: criar/transicionar — rpc_criar_os / rpc_transicionar_os / rpc_concluir_os
export const PODE_GERIR_OS = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: apontamento de execução — os_executores_insert_proprio
export const PODE_APONTAR_EXECUCAO = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: responder checklist — os_checklist_insert_resposta
export const PODE_RESPONDER_CHECKLIST = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: baixar peça — rpc_baixar_peca_os
export const PODE_BAIXAR_PECA = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: marcar execução de item aprovado (mão de obra) — rpc_marcar_item_orcamento_execucao
export const PODE_MARCAR_EXECUCAO_ITEM = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: liberar — rpc_liberar_os
export const PODE_LIBERAR_OS = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: abrir garantia — rpc_criar_os_garantia
export const PODE_ABRIR_GARANTIA = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// OS: correção formal de apontamento pós-encerramento — rpc_corrigir_apontamento
export const PODE_CORRIGIR_APONTAMENTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Estoque: NF de entrada / ajustes — rpc_confirmar_nf_entrada / rpc_registrar_ajuste_estoque
export const PODE_GERIR_ESTOQUE = [PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]

// Financeiro: gerar cobrança/parcelar/receber — rpc_criar_cobranca / rpc_parcelar_cobranca / rpc_registrar_recebimento
export const PODE_GERIR_FINANCEIRO = [PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
// Financeiro: visualizar módulo (cobrancas_select_nao_executor: qualquer não-executor)
export const PODE_VER_FINANCEIRO = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.DIRETORIA, PERFIS.ADMINISTRADOR_TECNICO]

// Administração de sistema (checklist templates, faixas de acréscimo)
export const PODE_GERIR_CHECKLIST = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
export const PODE_GERIR_FAIXAS_ACRESCIMO = [PERFIS.ADMINISTRADOR_TECNICO]

// ETAPA 5 (P1-B) — APR-002/004/005/006: decisão por item de orçamento (com
// meio de aprovação estruturado) — rpc_decidir_item_orcamento. Mesma união
// de perfis que já registrava autorização/comprovante no P1-A (encarregado/
// suporte administrativo/admin técnico); executor NUNCA decide (BR-006/
// instrução item 13, explícito: "executor não pode aprovar").
export const PODE_DECIDIR_ITEM_ORCAMENTO = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]

// ETAPA 5 (P1-B) — ADC-001..008: adicionais durante a OS.
// Identificar necessidade (abrir o cabeçalho do adicional, só motivo, sem
// preço) — rpc_criar_os_adicional. Executor participa aqui (ele que está
// executando e percebe a necessidade), mas NUNCA precifica nem decide.
export const PODE_IDENTIFICAR_ADICIONAL = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Precificar/incluir item no adicional (define valor) — rpc_incluir_item_os_adicional.
// Mesma autoridade de preço do orçamento (BR-010): nunca o executor.
export const PODE_PRECIFICAR_ADICIONAL = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Decidir item do adicional (aprovar/rejeitar, meio estruturado) — rpc_decidir_item_os_adicional.
export const PODE_DECIDIR_ITEM_ADICIONAL = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
// Cancelar formalmente um adicional ainda aguardando aprovação — rpc_cancelar_os_adicional.
export const PODE_CANCELAR_ADICIONAL = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Marcar execução de item aprovado do adicional (mão de obra) — rpc_marcar_item_os_adicional_execucao.
export const PODE_MARCAR_EXECUCAO_ADICIONAL = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// ETAPA 6 (P1-C) — item 12: recursos novos (config administrativa, prazo,
// desconto, fotos, custo interno, garantia de adicional, remoção de
// executor, cancelamento formal de item, termo de ciência, relatórios).
// Mesma disciplina das etapas anteriores: cada constante espelha a RPC
// correspondente (comentada), e o backend continua sendo a autoridade real
// (tem_perfil() em cada RPC, RLS nas tabelas de config) — este arquivo só
// evita oferecer na UI uma ação que o backend recusaria.

// Configuração administrativa: custo/hora, teto de desconto, limites de
// anexo — só administrador_tecnico (rpc_definir_custo_hora /
// rpc_definir_teto_desconto / rpc_definir_anexos_config /
// rpc_definir_obrigatoriedade_fotos usa encarregado+administrador_tecnico,
// ver constante própria abaixo).
export const PODE_CONFIGURAR_CUSTO_HORA = [PERFIS.ADMINISTRADOR_TECNICO]
export const PODE_CONFIGURAR_TETO_DESCONTO = [PERFIS.ADMINISTRADOR_TECNICO]
export const PODE_CONFIGURAR_ANEXOS = [PERFIS.ADMINISTRADOR_TECNICO]
// Ver custo/hora vigente (financeiro-like: nunca executor) — leitura de custo_hora_config/desconto_config.
export const PODE_VER_CUSTO_HORA = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.DIRETORIA, PERFIS.ADMINISTRADOR_TECNICO]

// Centro de custo: cadastro simples — mesma autoridade de cadastros gerais.
export const PODE_GERIR_CENTRO_CUSTO = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]

// Prazo da OS — rpc_definir_previsao_conclusao.
export const PODE_DEFINIR_PRAZO_OS = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Desconto no orçamento (dentro do teto configurado) — rpc_aplicar_desconto_orcamento.
export const PODE_CONCEDER_DESCONTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Fotos da OS — rpc_registrar_foto_os. Executor participa (só na OS em que
// atua — checado no backend), mas NUNCA configura obrigatoriedade.
export const PODE_ANEXAR_FOTO_OS = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]
export const PODE_CONFIGURAR_OBRIGATORIEDADE_FOTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Centro de custo da OS interna — rpc_definir_centro_custo_os.
export const PODE_DEFINIR_CENTRO_CUSTO_OS = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Garantia de item de adicional — mesma autoridade de BR-024 (rpc_criar_os_garantia).
export const PODE_ABRIR_GARANTIA_ADICIONAL = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Remoção formal de executor — rpc_remover_executor_os. Nunca o próprio
// executor (encerrar a própria participação exige encarregado/admin).
export const PODE_REMOVER_EXECUTOR = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Cancelamento formal de item aprovado ainda não executado (orçamento ou
// adicional) — rpc_marcar_item_orcamento_execucao / _adicional_execucao
// com status='cancelado'. Executor aponta execução mas não cancela item
// aprovado (decisão comercial, não técnica).
export const PODE_CANCELAR_ITEM_APROVADO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]

// Termo de Ciência de Débito — rpc_registrar_termo_ciencia (suporte
// administrativo trata financeiro/documentos, sem alteração técnica).
export const PODE_REGISTRAR_TERMO_CIENCIA = [PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.ADMINISTRADOR_TECNICO]

// Relatórios (encerramento/garantia/histórico de veículo/PDF de orçamento)
// — funções de leitura (security invoker); qualquer perfil ativo pode
// chamar a RPC, mas o CONTEÚDO retornado já respeita a RLS de cada tabela
// agregada para quem chama (ex.: executor nunca recebe valor de cobrança,
// porque a policy de 'cobrancas' já bloqueia SELECT para executor).
export const PODE_VER_RELATORIOS = [PERFIS.EXECUTOR, PERFIS.ENCARREGADO, PERFIS.SUPORTE_ADMINISTRATIVO, PERFIS.DIRETORIA, PERFIS.ADMINISTRADOR_TECNICO]

// FEATURE-ORCAMENTO-EXCLUSAO-01 (BR-045/046/047) — exclusão lógica de
// rascunho e cancelamento formal pós-rascunho, mesma autoridade de
// PODE_GERIR_ORCAMENTO (quem já pode enviar/versionar/descontar também
// exclui/cancela) — rpc_excluir_orcamento_rascunho / rpc_cancelar_orcamento.
export const PODE_EXCLUIR_ORCAMENTO_RASCUNHO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
export const PODE_CANCELAR_ORCAMENTO = [PERFIS.ENCARREGADO, PERFIS.ADMINISTRADOR_TECNICO]
// Restauração de orçamento excluído — rpc_restaurar_orcamento_excluido. Mais
// restrito que a própria exclusão por decisão deliberada: reverter uma ação
// destrutiva já auditada exige autoridade máxima, não a mesma autoridade
// que a praticou.
export const PODE_RESTAURAR_ORCAMENTO = [PERFIS.ADMINISTRADOR_TECNICO]

export function temPerfil(perfilAtual, listaPermitida) {
  return !!perfilAtual && listaPermitida.includes(perfilAtual)
}
