// ETAPA UX-DASHBOARD-01 — mapa único de cor/rótulo/severidade por status,
// para o Dashboard (gráficos precisam de string de cor em JS, não var()).
// Os valores hex espelham os tokens --status-* em src/style.css — mudar um
// dos dois lados sem o outro quebra a consistência visual entre telas.
// Não substitui os mapas locais já existentes em OrdensServicoList.vue /
// OrcamentosList.vue / CobrancasList.vue (fora do escopo desta etapa).

export const STATUS_OS = {
  aberta: { label: 'Aberta', cor: '#8b5cf6', severidade: 'info' },
  em_diagnostico: { label: 'Em diagnóstico', cor: '#38bdf8', severidade: 'warn' },
  aguardando_aprovacao: { label: 'Aguard. aprovação', cor: '#facc15', severidade: 'warn' },
  em_execucao: { label: 'Em execução', cor: '#38bdf8', severidade: 'warn' },
  aguardando_teste: { label: 'Aguard. teste', cor: '#fb923c', severidade: 'warn' },
  concluida: { label: 'Concluída', cor: '#4ade80', severidade: 'success' },
  liberada: { label: 'Liberada', cor: '#16a34a', severidade: 'success' },
  reaberta_garantia: { label: 'Garantia', cor: '#a78bfa', severidade: 'danger' },
  cancelada: { label: 'Cancelada', cor: '#f87171', severidade: 'danger' },
}

export const ORDEM_STATUS_OS = Object.keys(STATUS_OS)

export const STATUS_ORCAMENTO = {
  rascunho: { label: 'Rascunho', cor: '#9ca3af', severidade: 'secondary' },
  enviado: { label: 'Enviado', cor: '#38bdf8', severidade: 'warn' },
  aprovado: { label: 'Aprovado', cor: '#4ade80', severidade: 'success' },
  parcialmente_aprovado: { label: 'Parcialmente aprovado', cor: '#a78bfa', severidade: 'warn' },
  rejeitado: { label: 'Rejeitado', cor: '#f87171', severidade: 'danger' },
  substituido: { label: 'Substituído', cor: '#9ca3af', severidade: 'contrast' },
}

export const STATUS_COBRANCA = {
  aberta: { label: 'Aberta', cor: '#38bdf8', severidade: 'info' },
  parcial: { label: 'Parcial', cor: '#facc15', severidade: 'warn' },
  quitada: { label: 'Quitada', cor: '#4ade80', severidade: 'success' },
  vencida: { label: 'Vencida', cor: '#f87171', severidade: 'danger' },
  cancelada: { label: 'Cancelada', cor: '#9ca3af', severidade: 'contrast' },
}

// ETAPA UX-SOLICITACOES-01 — mesmas severidades já usadas no mapa local de
// SolicitacoesList.vue (aberta:info, em_analise:warn, convertida_*:success,
// cancelada:danger); só centraliza e acrescenta rótulo em PT-BR.
export const STATUS_SOLICITACAO = {
  aberta: { label: 'Aberta', cor: '#8b5cf6', severidade: 'info' },
  em_analise: { label: 'Em análise', cor: '#facc15', severidade: 'warn' },
  convertida_orcamento: { label: 'Convertida em orçamento', cor: '#4ade80', severidade: 'success' },
  convertida_os: { label: 'Convertida em OS', cor: '#4ade80', severidade: 'success' },
  cancelada: { label: 'Cancelada', cor: '#f87171', severidade: 'danger' },
}
