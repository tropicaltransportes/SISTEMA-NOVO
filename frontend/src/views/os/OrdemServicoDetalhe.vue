<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import Button from 'primevue/button'
import Checkbox from 'primevue/checkbox'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import { STATUS_OS } from '../../constants/statusVisual.js'
import OsCabecalho from './components/OsCabecalho.vue'
import OsFaseAtual from './components/OsFaseAtual.vue'
import OsTrabalhoAtual from './components/OsTrabalhoAtual.vue'
import OsServicos from './components/OsServicos.vue'
import OsCardsApoio from './components/OsCardsApoio.vue'
import OsChecklistDialog from './components/OsChecklistDialog.vue'
import OsPecasDialog from './components/OsPecasDialog.vue'
import OsFotosDialog from './components/OsFotosDialog.vue'
import OsAdicionaisDialog from './components/OsAdicionaisDialog.vue'
import OsAtividadeRecente from './components/OsAtividadeRecente.vue'
import OsPendenciasConclusao from './components/OsPendenciasConclusao.vue'

// ======================================================================
// ETAPA OS-UX-02 — reestruturação em 5 blocos de progressive disclosure
// (era 6 abas de mesmo peso, ver OS_UX_02_REPORT.md). Nenhuma RPC, RBAC ou
// regra de negócio foi tocada aqui: mesmas 17 RPCs + 2 escritas diretas em
// tabela do arquivo original, só reorganizadas entre este orquestrador e
// os componentes de ./components/. Algumas funções que liam formulário de
// um ref local do arquivo original agora recebem esse formulário como
// parâmetro (payload), porque o formulário passou a viver no componente
// filho — a chamada RPC em si e seus parâmetros não mudaram.
// ======================================================================

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const osId = computed(() => route.params.id)
const os = ref(null)
const checklistItens = ref([])
const respostas = ref([])
const executores = ref([])
const movimentos = ref([])
const pecas = ref([])
const checklistTemplates = ref([])
const osOrigem = ref(null)
const osGarantias = ref([])
const carregando = ref(true)
const orcamentoItens = ref([])
const itensOsOrigemParaGarantia = ref([])
const garantiaItensVinculados = ref([])
const osAdicionais = ref([])
const osFotos = ref([])
const checklistTemplateAtual = ref(null)
const auditoriaEventos = ref([])

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

const podeTransicionar = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeApontar = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeResponderChecklist = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeBaixarPeca = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeGerarCobranca = computed(() => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeAbrirGarantia = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeIdentificarAdicional = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podePrecificarAdicional = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeDecidirAdicional = computed(() => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeCancelarAdicional = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeDefinirPrazo = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeRemoverExecutor = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeAnexarFoto = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeExcluirOS = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeCancelarOS = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeRestaurarOS = computed(() => auth.perfil === 'administrador_tecnico')

const NOVENTA_DIAS_MS = 90 * 24 * 60 * 60 * 1000
const prazoGarantiaAte = computed(() => {
  if (!os.value?.data_liberacao) return null
  return new Date(new Date(os.value.data_liberacao).getTime() + NOVENTA_DIAS_MS)
})
const dentroDoPrazoGarantia = computed(() => {
  if (!os.value || os.value.status !== 'liberada' || os.value.os_origem_id) return false
  return prazoGarantiaAte.value && Date.now() <= prazoGarantiaAte.value.getTime()
})

async function carregar() {
  carregando.value = true
  const [respOs, respExec, respMov, respPecas, respTemplates] = await Promise.all([
    supabase
      .from('ordens_servico')
      .select('id, tipo, status, data_abertura, data_liberacao, checklist_template_id, orcamento_id, os_origem_id, previsao_conclusao, previsao_definida_por, previsao_definida_em, custo_pecas, custo_mao_obra, custo_total, custo_hora_aplicado, horas_apontadas_total, custo_calculado_em, centro_custo_id, deleted_at, deleted_by, deleted_reason, cancelado_em, cancelado_por, cancelamento_motivo, veiculo:veiculos(id, placa, prefixo, modelo), cliente:clientes(id, nome, tipo), deleted_by_profile:profiles!ordens_servico_deleted_by_fkey(nome), cancelado_por_profile:profiles!ordens_servico_cancelado_por_fkey(nome)')
      .eq('id', osId.value)
      .single(),
    supabase.from('os_executores').select('id, usuario_id, etapa, inicio, fim, observacao, ativo, removido_por, removido_em, motivo_remocao, usuario:profiles!os_executores_usuario_id_fkey(nome)').eq('os_id', osId.value).order('inicio', { ascending: false }),
    supabase.from('estoque_movimentos').select('id, quantidade, custo_unitario, criado_em, orcamento_item_id, os_adicional_item_id, tipo, peca:pecas(sku, descricao)').eq('origem_tipo', 'os').eq('origem_id', osId.value).order('criado_em', { ascending: false }),
    supabase.from('pecas').select('id, sku, descricao, saldo_atual').is('deleted_at', null).order('descricao'),
    supabase.from('checklist_templates').select('id, nome').eq('ativo', true).order('nome'),
  ])

  if (respOs.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar OS', detail: respOs.error.message, life: 5000 })
    carregando.value = false
    return
  }
  os.value = respOs.data
  for (const [nome, resp] of [['executores', respExec], ['movimentações de estoque', respMov], ['peças', respPecas], ['templates de checklist', respTemplates]]) {
    if (resp.error) {
      toast.add({ severity: 'warn', summary: `Falha ao carregar ${nome}`, detail: resp.error.message, life: 6000 })
    }
  }
  executores.value = respExec.data ?? []
  movimentos.value = respMov.data ?? []
  pecas.value = respPecas.data ?? []
  checklistTemplates.value = respTemplates.data ?? []

  const { data: respFotos } = await supabase
    .from('os_fotos')
    .select('id, tipo, arquivo_path, enviado_por, enviado_em, observacao, enviado_por_profile:profiles(nome)')
    .eq('os_id', osId.value)
    .order('enviado_em', { ascending: false })
  osFotos.value = respFotos ?? []
  if (os.value.checklist_template_id) {
    const { data: respTplAtual } = await supabase
      .from('checklist_templates')
      .select('id, nome, foto_antes_obrigatoria, foto_depois_obrigatoria')
      .eq('id', os.value.checklist_template_id)
      .single()
    checklistTemplateAtual.value = respTplAtual ?? null
  } else {
    checklistTemplateAtual.value = null
  }

  const [respOsOrigem, respOsGarantias] = await Promise.all([
    os.value.os_origem_id
      ? supabase.from('ordens_servico').select('id, veiculo:veiculos(placa, prefixo), orcamento_id').eq('id', os.value.os_origem_id).single()
      : Promise.resolve({ data: null }),
    supabase.from('ordens_servico').select('id, status, data_abertura, veiculo:veiculos(placa, prefixo)').eq('os_origem_id', osId.value),
  ])
  osOrigem.value = respOsOrigem.data
  osGarantias.value = respOsGarantias.data ?? []

  if (os.value.orcamento_id) {
    const { data } = await supabase
      .from('orcamento_itens')
      .select('id, peca_id, descricao, quantidade, execucao_status, status_aprovacao, peca:pecas(sku, descricao)')
      .eq('orcamento_id', os.value.orcamento_id)
    orcamentoItens.value = data ?? []
  } else {
    orcamentoItens.value = []
  }

  if (os.value.os_origem_id) {
    const { data } = await supabase
      .from('os_garantia_itens')
      .select('orcamento_item_original_id, motivo, item:orcamento_itens(id, descricao, peca_id, quantidade, peca:pecas(sku, descricao))')
      .eq('os_garantia_id', osId.value)
    garantiaItensVinculados.value = data ?? []
  } else {
    garantiaItensVinculados.value = []
  }
  itensOsOrigemParaGarantia.value = orcamentoItens.value

  const { data: respAdicionais } = await supabase
    .from('os_adicionais')
    .select('id, numero, motivo, status, criado_em, criado_por, os_adicional_itens(id, peca_id, descricao, quantidade, valor_unitario, valor_total, justificativa, status_aprovacao, meio_aprovacao, autorizado_por_nome, autorizado_em, comprovante_path, observacao, execucao_status, peca:pecas(sku, descricao))')
    .eq('os_id', osId.value)
    .order('numero', { ascending: true })
  osAdicionais.value = respAdicionais ?? []

  if (os.value.checklist_template_id) {
    const [respItens, respResp] = await Promise.all([
      supabase.from('checklist_template_itens').select('id, descricao, obrigatorio').eq('template_id', os.value.checklist_template_id),
      supabase.from('os_checklist_respostas').select('id, template_item_id, ok').eq('os_id', osId.value),
    ])
    checklistItens.value = respItens.data ?? []
    respostas.value = respResp.data ?? []
  } else {
    checklistItens.value = []
    respostas.value = []
  }
  if (podeVerHistorico.value) {
    const { data: respAuditoria } = await supabase
      .from('auditoria_eventos')
      .select('id, valor_anterior, valor_novo, criado_em, usuario:profiles(nome)')
      .eq('entidade', 'ordens_servico')
      .eq('entidade_id', osId.value)
      .eq('acao', 'mudanca_status')
      .order('criado_em', { ascending: true })
    auditoriaEventos.value = respAuditoria ?? []
  } else {
    auditoriaEventos.value = []
  }
  carregando.value = false
}

function respostaDoItem(itemId) {
  return respostas.value.find((r) => r.template_item_id === itemId)
}

// ---------- Transições ----------
// ETAPA OS-FLOW-03 — BR-053: 2 retrocessos controlados, sempre com motivo,
// nunca na zona de ação principal (ficam no menu "⋮", item 10 do pedido).
// Continuam fora do mapa `transicoesDisponiveis` de propósito — aquele
// mapa alimenta a ação primária do cabeçalho, que só deve oferecer avanço.
const transicoesDisponiveis = computed(() => {
  const mapa = {
    aberta: [{ label: 'Iniciar Diagnóstico', next: 'em_diagnostico' }],
    em_diagnostico: [
      { label: 'Enviar p/ Aprovação (orçamento adicional)', next: 'aguardando_aprovacao' },
      { label: 'Iniciar Execução', next: 'em_execucao' },
    ],
    aguardando_aprovacao: [{ label: 'Iniciar Execução', next: 'em_execucao' }],
    em_execucao: [{ label: 'Enviar p/ Teste', next: 'aguardando_teste' }],
  }
  return mapa[os.value?.status] ?? []
})

const retrocessosDisponiveis = computed(() => {
  const mapa = {
    aguardando_teste: [{ label: 'Retornar para Execução', next: 'em_execucao' }],
    em_execucao: [{ label: 'Retornar para Diagnóstico', next: 'em_diagnostico' }],
  }
  return mapa[os.value?.status] ?? []
})

async function transicionar(next, motivo = null) {
  const { error } = await supabase.rpc('rpc_transicionar_os', { p_os_id: osId.value, p_novo_status: next, p_motivo: motivo })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao transicionar', detail: error.message, life: 6000 })
    return false
  }
  await carregar()
  return true
}

function confirmarTransicao(t) {
  if (!t.danger) return transicionar(t.next)
  confirm.require({
    message: `Confirmar: ${t.label}?`,
    header: 'Confirmar ação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Confirmar',
    rejectLabel: 'Voltar',
    accept: () => transicionar(t.next),
  })
}

// ---------- Retorno controlado de fase (BR-053) ----------
const dialogoRetornoFaseAberto = ref(false)
const retrocessoAlvo = ref(null)
const motivoRetornoFase = ref('')
function abrirRetornoFase(item) {
  retrocessoAlvo.value = item
  motivoRetornoFase.value = ''
  dialogoRetornoFaseAberto.value = true
}
async function confirmarRetornoFase() {
  if (!motivoRetornoFase.value || motivoRetornoFase.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const ok = await transicionar(retrocessoAlvo.value.next, motivoRetornoFase.value)
  if (ok) dialogoRetornoFaseAberto.value = false
}

async function concluir() {
  const { error } = await supabase.rpc('rpc_concluir_os', { p_os_id: osId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Não é possível concluir', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS concluída', life: 3000 })
  await carregar()
}

async function liberar() {
  const { error } = await supabase.rpc('rpc_liberar_os', { p_os_id: osId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Não é possível liberar', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS liberada', life: 3000 })
  await carregar()
}

// ---------- Prazo ----------
const dialogoPrazoAberto = ref(false)
const formPrazo = ref({ previsao_conclusao: null, motivo: '' })
function abrirPrazo() {
  formPrazo.value = { previsao_conclusao: os.value.previsao_conclusao ? new Date(os.value.previsao_conclusao) : null, motivo: '' }
  dialogoPrazoAberto.value = true
}
async function salvarPrazo() {
  if (!formPrazo.value.previsao_conclusao) {
    toast.add({ severity: 'warn', summary: 'Selecione a data/hora prevista', life: 4000 })
    return
  }
  if (os.value.previsao_conclusao && (!formPrazo.value.motivo || formPrazo.value.motivo.trim().length < 5)) {
    toast.add({ severity: 'warn', summary: 'Alterar um prazo já definido exige motivo (mín. 5 caracteres)', life: 5000 })
    return
  }
  const { error } = await supabase.rpc('rpc_definir_previsao_conclusao', {
    p_os_id: osId.value,
    p_previsao_conclusao: new Date(formPrazo.value.previsao_conclusao).toISOString(),
    p_motivo: formPrazo.value.motivo || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao definir prazo', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Prazo definido', life: 3000 })
  dialogoPrazoAberto.value = false
  await carregar()
}

// ---------- Fotos ----------
async function enviarFoto(payload) {
  const caminhoDestino = `${osId.value}/${payload.tipo}/${Date.now()}-${payload.arquivo.name}`
  const { error: erroUpload } = await supabase.storage.from('os-fotos').upload(caminhoDestino, payload.arquivo)
  if (erroUpload) {
    toast.add({ severity: 'error', summary: 'Erro ao enviar foto', detail: erroUpload.message, life: 6000 })
    return false
  }
  const { error } = await supabase.rpc('rpc_registrar_foto_os', {
    p_os_id: osId.value,
    p_tipo: payload.tipo,
    p_arquivo_path: caminhoDestino,
    p_observacao: payload.observacao || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Foto recusada', detail: error.message, life: 7000 })
    return false
  }
  toast.add({ severity: 'success', summary: 'Foto registrada', life: 3000 })
  await carregar()
  return true
}

// ---------- Garantia ----------
const dialogoGarantiaAberto = ref(false)
const itensGarantiaSelecionados = ref([])

function confirmarAbrirGarantia() {
  if (orcamentoItens.value.length === 0) {
    return abrirGarantiaComItens([])
  }
  itensGarantiaSelecionados.value = []
  dialogoGarantiaAberto.value = true
}

async function abrirGarantiaComItens(itensIds) {
  const { data, error } = await supabase.rpc('rpc_criar_os_garantia', {
    p_os_origem_id: osId.value,
    p_itens_originais: itensIds.length ? itensIds : null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Não é possível abrir garantia', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS de garantia criada', life: 3000 })
  dialogoGarantiaAberto.value = false
  router.push('/os/' + data)
}

// ---------- Checklist ----------
async function definirChecklist(templateId) {
  const { error } = await supabase.rpc('rpc_definir_checklist_os', { p_os_id: osId.value, p_checklist_template_id: templateId })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao definir checklist', detail: error.message, life: 6000 })
    return
  }
  await carregar()
}

async function alternarResposta(item, valor) {
  const { error } = await supabase.from('os_checklist_respostas').upsert(
    { os_id: osId.value, template_item_id: item.id, ok: valor, respondido_por: auth.profile.id, respondido_em: new Date().toISOString() },
    { onConflict: 'os_id,template_item_id' }
  )
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar resposta', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

const checklistProgresso = computed(() => ({
  concluidos: checklistItens.value.filter((i) => respostaDoItem(i.id)?.ok).length,
  total: checklistItens.value.length,
}))
const checklistObrigatoriosPendentes = computed(() =>
  checklistItens.value.filter((i) => i.obrigatorio && !respostaDoItem(i.id)?.ok).length
)

// ---------- Apontamento ----------
async function iniciarApontamento(payload) {
  const { error } = await supabase.from('os_executores').insert({
    os_id: osId.value,
    usuario_id: auth.profile.id,
    etapa: payload.etapa,
    inicio: new Date().toISOString(),
    observacao: payload.observacao || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao iniciar apontamento', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

const osEncerrada = computed(() => ['concluida', 'liberada', 'cancelada'].includes(os.value?.status) || !!os.value?.deleted_at)

// ETAPA OS-FLOW-03 — BR-052: reflexo visual só (a RPC é quem decide de
// verdade) do bloqueio de transição/conclusão com apontamento aberto.
const apontamentoAberto = computed(() => executores.value.some((e) => e.ativo !== false && !e.fim))

// ---------- Excluir / Cancelar / Restaurar OS ----------
const osEhVirgem = computed(() => {
  if (!os.value || os.value.status !== 'aberta' || os.value.deleted_at) return false
  return (
    executores.value.length === 0 &&
    movimentos.value.length === 0 &&
    osFotos.value.length === 0 &&
    osAdicionais.value.length === 0 &&
    respostas.value.length === 0
  )
})
const osCancelavel = computed(() => {
  if (!os.value || os.value.deleted_at) return false
  return ['aberta', 'em_diagnostico', 'aguardando_aprovacao', 'em_execucao', 'aguardando_teste', 'concluida'].includes(os.value.status)
})

const itensMenuAcoesOS = computed(() => {
  if (!os.value) return []
  const lista = []
  if (osEhVirgem.value && podeExcluirOS.value) {
    lista.push({ label: 'Excluir OS', icon: 'pi pi-trash', class: 'item-menu-destrutivo', command: () => abrirExcluirOS() })
  } else if (osCancelavel.value && podeCancelarOS.value) {
    lista.push({ label: 'Cancelar OS', icon: 'pi pi-ban', class: 'item-menu-destrutivo', command: () => abrirCancelarOS() })
  }
  if (os.value.deleted_at && podeRestaurarOS.value) {
    lista.push({ label: 'Restaurar OS', icon: 'pi pi-refresh', command: () => confirmarRestaurarOS() })
  }
  return lista
})

const dialogoExclusaoOSAberto = ref(false)
const salvandoExclusaoOS = ref(false)
const formExclusaoOS = ref({ motivo: '' })
function abrirExcluirOS() {
  formExclusaoOS.value = { motivo: '' }
  dialogoExclusaoOSAberto.value = true
}
async function confirmarExcluirOS() {
  if (!formExclusaoOS.value.motivo || formExclusaoOS.value.motivo.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Motivo da exclusão é obrigatório (mín. 5 caracteres)', life: 5000 })
    return
  }
  salvandoExclusaoOS.value = true
  const { error } = await supabase.rpc('rpc_excluir_os_rascunho', { p_os_id: osId.value, p_motivo: formExclusaoOS.value.motivo })
  salvandoExclusaoOS.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao excluir OS', detail: error.message, life: 8000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS excluída', life: 3000 })
  dialogoExclusaoOSAberto.value = false
  router.push('/os')
}

const dialogoCancelamentoOSAberto = ref(false)
const salvandoCancelamentoOS = ref(false)
const formCancelamentoOS = ref({ motivo: '' })
function abrirCancelarOS() {
  formCancelamentoOS.value = { motivo: '' }
  dialogoCancelamentoOSAberto.value = true
}
async function confirmarCancelarOS() {
  if (!formCancelamentoOS.value.motivo || formCancelamentoOS.value.motivo.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Motivo do cancelamento é obrigatório (mín. 5 caracteres)', life: 5000 })
    return
  }
  salvandoCancelamentoOS.value = true
  const { error } = await supabase.rpc('rpc_cancelar_os', { p_os_id: osId.value, p_motivo: formCancelamentoOS.value.motivo })
  salvandoCancelamentoOS.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao cancelar OS', detail: error.message, life: 8000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS cancelada', life: 3000 })
  dialogoCancelamentoOSAberto.value = false
  await carregar()
}

function confirmarRestaurarOS() {
  confirm.require({
    message: 'Restaurar esta OS excluída? Ela volta a aparecer nas listagens normais.',
    header: 'Confirmar restauração',
    icon: 'pi pi-refresh',
    acceptLabel: 'Restaurar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_restaurar_os_excluida', { p_os_id: osId.value })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao restaurar', detail: error.message, life: 6000 })
        return
      }
      toast.add({ severity: 'success', summary: 'OS restaurada', life: 3000 })
      await carregar()
    },
  })
}

const resumoConsequenciasCancelamento = computed(() => {
  if (!os.value) return []
  const linhas = []
  const apontamentosAbertos = executores.value.filter((e) => !e.fim).length
  if (apontamentosAbertos > 0) linhas.push(`${apontamentosAbertos} apontamento(s) em aberto serão encerrados`)
  const pecasBaixadas = movimentos.value.filter((m) => m.tipo === 'saida').length
  if (pecasBaixadas > 0) linhas.push(`${pecasBaixadas} peça(s) baixada(s) serão estornadas ao estoque`)
  const adicionaisPendentes = osAdicionais.value.filter((a) => a.status === 'aguardando_aprovacao').length
  if (adicionaisPendentes > 0) linhas.push(`${adicionaisPendentes} adicional(is) aguardando aprovação serão encerrados formalmente`)
  return linhas
})

async function encerrarApontamento(exec) {
  const { error } = await supabase.from('os_executores').update({ fim: new Date().toISOString() }).eq('id', exec.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao encerrar apontamento', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

// ---------- Remoção formal de executor ----------
const dialogoRemoverExecutorAberto = ref(false)
const executorParaRemover = ref(null)
const motivoRemocaoExecutor = ref('')
function abrirRemoverExecutor(exec) {
  executorParaRemover.value = exec
  motivoRemocaoExecutor.value = ''
  dialogoRemoverExecutorAberto.value = true
}
async function confirmarRemoverExecutor() {
  if (!motivoRemocaoExecutor.value || motivoRemocaoExecutor.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_remover_executor_os', {
    p_os_executor_id: executorParaRemover.value.id,
    p_motivo: motivoRemocaoExecutor.value,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao remover executor', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Participação encerrada (histórico preservado)', life: 3000 })
  dialogoRemoverExecutorAberto.value = false
  await carregar()
}

// ---------- Baixa de peça ----------
const podeMovimentarEstoque = computed(() => ['em_diagnostico', 'em_execucao'].includes(os.value?.status))
const podeBaixarLivre = computed(() => !os.value?.orcamento_id && !os.value?.os_origem_id)

function quantidadeJaBaixada(itemId, origem) {
  const campo = origem === 'adicional' ? 'os_adicional_item_id' : 'orcamento_item_id'
  return movimentos.value
    .filter((m) => m[campo] === itemId)
    .reduce((soma, m) => soma + (m.tipo === 'estorno_saida' ? -Number(m.quantidade) : Number(m.quantidade)), 0)
}

const itensParaBaixa = computed(() => {
  const doOrcamento = os.value?.orcamento_id
    ? orcamentoItens.value
        .filter((i) => i.peca_id && i.status_aprovacao === 'aprovado')
        .map((i) => ({ chave: `orc:${i.id}`, origem: 'orcamento', id: i.id, peca_id: i.peca_id, descricao: i.descricao, quantidade: i.quantidade, peca: i.peca, restante: i.quantidade - quantidadeJaBaixada(i.id, 'orcamento') }))
    : []
  const daGarantia = os.value?.os_origem_id
    ? garantiaItensVinculados.value
        .filter((v) => v.item?.peca_id)
        .map((v) => ({ chave: `orc:${v.item.id}`, origem: 'orcamento', id: v.item.id, peca_id: v.item.peca_id, descricao: v.item.descricao, quantidade: v.item.quantidade, peca: v.item.peca, restante: v.item.quantidade - quantidadeJaBaixada(v.item.id, 'orcamento') }))
    : []
  const doAdicional = osAdicionais.value.flatMap((a) =>
    (a.os_adicional_itens ?? [])
      .filter((i) => i.peca_id && i.status_aprovacao === 'aprovado')
      .map((i) => ({
        chave: `adc:${i.id}`,
        origem: 'adicional',
        id: i.id,
        peca_id: i.peca_id,
        descricao: `[AD-${String(a.numero).padStart(3, '0')}] ${i.descricao}`,
        quantidade: i.quantidade,
        peca: i.peca,
        restante: i.quantidade - quantidadeJaBaixada(i.id, 'adicional'),
      }))
  )
  return [...doOrcamento, ...daGarantia, ...doAdicional]
})

async function baixarPeca(payload) {
  const itemSelecionado = itensParaBaixa.value.find((i) => i.chave === payload.chave)
  if (!podeBaixarLivre.value && !itemSelecionado) {
    toast.add({ severity: 'warn', summary: 'Selecione o item do orçamento/adicional/garantia', life: 4000 })
    return
  }
  if (!payload.peca_id || !payload.quantidade) {
    toast.add({ severity: 'warn', summary: 'Selecione a peça e a quantidade', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_baixar_peca_os', {
    p_os_id: osId.value,
    p_peca_id: payload.peca_id,
    p_quantidade: payload.quantidade,
    p_orcamento_item_id: itemSelecionado?.origem === 'orcamento' ? itemSelecionado.id : null,
    p_os_adicional_item_id: itemSelecionado?.origem === 'adicional' ? itemSelecionado.id : null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao baixar peça', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Peça baixada do estoque', life: 3000 })
  await carregar()
}

// ---------- Itens de mão de obra ----------
const itensMaoDeObra = computed(() => orcamentoItens.value.filter((i) => !i.peca_id && i.status_aprovacao === 'aprovado'))
const podeMarcarExecucao = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const dialogoCancelarItemAberto = ref(false)
const itemParaCancelar = ref(null)
const motivoCancelamento = ref('')

async function marcarItemExecutado(item) {
  const { error } = await supabase.rpc('rpc_marcar_item_orcamento_execucao', {
    p_orcamento_item_id: item.id,
    p_status: 'executado',
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao marcar item', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Item marcado como executado', life: 3000 })
  await carregar()
}

const itemParaCancelarTipo = ref('orcamento')

function abrirCancelarItem(item, tipo = 'orcamento') {
  itemParaCancelar.value = item
  itemParaCancelarTipo.value = tipo
  motivoCancelamento.value = ''
  dialogoCancelarItemAberto.value = true
}

async function confirmarCancelarItem() {
  if (!motivoCancelamento.value || motivoCancelamento.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const rpcNome = itemParaCancelarTipo.value === 'adicional' ? 'rpc_marcar_item_os_adicional_execucao' : 'rpc_marcar_item_orcamento_execucao'
  const params = itemParaCancelarTipo.value === 'adicional'
    ? { p_item_id: itemParaCancelar.value.id, p_status: 'cancelado', p_motivo: motivoCancelamento.value }
    : { p_orcamento_item_id: itemParaCancelar.value.id, p_status: 'cancelado', p_motivo: motivoCancelamento.value }
  const { error } = await supabase.rpc(rpcNome, params)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao cancelar item', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Item dispensado (auditado)', life: 3000 })
  dialogoCancelarItemAberto.value = false
  await carregar()
}

// ---------- Adicionais ----------
async function criarAdicional(payload) {
  const { error } = await supabase.rpc('rpc_criar_os_adicional', {
    p_os_id: osId.value,
    p_motivo: payload.motivo,
    p_idempotency_key: payload.idempotency_key,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao identificar adicional', detail: error.message, life: 6000 })
    return false
  }
  toast.add({ severity: 'success', summary: 'Necessidade registrada — aguardando precificação', life: 3000 })
  await carregar()
  return true
}

async function incluirItemAdicional(payload) {
  const { error } = await supabase.rpc('rpc_incluir_item_os_adicional', {
    p_adicional_id: payload.adicional_id,
    p_peca_id: payload.peca_id || null,
    p_descricao: payload.descricao,
    p_quantidade: payload.quantidade,
    p_valor_unitario: payload.valor_unitario,
    p_justificativa: payload.justificativa || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao incluir item', detail: error.message, life: 7000 })
    return false
  }
  toast.add({ severity: 'success', summary: 'Item incluído no adicional', life: 3000 })
  await carregar()
  return true
}

async function decidirItemAdicional(payload) {
  let comprovantePath = null
  if (payload.meio_aprovacao === 'email') {
    const caminhoDestino = `${osId.value}/adicional-item-${payload.item_id}-${Date.now()}-${payload.arquivo.name}`
    const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, payload.arquivo)
    if (erroUpload) {
      toast.add({ severity: 'error', summary: 'Erro ao enviar comprovante', detail: erroUpload.message, life: 6000 })
      return false
    }
    comprovantePath = caminhoDestino
  }
  const { error } = await supabase.rpc('rpc_decidir_item_os_adicional', {
    p_item_id: payload.item_id,
    p_decisao: payload.decisao,
    p_meio_aprovacao: payload.meio_aprovacao,
    p_autorizado_por_nome: payload.autorizado_por_nome,
    p_comprovante_path: comprovantePath,
    p_observacao: payload.observacao || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar decisão', detail: error.message, life: 7000 })
    return false
  }
  toast.add({ severity: 'success', summary: `Item ${payload.decisao}`, life: 3000 })
  await carregar()
  return true
}

async function marcarItemAdicionalExecutado(item) {
  const { error } = await supabase.rpc('rpc_marcar_item_os_adicional_execucao', { p_item_id: item.id, p_status: 'executado' })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao marcar item', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Item marcado como executado', life: 3000 })
  await carregar()
}

async function cancelarAdicional(payload) {
  const { error } = await supabase.rpc('rpc_cancelar_os_adicional', {
    p_adicional_id: payload.adicional_id,
    p_motivo: payload.motivo,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao cancelar adicional', detail: error.message, life: 6000 })
    return false
  }
  toast.add({ severity: 'success', summary: 'Adicional cancelado (auditado)', life: 3000 })
  await carregar()
  return true
}

function valorAdicional(adicional, filtro) {
  return (adicional.os_adicional_itens ?? [])
    .filter((i) => (filtro ? i.status_aprovacao === filtro : true))
    .reduce((s, i) => s + Number(i.valor_total), 0)
}

const adicionaisAguardandoDecisao = computed(() => osAdicionais.value.filter((a) => a.status === 'aguardando_aprovacao'))

// ---------- Fase / histórico / dialogs de apoio ----------
const podeVerHistorico = computed(() => auth.perfil !== 'executor')

const ETAPAS_OS = [
  { status: 'aberta', label: 'Aberta', icone: 'pi pi-file' },
  { status: 'em_diagnostico', label: 'Diagnóstico', icone: 'pi pi-search' },
  { status: 'em_execucao', label: 'Execução', icone: 'pi pi-wrench' },
  { status: 'aguardando_teste', label: 'Teste', icone: 'pi pi-verified' },
  { status: 'concluida', label: 'Concluída', icone: 'pi pi-check-circle' },
  { status: 'liberada', label: 'Liberada', icone: 'pi pi-flag-fill' },
]
const indiceEtapaAtual = computed(() => {
  if (os.value?.status === 'aguardando_aprovacao') return 1
  return ETAPAS_OS.findIndex((e) => e.status === os.value?.status)
})
const mostrarBarraEtapas = computed(() => indiceEtapaAtual.value !== -1)
const emAguardandoAprovacao = computed(() => os.value?.status === 'aguardando_aprovacao')

const transicoesNaoDanger = computed(() => transicoesDisponiveis.value.filter((t) => !t.danger))

const resumoOS = computed(() => ({
  execucoesAtivas: executores.value.filter((e) => e.ativo !== false && !e.fim).length,
  totalExecucoes: executores.value.length,
  totalPecasQtd: movimentos.value.length,
  totalPecasValor: movimentos.value.reduce((s, m) => s + Number(m.quantidade) * Number(m.custo_unitario ?? 0), 0),
  totalFotos: osFotos.value.length,
  adicionaisAbertos: osAdicionais.value.filter((a) => a.status === 'aguardando_aprovacao').length,
  adicionaisTotal: osAdicionais.value.length,
}))

// ETAPA OS-FLOW-03 (itens 15/23 do pedido) — "aprovado" != "utilizado":
// itensParaBaixa já carrega quantidade aprovada e `restante` por item
// (calculado do ledger de estoque_movimentos), só falta contar quantos
// itens ainda têm pendência. Para Adicionais, contagens por ITEM (não por
// cabeçalho de adicional) porque um único adicional pode ter itens em
// estados diferentes.
const pecasAguardandoUtilizacao = computed(() => itensParaBaixa.value.filter((i) => i.restante > 0).length)

const todosItensAdicionais = computed(() => osAdicionais.value.flatMap((a) => a.os_adicional_itens ?? []))
const resumoAdicionais = computed(() => ({
  identificados: osAdicionais.value.length,
  aguardandoDecisao: todosItensAdicionais.value.filter((i) => i.status_aprovacao === 'pendente').length,
  aprovados: todosItensAdicionais.value.filter((i) => i.status_aprovacao === 'aprovado').length,
  executados: todosItensAdicionais.value.filter((i) => i.status_aprovacao === 'aprovado' && i.execucao_status === 'executado').length,
}))

function rotuloStatus(s) {
  return STATUS_OS[s]?.label ?? s ?? '—'
}
const eventosHistorico = computed(() => {
  if (!os.value) return []
  const eventos = []
  if (os.value.data_abertura) {
    eventos.push({ data: os.value.data_abertura, titulo: 'OS aberta', detalhe: null, icone: 'pi pi-file' })
  }
  for (const ev of auditoriaEventos.value) {
    eventos.push({
      data: ev.criado_em,
      titulo: `Status alterado: ${rotuloStatus(ev.valor_anterior?.status)} → ${rotuloStatus(ev.valor_novo?.status)}`,
      detalhe: ev.usuario?.nome ? `por ${ev.usuario.nome}` : null,
      icone: 'pi pi-sync',
    })
  }
  for (const e of executores.value) {
    if (e.inicio) eventos.push({ data: e.inicio, titulo: `Apontamento iniciado (${e.etapa})`, detalhe: e.usuario?.nome ? `por ${e.usuario.nome}` : null, icone: 'pi pi-play' })
    if (e.fim) eventos.push({ data: e.fim, titulo: `Apontamento encerrado (${e.etapa})`, detalhe: e.usuario?.nome ? `por ${e.usuario.nome}` : null, icone: 'pi pi-stop' })
    if (e.ativo === false && e.removido_em) eventos.push({ data: e.removido_em, titulo: 'Participação de executor encerrada', detalhe: e.motivo_remocao, icone: 'pi pi-user-minus' })
  }
  for (const f of osFotos.value) {
    eventos.push({ data: f.enviado_em, titulo: `Foto (${f.tipo}) enviada`, detalhe: f.enviado_por_profile?.nome ? `por ${f.enviado_por_profile.nome}` : null, icone: 'pi pi-image' })
  }
  for (const a of osAdicionais.value) {
    eventos.push({ data: a.criado_em, titulo: `Adicional AD-${String(a.numero).padStart(3, '0')} identificado`, detalhe: a.motivo, icone: 'pi pi-plus-circle' })
  }
  for (const g of osGarantias.value) {
    eventos.push({ data: g.data_abertura, titulo: `Garantia aberta a partir desta OS: ${g.veiculo?.placa ?? ''}`, detalhe: rotuloStatus(g.status), icone: 'pi pi-shield' })
  }
  if (os.value.previsao_definida_em) {
    eventos.push({ data: os.value.previsao_definida_em, titulo: 'Previsão de conclusão definida/alterada', detalhe: null, icone: 'pi pi-calendar' })
  }
  return eventos.filter((e) => e.data).sort((a, b) => new Date(b.data) - new Date(a.data))
})

const dataConclusaoOS = computed(() => auditoriaEventos.value.find((e) => e.valor_novo?.status === 'concluida')?.criado_em ?? null)
const executoresUnicos = computed(() => [...new Set(executores.value.map((e) => e.usuario?.nome).filter(Boolean))])

// ---------- Dialogs de apoio (Checklist/Peças/Fotos/Adicionais) ----------
const dialogChecklistAberto = ref(false)
const dialogPecasAberto = ref(false)
const dialogFotosAberto = ref(false)
const dialogAdicionaisAberto = ref(false)

watch(osId, carregar, { immediate: true })
</script>

<template>
  <div v-if="carregando" class="estado-carregando">Carregando...</div>
  <div v-else-if="os" class="os-detalhe">

    <OsCabecalho
      :os="os"
      :os-id="osId"
      :pode-definir-prazo="podeDefinirPrazo"
      :os-encerrada="osEncerrada"
      :pode-gerar-cobranca="podeGerarCobranca"
      :pode-abrir-garantia="podeAbrirGarantia"
      :dentro-do-prazo-garantia="dentroDoPrazoGarantia"
      :transicoes-nao-danger="transicoesNaoDanger"
      :itens-menu-acoes="itensMenuAcoesOS"
      :retrocessos-disponiveis="retrocessosDisponiveis"
      :apontamento-aberto="apontamentoAberto"
      :abrir-prazo="abrirPrazo"
      :confirmar-transicao="confirmarTransicao"
      :concluir="concluir"
      :liberar="liberar"
      :confirmar-abrir-garantia="confirmarAbrirGarantia"
      :abrir-retorno-fase="abrirRetornoFase"
    />

    <OsFaseAtual
      :os="os"
      :etapas="ETAPAS_OS"
      :indice-etapa-atual="indiceEtapaAtual"
      :mostrar-barra-etapas="mostrarBarraEtapas"
      :em-aguardando-aprovacao="emAguardandoAprovacao"
    />

    <p v-if="osOrigem || osGarantias.length > 0 || dentroDoPrazoGarantia" class="hint linha-info-apoio">
      <template v-if="osOrigem">Esta OS é garantia da <router-link :to="'/os/' + osOrigem.id">OS {{ osOrigem.veiculo?.placa }}</router-link> — sem cobrança ao cliente. </template>
      <template v-if="osGarantias.length > 0">Garantia(s) aberta(s) a partir desta OS: <router-link v-for="g in osGarantias" :key="g.id" :to="'/os/' + g.id" style="margin-right: 0.5rem">{{ g.veiculo?.placa }} ({{ rotuloStatus(g.status) }})</router-link></template>
      <template v-if="dentroDoPrazoGarantia">Garantia até {{ prazoGarantiaAte.toLocaleDateString('pt-BR') }}.</template>
    </p>
    <p v-if="os.tipo === 'interna' && os.custo_calculado_em" class="hint linha-info-apoio">
      Custo interno: peças {{ formatarMoeda(os.custo_pecas) }} + mão de obra {{ formatarMoeda(os.custo_mao_obra) }} = <strong>{{ formatarMoeda(os.custo_total) }}</strong> — sem cobrança (cliente interno).
    </p>

    <div v-if="adicionaisAguardandoDecisao.length > 0 && podeDecidirAdicional" class="alerta-adicional" @click="dialogAdicionaisAberto = true">
      <i class="pi pi-exclamation-triangle"></i>
      <div>
        <strong>{{ adicionaisAguardandoDecisao.length }} adicional(is) aguardando decisão</strong>
        <span class="hint"> — AD-{{ String(adicionaisAguardandoDecisao[0].numero).padStart(3, '0') }}: {{ adicionaisAguardandoDecisao[0].motivo }}</span>
      </div>
      <Button label="Ver pendência" size="small" text />
    </div>

    <OsTrabalhoAtual
      v-if="!osEncerrada"
      :os="os"
      :executores="executores"
      :meu-id="auth.profile?.id"
      :pode-apontar="podeApontar"
      :pode-remover-executor="podeRemoverExecutor"
      :os-encerrada="osEncerrada"
      :iniciar-apontamento="iniciarApontamento"
      :encerrar-apontamento="encerrarApontamento"
      :abrir-remover-executor="abrirRemoverExecutor"
    />

    <OsPendenciasConclusao
      v-if="os.status === 'aguardando_teste'"
      :checklist-itens="checklistItens"
      :respostas="respostas"
      :itens-mao-de-obra="itensMaoDeObra"
      :os-adicionais="osAdicionais"
      :os-fotos="osFotos"
      :checklist-template-atual="checklistTemplateAtual"
      :executores="executores"
      :itens-para-baixa="itensParaBaixa"
      :pode-transicionar="podeTransicionar"
      :concluir="concluir"
    />

    <div v-if="os.status === 'concluida'" class="card">
      <h3>Serviço Concluído</h3>
      <p v-if="dataConclusaoOS">Concluído em {{ new Date(dataConclusaoOS).toLocaleString('pt-BR') }}.</p>
      <p v-if="executoresUnicos.length">Executores: {{ executoresUnicos.join(', ') }}</p>
      <p class="hint">Próxima etapa: liberação{{ os.tipo === 'externa' ? ' e cobrança' : '' }}.</p>
      <!-- ETAPA DOC-OS-FINAL-01 — item 55: documento comercial disponível
           assim que a OS conclui, sem depender de já existir cobrança. -->
      <div class="acoes-documento-final">
        <Button label="Visualizar OS" icon="pi pi-file-pdf" size="small" outlined @click="router.push('/os/' + osId + '/documento')" />
      </div>
    </div>

    <OsServicos
      :itens-mao-de-obra="itensMaoDeObra"
      :os-adicionais="osAdicionais"
      :pode-marcar-execucao="podeMarcarExecucao"
      :os-encerrada="osEncerrada"
      :formatar-moeda="formatarMoeda"
      :marcar-item-executado="marcarItemExecutado"
      :marcar-item-adicional-executado="marcarItemAdicionalExecutado"
      :abrir-cancelar-item="abrirCancelarItem"
    />

    <OsCardsApoio
      :checklist-progresso="checklistProgresso"
      :checklist-obrigatorios-pendentes="checklistObrigatoriosPendentes"
      :pecas-count="resumoOS.totalPecasQtd"
      :pecas-valor="resumoOS.totalPecasQtd ? formatarMoeda(resumoOS.totalPecasValor) : ''"
      :pecas-aguardando-utilizacao="pecasAguardandoUtilizacao"
      :fotos-count="resumoOS.totalFotos"
      :adicionais-identificados="resumoAdicionais.identificados"
      :adicionais-aprovados="resumoAdicionais.aprovados"
      :adicionais-executados="resumoAdicionais.executados"
      :adicionais-aguardando-decisao="resumoAdicionais.aguardandoDecisao"
      @abrir-checklist="dialogChecklistAberto = true"
      @abrir-pecas="dialogPecasAberto = true"
      @abrir-fotos="dialogFotosAberto = true"
      @abrir-adicionais="dialogAdicionaisAberto = true"
    />

    <OsAtividadeRecente :eventos="eventosHistorico" :pode-ver-historico="podeVerHistorico" />

    <!-- ===== Dialogs de apoio (checklist/peças/fotos/adicionais) ===== -->
    <OsChecklistDialog
      v-model:visible="dialogChecklistAberto"
      :checklist-template-id="os.checklist_template_id"
      :checklist-itens="checklistItens"
      :checklist-templates="checklistTemplates"
      :pode-responder-checklist="podeResponderChecklist"
      :pode-transicionar="podeTransicionar"
      :resposta-do-item="respostaDoItem"
      :definir-checklist="definirChecklist"
      :alternar-resposta="alternarResposta"
    />
    <OsPecasDialog
      v-model:visible="dialogPecasAberto"
      :movimentos="movimentos"
      :pecas="pecas"
      :itens-para-baixa="itensParaBaixa"
      :pode-baixar-peca="podeBaixarPeca"
      :pode-movimentar-estoque="podeMovimentarEstoque"
      :pode-baixar-livre="podeBaixarLivre"
      :baixar-peca="baixarPeca"
    />
    <OsFotosDialog
      v-model:visible="dialogFotosAberto"
      :os-fotos="osFotos"
      :checklist-template-atual="checklistTemplateAtual"
      :pode-anexar-foto="podeAnexarFoto"
      :os-encerrada="osEncerrada"
      :enviar-foto="enviarFoto"
    />
    <OsAdicionaisDialog
      v-model:visible="dialogAdicionaisAberto"
      :os-adicionais="osAdicionais"
      :pecas="pecas"
      :os-encerrada="osEncerrada"
      :pode-identificar-adicional="podeIdentificarAdicional"
      :pode-precificar-adicional="podePrecificarAdicional"
      :pode-decidir-adicional="podeDecidirAdicional"
      :pode-cancelar-adicional="podeCancelarAdicional"
      :pode-marcar-execucao="podeMarcarExecucao"
      :formatar-moeda="formatarMoeda"
      :valor-adicional="valorAdicional"
      :criar-adicional="criarAdicional"
      :incluir-item-adicional="incluirItemAdicional"
      :decidir-item-adicional="decidirItemAdicional"
      :marcar-item-adicional-executado="marcarItemAdicionalExecutado"
      :cancelar-adicional="cancelarAdicional"
      :abrir-cancelar-item="abrirCancelarItem"
    />

    <!-- ===== Dialogs que permanecem no orquestrador (pequenos, já sob demanda) ===== -->
    <Dialog v-model:visible="dialogoGarantiaAberto" modal header="Abrir Garantia — vincular itens originais" style="width: 480px">
      <p class="hint">Selecione quais itens desta OS são objeto do retorno em garantia. Só serviço/peça vinculado a um destes itens poderá ser lançado na OS de garantia.</p>
      <div v-for="item in itensOsOrigemParaGarantia" :key="item.id" class="checklist" style="margin-bottom:0.25rem">
        <Checkbox
          :modelValue="itensGarantiaSelecionados.includes(item.id)"
          binary
          @update:modelValue="(v) => { itensGarantiaSelecionados = v ? [...itensGarantiaSelecionados, item.id] : itensGarantiaSelecionados.filter((i) => i !== item.id) }"
        />
        <span style="margin-left:0.4rem">{{ item.descricao }}<span v-if="item.peca"> — {{ item.peca.descricao }}</span></span>
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoGarantiaAberto = false" />
        <Button label="Abrir Garantia" :disabled="itensGarantiaSelecionados.length === 0" @click="abrirGarantiaComItens(itensGarantiaSelecionados)" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoPrazoAberto" modal header="Definir Prazo (Previsão de Conclusão)" style="width: 420px">
      <div class="form-campo">
        <label>Data/hora prevista</label>
        <input type="datetime-local" v-model="formPrazo.previsao_conclusao" style="padding:0.4rem" />
      </div>
      <div class="form-campo" v-if="os.previsao_conclusao">
        <label>Motivo da alteração (obrigatório — já existia um prazo)</label>
        <Textarea v-model="formPrazo.motivo" rows="2" autoResize placeholder="Mínimo 5 caracteres" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoPrazoAberto = false" />
        <Button label="Salvar" @click="salvarPrazo" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoRetornoFaseAberto" modal :header="retrocessoAlvo?.label ?? 'Retornar fase'" style="width: 440px">
      <p class="hint">Isto muda a fase da OS de volta — fica registrado na trilha de auditoria com motivo, usuário e data/hora. Nenhum apontamento antigo é reaberto; o próximo trabalho gera um apontamento novo.</p>
      <div class="form-campo">
        <label>Motivo (obrigatório)</label>
        <Textarea v-model="motivoRetornoFase" rows="3" autoResize placeholder="Ex.: Vazamento identificado durante teste final. (mínimo 5 caracteres)" style="width:100%" />
      </div>
      <template #footer>
        <Button label="Voltar" text @click="dialogoRetornoFaseAberto = false" />
        <Button :label="retrocessoAlvo?.label ?? 'Confirmar'" @click="confirmarRetornoFase" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoRemoverExecutorAberto" modal header="Encerrar Participação do Executor" style="width: 420px">
      <p class="hint">Isto encerra a participação futura do executor nesta OS. O histórico de apontamento já registrado NUNCA é apagado.</p>
      <Textarea v-model="motivoRemocaoExecutor" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoRemoverExecutorAberto = false" />
        <Button label="Confirmar" severity="danger" @click="confirmarRemoverExecutor" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoCancelarItemAberto" modal header="Dispensar item aprovado" style="width: 420px">
      <p class="hint">Cancelar um item aprovado exige motivo — fica registrado na trilha de auditoria.</p>
      <Textarea v-model="motivoCancelamento" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelarItemAberto = false" />
        <Button label="Confirmar dispensa" severity="danger" @click="confirmarCancelarItem" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoExclusaoOSAberto" modal header="Excluir Ordem de Serviço?" style="width: 460px">
      <p class="texto-explicativo">
        Esta OS ainda não possui atividade operacional e será removida das listagens normais. O registro permanecerá preservado para auditoria.
      </p>
      <p v-if="os" class="resumo-decisao">
        OS: <strong>{{ os.veiculo?.placa }}</strong>
        Cliente: <strong>{{ os.cliente?.nome || '—' }}</strong>
        Veículo: <strong>{{ os.veiculo?.modelo || '—' }}</strong>
        Abertura: <strong>{{ new Date(os.data_abertura).toLocaleString('pt-BR') }}</strong>
      </p>
      <div class="form-campo">
        <label>Motivo da exclusão (obrigatório)</label>
        <Textarea v-model="formExclusaoOS.motivo" rows="3" autoResize placeholder="Mínimo 5 caracteres" />
      </div>
      <template #footer>
        <Button label="Voltar" text @click="dialogoExclusaoOSAberto = false" />
        <Button label="Excluir OS" severity="danger" :loading="salvandoExclusaoOS" @click="confirmarExcluirOS" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoCancelamentoOSAberto" modal header="Cancelar Ordem de Serviço?" style="width: 480px">
      <p class="texto-explicativo">O cancelamento preservará todo o histórico e realizará os estornos permitidos.</p>
      <p v-if="os" class="resumo-decisao">
        OS: <strong>{{ os.veiculo?.placa }}</strong>
        Cliente: <strong>{{ os.cliente?.nome || '—' }}</strong>
        Veículo: <strong>{{ os.veiculo?.modelo || '—' }}</strong>
      </p>
      <div v-if="resumoConsequenciasCancelamento.length" class="info-box">
        <p><strong>Esta OS possui:</strong></p>
        <ul>
          <li v-for="(linha, i) in resumoConsequenciasCancelamento" :key="i">{{ linha }}</li>
        </ul>
      </div>
      <div class="form-campo">
        <label>Motivo do cancelamento (obrigatório)</label>
        <Textarea v-model="formCancelamentoOS.motivo" rows="3" autoResize placeholder="Mínimo 5 caracteres" />
      </div>
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelamentoOSAberto = false" />
        <Button label="Cancelar OS" severity="danger" :loading="salvandoCancelamentoOS" @click="confirmarCancelarOS" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.estado-carregando {
  color: var(--text-muted);
  padding: 40px 0;
}
.os-detalhe {
  display: flex;
  flex-direction: column;
}
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
}
.linha-info-apoio {
  margin: 0 0 6px;
}
.alerta-adicional {
  display: flex;
  align-items: center;
  gap: 12px;
  background: var(--warning-bg);
  border: 1px solid var(--warning);
  border-radius: var(--card-radius);
  padding: 12px 16px;
  margin-bottom: 14px;
  cursor: pointer;
}
.alerta-adicional > i {
  color: var(--warning);
  font-size: 18px;
}
.alerta-adicional > div {
  flex: 1;
  min-width: 0;
}
.alerta-adicional strong {
  color: var(--text-heading);
  font-size: 13px;
}
.card {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 20px;
  margin-bottom: 14px;
}
.card h3 {
  margin: 0 0 10px;
  font-size: 13.5px;
  font-weight: 700;
  color: var(--text-heading);
}
.card p {
  margin: 0 0 6px;
  font-size: 13px;
  color: var(--text-body);
}
.acoes-documento-final {
  margin-top: 10px;
}
.checklist {
  list-style: none;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
.checklist li {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  margin-bottom: 0.9rem;
}
.form-campo label {
  font-size: 0.8rem;
  color: var(--text-muted);
}
.texto-explicativo {
  color: var(--text-body);
  font-size: 13px;
  margin: 0 0 10px;
}
.resumo-decisao {
  font-size: 12.5px;
  color: var(--text-muted);
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 12px;
}
.info-box {
  background: var(--surface-hover);
  border-radius: 8px;
  padding: 10px 14px;
  margin-bottom: 12px;
  font-size: 12.5px;
}
.info-box ul {
  margin: 4px 0 0;
  padding-left: 18px;
}
</style>
