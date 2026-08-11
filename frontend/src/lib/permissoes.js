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

export function temPerfil(perfilAtual, listaPermitida) {
  return !!perfilAtual && listaPermitida.includes(perfilAtual)
}
