<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputNumber from 'primevue/inputnumber'
import InputText from 'primevue/inputtext'
import Checkbox from 'primevue/checkbox'
import Tag from 'primevue/tag'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
// OS-UX-01 — reestruturação em abas (tela era uma rolagem única); STATUS_OS
// centraliza rótulo/cor do badge de status (era um mapa local + string crua).
import { STATUS_OS } from '../../constants/statusVisual.js'
import Tabs from 'primevue/tabs'
import TabList from 'primevue/tablist'
import Tab from 'primevue/tab'
import TabPanels from 'primevue/tabpanels'
import TabPanel from 'primevue/tabpanel'

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
// ETAPA 4 (P1-A) — item D (EST-004): itens do orçamento desta OS (quando
// houver), com quanto já foi executado — usados para exigir vínculo na
// baixa de peça, em vez de deixar escolher qualquer peça livremente.
const orcamentoItens = ref([])
// item G (GAR-005): itens da OS ORIGINAL disponíveis para vincular quando
// esta OS é uma garantia; e o vínculo já registrado, quando a OS atual já é
// uma garantia.
const itensOsOrigemParaGarantia = ref([])
const garantiaItensVinculados = ref([])
// ETAPA 5 (P1-B) — ADC-001..008: adicionais da OS (necessidade identificada
// durante a execução, precificada pelo encarregado, aprovada por item).
const osAdicionais = ref([])
// ETAPA 6 (P1-C) — item 2/3: fotos da OS.
const osFotos = ref([])
const checklistTemplateAtual = ref(null)

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

const podeTransicionar = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeApontar = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeResponderChecklist = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeBaixarPeca = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeGerarCobranca = computed(() => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeAbrirGarantia = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
// ETAPA 5 (P1-B) — item 13 (RBAC de adicionais): executor identifica a
// necessidade (motivo), mas NUNCA precifica nem decide; encarregado/admin
// técnico precificam (incluem item com valor); decisão (aprovar/rejeitar
// item, com meio estruturado) é encarregado/suporte administrativo/admin
// técnico — mesma composição que já registrava autorização de orçamento.
const podeIdentificarAdicional = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podePrecificarAdicional = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeDecidirAdicional = computed(() => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeCancelarAdicional = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
// ETAPA 6 (P1-C) — item 12 (RBAC)
const podeDefinirPrazo = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeRemoverExecutor = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeAnexarFoto = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))

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
      .select('id, tipo, status, data_abertura, data_liberacao, checklist_template_id, orcamento_id, os_origem_id, previsao_conclusao, previsao_definida_por, previsao_definida_em, custo_pecas, custo_mao_obra, custo_total, custo_hora_aplicado, horas_apontadas_total, custo_calculado_em, centro_custo_id, veiculo:veiculos(id, placa, prefixo, modelo), cliente:clientes(id, nome, tipo)')
      .eq('id', osId.value)
      .single(),
    // ETAPA 8 (RC2) — seção 1: 'usuario:profiles(nome)' é ambíguo porque
    // os_executores tem DUAS FKs para profiles (usuario_id e removido_por).
    // Sem desambiguação explícita, o PostgREST recusa o embed com
    // PGRST201/HTTP 300 ("Could not embed because more than one
    // relationship was found") em TODA carga de OS, mascarado até agora
    // porque o retorno era usado como `data ?? []` sem checar `.error`.
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
  // ETAPA 8 (RC2) — seção 1: as 4 chamadas abaixo são auxiliares (a OS em si
  // já carregou); não abortam a tela, mas também não podem ser silenciadas —
  // regra do CLAUDE.md ("é proibido... considerar teste não executado como
  // aprovado" aplica-se aqui por analogia a erro tratado como sucesso).
  for (const [nome, resp] of [['executores', respExec], ['movimentações de estoque', respMov], ['peças', respPecas], ['templates de checklist', respTemplates]]) {
    if (resp.error) {
      toast.add({ severity: 'warn', summary: `Falha ao carregar ${nome}`, detail: resp.error.message, life: 6000 })
    }
  }
  executores.value = respExec.data ?? []
  movimentos.value = respMov.data ?? []
  pecas.value = respPecas.data ?? []
  checklistTemplates.value = respTemplates.data ?? []

  // ETAPA 6 (P1-C) — item 2/3: fotos da OS + obrigatoriedade do checklist atual.
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

  // ETAPA 4 (P1-A) — item D (EST-004): itens do orçamento desta OS, com
  // quanto já foi baixado/executado — a baixa de peça agora exige escolher
  // um destes itens (rpc_baixar_peca_os passou a exigir p_orcamento_item_id
  // quando a OS tem orçamento).
  if (os.value.orcamento_id) {
    const { data } = await supabase
      .from('orcamento_itens')
      .select('id, peca_id, descricao, quantidade, execucao_status, status_aprovacao, peca:pecas(sku, descricao)')
      .eq('orcamento_id', os.value.orcamento_id)
    orcamentoItens.value = data ?? []
  } else {
    orcamentoItens.value = []
  }

  // item G (GAR-005): se ESTA OS é garantia, carrega o vínculo já
  // registrado (itens da OS original cobertos por esta garantia).
  if (os.value.os_origem_id) {
    const { data } = await supabase
      .from('os_garantia_itens')
      .select('orcamento_item_original_id, motivo, item:orcamento_itens(id, descricao, peca_id, quantidade, peca:pecas(sku, descricao))')
      .eq('os_garantia_id', osId.value)
    garantiaItensVinculados.value = data ?? []
  } else {
    garantiaItensVinculados.value = []
  }
  // Itens desta própria OS disponíveis para vincular ao ABRIR uma garantia
  // NOVA a partir dela (rpc_criar_os_garantia exige ao menos um quando a OS
  // original tem orçamento) — reaproveita orcamentoItens já carregado acima.
  itensOsOrigemParaGarantia.value = orcamentoItens.value

  // ETAPA 5 (P1-B) — ADC-006: adicionais e seus itens, sempre carregados
  // (independem de a OS ter orçamento — adicional é entidade ligada à OS).
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
  // OS-UX-01 — aba Histórico: leitura adicional só de mudança de status,
  // de uma tabela de auditoria que já existe (auditoria_eventos, populada
  // por trigger — ver supabase/migrations/20260812093500_p1a_auditoria.sql).
  // Não é RPC nem migration nova; a RLS da própria tabela já nega pra
  // executor, `podeVerHistorico` só espelha isso pra não fazer um select
  // que sempre voltaria vazio.
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
const transicoesDisponiveis = computed(() => {
  const mapa = {
    aberta: [{ label: 'Iniciar Diagnóstico', next: 'em_diagnostico' }, { label: 'Cancelar', next: 'cancelada', danger: true }],
    em_diagnostico: [
      { label: 'Enviar p/ Aprovação (orçamento adicional)', next: 'aguardando_aprovacao' },
      { label: 'Iniciar Execução', next: 'em_execucao' },
      { label: 'Cancelar', next: 'cancelada', danger: true },
    ],
    aguardando_aprovacao: [{ label: 'Iniciar Execução', next: 'em_execucao' }, { label: 'Cancelar', next: 'cancelada', danger: true }],
    em_execucao: [{ label: 'Enviar p/ Teste', next: 'aguardando_teste' }],
  }
  return mapa[os.value?.status] ?? []
})

async function transicionar(next) {
  const { error } = await supabase.rpc('rpc_transicionar_os', { p_os_id: osId.value, p_novo_status: next })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao transicionar', detail: error.message, life: 6000 })
    return
  }
  await carregar()
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

// ---------- Prazo (ETAPA 6/P1-C — Decisão 3, PEN-003) ----------
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

// ---------- Fotos (ETAPA 6/P1-C — item 2/3, Decisão 6) ----------
const formFoto = ref({ tipo: 'antes', arquivo: null, observacao: '' })
const enviandoFoto = ref(false)
function onArquivoFotoSelecionado(event) {
  formFoto.value.arquivo = event.target.files[0] || null
}
async function enviarFoto() {
  if (!formFoto.value.arquivo) {
    toast.add({ severity: 'warn', summary: 'Selecione o arquivo da foto', life: 4000 })
    return
  }
  enviandoFoto.value = true
  const caminhoDestino = `${osId.value}/${formFoto.value.tipo}/${Date.now()}-${formFoto.value.arquivo.name}`
  const { error: erroUpload } = await supabase.storage.from('os-fotos').upload(caminhoDestino, formFoto.value.arquivo)
  if (erroUpload) {
    enviandoFoto.value = false
    toast.add({ severity: 'error', summary: 'Erro ao enviar foto', detail: erroUpload.message, life: 6000 })
    return
  }
  const { error } = await supabase.rpc('rpc_registrar_foto_os', {
    p_os_id: osId.value,
    p_tipo: formFoto.value.tipo,
    p_arquivo_path: caminhoDestino,
    p_observacao: formFoto.value.observacao || null,
  })
  enviandoFoto.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Foto recusada', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Foto registrada', life: 3000 })
  formFoto.value = { tipo: 'antes', arquivo: null, observacao: '' }
  await carregar()
}

// ETAPA 4 (P1-A) — item G (GAR-005): abrir garantia agora exige escolher
// quais itens da OS original são objeto do retorno — não é mais possível
// abrir uma garantia "em branco" e depois lançar qualquer coisa nela.
const dialogoGarantiaAberto = ref(false)
const itensGarantiaSelecionados = ref([])

function confirmarAbrirGarantia() {
  if (orcamentoItens.value.length === 0) {
    // OS sem orçamento (ex.: interna) — nada para vincular, RPC aceita array vazio.
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

// ---------- Apontamento ----------
const formApontamento = ref({ etapa: null, observacao: '' })
const etapas = ['diagnostico', 'execucao', 'teste', 'revisao']

async function iniciarApontamento() {
  if (!formApontamento.value.etapa) {
    toast.add({ severity: 'warn', summary: 'Selecione a etapa', life: 4000 })
    return
  }
  const { error } = await supabase.from('os_executores').insert({
    os_id: osId.value,
    usuario_id: auth.profile.id,
    etapa: formApontamento.value.etapa,
    inicio: new Date().toISOString(),
    observacao: formApontamento.value.observacao || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao iniciar apontamento', detail: error.message, life: 5000 })
    return
  }
  formApontamento.value = { etapa: null, observacao: '' }
  await carregar()
}

// ETAPA 4 (P1-A) — item F (CON-007): apontamento só pode ser encerrado
// enquanto a OS não está concluída/liberada/cancelada (o backend já nega o
// UPDATE nesses casos — esconder o botão evita o usuário tentar uma ação
// que sempre falharia, mas a garantia real continua sendo a policy).
const osEncerrada = computed(() => ['concluida', 'liberada', 'cancelada'].includes(os.value?.status))

async function encerrarApontamento(exec) {
  const { error } = await supabase.from('os_executores').update({ fim: new Date().toISOString() }).eq('id', exec.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao encerrar apontamento', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

// ---------- Remoção formal de executor (ETAPA 6/P1-C — item 8, EXE-003) ----------
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
// ETAPA 4 (P1-A) — item D (EST-004): quando a OS tem orçamento (ou é
// garantia com item vinculado), a baixa exige escolher o ITEM aprovado —
// a peça é derivada do item, não escolhida livremente (rpc_baixar_peca_os
// agora exige p_orcamento_item_id nesses casos e bloqueia peça fora do
// escopo aprovado).
const formBaixa = ref({ peca_id: null, quantidade: 1, chave: null })
const podeMovimentarEstoque = computed(() => ['em_diagnostico', 'em_execucao'].includes(os.value?.status))
const podeBaixarLivre = computed(() => !os.value?.orcamento_id && !os.value?.os_origem_id)

// saída soma, estorno_saída subtrai — reflete o líquido realmente consumido
// deste item nesta OS (mesmo cálculo do backend em
// sincronizar_execucao_item_orcamento / sincronizar_execucao_item_adicional).
function quantidadeJaBaixada(itemId, origem) {
  const campo = origem === 'adicional' ? 'os_adicional_item_id' : 'orcamento_item_id'
  return movimentos.value
    .filter((m) => m[campo] === itemId)
    .reduce((soma, m) => soma + (m.tipo === 'estorno_saida' ? -Number(m.quantidade) : Number(m.quantidade)), 0)
}

// ETAPA 5 (P1-B) — item 8: lista de itens elegíveis para baixa combina
// itens do orçamento original, itens vinculados via garantia, E itens
// APROVADOS de adicionais (rpc_baixar_peca_os agora aceita os dois vínculos,
// mutuamente exclusivos — a origem de cada baixa fica sempre identificável
// no ledger via orcamento_item_id OU os_adicional_item_id).
const itensParaBaixa = computed(() => {
  // ETAPA 5 (P1-B) — achado real de verificação visual: mesmo motivo do
  // itensMaoDeObra acima — só item APROVADO entra na lista de baixa (item
  // rejeitado/pendente sempre seria recusado pelo backend).
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
function selecionouItemBaixa() {
  const item = itensParaBaixa.value.find((i) => i.chave === formBaixa.value.chave)
  formBaixa.value.peca_id = item?.peca_id ?? null
}

async function baixarPeca() {
  const itemSelecionado = itensParaBaixa.value.find((i) => i.chave === formBaixa.value.chave)
  if (!podeBaixarLivre.value && !itemSelecionado) {
    toast.add({ severity: 'warn', summary: 'Selecione o item do orçamento/adicional/garantia', life: 4000 })
    return
  }
  if (!formBaixa.value.peca_id || !formBaixa.value.quantidade) {
    toast.add({ severity: 'warn', summary: 'Selecione a peça e a quantidade', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_baixar_peca_os', {
    p_os_id: osId.value,
    p_peca_id: formBaixa.value.peca_id,
    p_quantidade: formBaixa.value.quantidade,
    p_orcamento_item_id: itemSelecionado?.origem === 'orcamento' ? itemSelecionado.id : null,
    p_os_adicional_item_id: itemSelecionado?.origem === 'adicional' ? itemSelecionado.id : null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao baixar peça', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Peça baixada do estoque', life: 3000 })
  formBaixa.value = { peca_id: null, quantidade: 1, chave: null }
  await carregar()
}

// ---------- Itens de mão de obra (item E / CON-002) ----------
// Itens sem peça (mão de obra) não têm sinal automático de execução —
// precisam ser marcados manualmente antes de a OS poder ser concluída.
// ETAPA 5 (P1-B) — achado real de verificação visual: itens PENDENTES/REJEITADOS
// nunca são executáveis (item 7 do pedido) — a lista de mão de obra "para marcar
// execução" só deve conter itens já APROVADOS, senão a UI oferece uma ação que o
// backend sempre vai recusar (rpc_marcar_item_orcamento_execucao agora exige
// status_aprovacao='aprovado'). Itens rejeitados continuam visíveis no
// histórico via "Ver decisões" no orçamento (nunca somem), só não aparecem
// aqui como "pendentes de execução".
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

// tipo: 'orcamento' (default) ou 'adicional' — ETAPA 5 (P1-B) reaproveita o
// mesmo diálogo/RPC-por-tipo em vez de duplicar a UI de "dispensar item".
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

// ---------- Adicionais (ETAPA 5 / P1-B — ADC-001..008) ----------
const dialogoNovoAdicionalAberto = ref(false)
const formNovoAdicional = ref({ motivo: '' })
let adicionalIdempotencyKey = crypto.randomUUID()

function abrirNovoAdicional() {
  formNovoAdicional.value = { motivo: '' }
  adicionalIdempotencyKey = crypto.randomUUID()
  dialogoNovoAdicionalAberto.value = true
}

async function criarAdicional() {
  if (!formNovoAdicional.value.motivo || formNovoAdicional.value.motivo.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Descreva o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_criar_os_adicional', {
    p_os_id: osId.value,
    p_motivo: formNovoAdicional.value.motivo,
    p_idempotency_key: adicionalIdempotencyKey,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao identificar adicional', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Necessidade registrada — aguardando precificação', life: 3000 })
  dialogoNovoAdicionalAberto.value = false
  adicionalIdempotencyKey = crypto.randomUUID()
  await carregar()
}

const dialogoItemAdicionalAberto = ref(false)
const adicionalAtual = ref(null)
const formItemAdicional = ref({ peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0, justificativa: '' })

function abrirIncluirItemAdicional(adicional) {
  adicionalAtual.value = adicional
  formItemAdicional.value = { peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0, justificativa: '' }
  dialogoItemAdicionalAberto.value = true
}
function selecionouPecaAdicional() {
  const p = pecas.value.find((x) => x.id === formItemAdicional.value.peca_id)
  if (p && !formItemAdicional.value.descricao) formItemAdicional.value.descricao = p.descricao
}
async function incluirItemAdicional() {
  if (!formItemAdicional.value.descricao || formItemAdicional.value.quantidade <= 0) {
    toast.add({ severity: 'warn', summary: 'Descrição e quantidade são obrigatórias', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_incluir_item_os_adicional', {
    p_adicional_id: adicionalAtual.value.id,
    p_peca_id: formItemAdicional.value.peca_id || null,
    p_descricao: formItemAdicional.value.descricao,
    p_quantidade: formItemAdicional.value.quantidade,
    p_valor_unitario: formItemAdicional.value.valor_unitario,
    p_justificativa: formItemAdicional.value.justificativa || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao incluir item', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Item incluído no adicional', life: 3000 })
  dialogoItemAdicionalAberto.value = false
  await carregar()
}

// Decisão de item de adicional — mesmo padrão estrutural do orçamento
// (APR-004/005/006: meio de aprovação sempre estruturado, nunca inferido).
const dialogoDecisaoAdicionalAberto = ref(false)
const itemAdicionalAtual = ref(null)
const formDecisaoAdicional = ref({ autorizado_por_nome: '', meio_aprovacao: 'sistema', observacao: '', arquivo: null })
const meiosAprovacaoAdicional = [
  { label: 'Sistema (botão)', value: 'sistema' },
  { label: 'E-mail (evidência obrigatória)', value: 'email' },
  { label: 'Verbal documentado (observação obrigatória)', value: 'verbal_documentado' },
]

function abrirDecisaoAdicional(item) {
  itemAdicionalAtual.value = item
  formDecisaoAdicional.value = { autorizado_por_nome: '', meio_aprovacao: 'sistema', observacao: '', arquivo: null }
  dialogoDecisaoAdicionalAberto.value = true
}
function onArquivoDecisaoAdicionalSelecionado(event) {
  formDecisaoAdicional.value.arquivo = event.target.files[0] || null
}
async function decidirItemAdicional(decisao) {
  const item = itemAdicionalAtual.value
  if (!formDecisaoAdicional.value.autorizado_por_nome || formDecisaoAdicional.value.autorizado_por_nome.trim().length < 2) {
    toast.add({ severity: 'warn', summary: 'Informe o nome de quem autorizou', life: 5000 })
    return
  }
  if (formDecisaoAdicional.value.meio_aprovacao === 'verbal_documentado' && formDecisaoAdicional.value.observacao.trim().length < 10) {
    toast.add({ severity: 'warn', summary: 'Observação obrigatória (mín. 10 caracteres) para verbal documentado', life: 5000 })
    return
  }
  let comprovantePath = null
  if (formDecisaoAdicional.value.meio_aprovacao === 'email') {
    if (!formDecisaoAdicional.value.arquivo) {
      toast.add({ severity: 'warn', summary: 'Anexe o comprovante do e-mail', life: 5000 })
      return
    }
    const caminhoDestino = `${osId.value}/adicional-item-${item.id}-${Date.now()}-${formDecisaoAdicional.value.arquivo.name}`
    const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, formDecisaoAdicional.value.arquivo)
    if (erroUpload) {
      toast.add({ severity: 'error', summary: 'Erro ao enviar comprovante', detail: erroUpload.message, life: 6000 })
      return
    }
    comprovantePath = caminhoDestino
  }
  const { error } = await supabase.rpc('rpc_decidir_item_os_adicional', {
    p_item_id: item.id,
    p_decisao: decisao,
    p_meio_aprovacao: formDecisaoAdicional.value.meio_aprovacao,
    p_autorizado_por_nome: formDecisaoAdicional.value.autorizado_por_nome,
    p_comprovante_path: comprovantePath,
    p_observacao: formDecisaoAdicional.value.observacao || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar decisão', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: `Item ${decisao}`, life: 3000 })
  dialogoDecisaoAdicionalAberto.value = false
  await carregar()
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

const dialogoCancelarAdicionalAberto = ref(false)
const adicionalParaCancelar = ref(null)
const motivoCancelamentoAdicional = ref('')
function abrirCancelarAdicional(adicional) {
  adicionalParaCancelar.value = adicional
  motivoCancelamentoAdicional.value = ''
  dialogoCancelarAdicionalAberto.value = true
}
async function confirmarCancelarAdicional() {
  if (!motivoCancelamentoAdicional.value || motivoCancelamentoAdicional.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_cancelar_os_adicional', {
    p_adicional_id: adicionalParaCancelar.value.id,
    p_motivo: motivoCancelamentoAdicional.value,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao cancelar adicional', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Adicional cancelado (auditado)', life: 3000 })
  dialogoCancelarAdicionalAberto.value = false
  await carregar()
}

function valorAdicional(adicional, filtro) {
  return (adicional.os_adicional_itens ?? [])
    .filter((i) => (filtro ? i.status_aprovacao === filtro : true))
    .reduce((s, i) => s + Number(i.valor_total), 0)
}

const severidadeStatusAdicional = { aguardando_aprovacao: 'warn', aprovado: 'success', parcialmente_aprovado: 'warn', rejeitado: 'danger' }
const tagDecisaoItemAdicional = { pendente: 'warn', aprovado: 'success', rejeitado: 'danger' }

// ======================================================================
// OS-UX-01 — acréscimos de reestruturação de UI (cabeçalho/barra de etapas/
// abas/histórico). Nada acima desta linha foi alterado: mesmas RPCs, mesmos
// parâmetros, mesmo RBAC, mesmo state machine.
// ======================================================================

const tabAtiva = ref('geral')

// Histórico: mesma RLS de auditoria_eventos (perfil !== 'executor')
// espelhada aqui só pra não disparar um select que sempre voltaria vazio.
const auditoriaEventos = ref([])
const podeVerHistorico = computed(() => auth.perfil !== 'executor')

// Barra de etapas — um passo por status REAL da máquina de estado (não
// inventa estado novo). `aguardando_aprovacao` não é passo próprio (é
// sub-estado opcional entre Diagnóstico e Execução — ver plano); vira selo
// no passo "Diagnóstico". `cancelada`/`reaberta_garantia` não aparecem como
// passo (cancelada é terminal, alcançável de 3 pontos diferentes;
// reaberta_garantia é valor vestigial, nenhuma transição real neste arquivo
// o produz — uma garantia é sempre uma OS nova via rpc_criar_os_garantia).
const ETAPAS_OS = [
  { status: 'aberta', label: 'Aberta', icone: 'pi pi-file' },
  { status: 'em_diagnostico', label: 'Diagnóstico', icone: 'pi pi-search' },
  { status: 'em_execucao', label: 'Execução', icone: 'pi pi-wrench' },
  { status: 'aguardando_teste', label: 'Teste', icone: 'pi pi-verified' },
  { status: 'concluida', label: 'Concluída', icone: 'pi pi-check-circle' },
  { status: 'liberada', label: 'Liberada', icone: 'pi pi-flag-fill' },
]
const indiceEtapaAtual = computed(() => {
  if (os.value?.status === 'aguardando_aprovacao') return 1 // mesma posição de "Diagnóstico"
  return ETAPAS_OS.findIndex((e) => e.status === os.value?.status)
})
const mostrarBarraEtapas = computed(() => indiceEtapaAtual.value !== -1)
const emAguardandoAprovacao = computed(() => os.value?.status === 'aguardando_aprovacao')

// Cabeçalho — hierarquia de botões (item 5 do pedido): quando só existe UMA
// transição não-destrutiva disponível, ela é a ação primária; quando há
// mais de uma (em_diagnostico: "Enviar p/ Aprovação" x "Iniciar Execução"),
// nenhuma tem preferência codificada no state machine — as duas ficam
// secundárias, empatadas. "Cancelar" nunca entra nesse grupo (é sempre
// destrutiva, renderizada à parte).
const transicoesNaoDanger = computed(() => transicoesDisponiveis.value.filter((t) => !t.danger))
const transicaoDanger = computed(() => transicoesDisponiveis.value.find((t) => t.danger) ?? null)

// Resumo operacional (Visão Geral) — só agrega o que já está carregado,
// nenhum fetch novo, nenhum cálculo de negócio (é contagem/soma de exibição).
const resumoOS = computed(() => ({
  execucoesAtivas: executores.value.filter((e) => e.ativo !== false && !e.fim).length,
  totalExecucoes: executores.value.length,
  totalPecasQtd: movimentos.value.length,
  totalPecasValor: movimentos.value.reduce((s, m) => s + Number(m.quantidade) * Number(m.custo_unitario ?? 0), 0),
  totalFotos: osFotos.value.length,
  adicionaisAbertos: osAdicionais.value.filter((a) => a.status === 'aguardando_aprovacao').length,
  adicionaisTotal: osAdicionais.value.length,
}))

// Histórico — timeline client-side juntando o evento real de mudança de
// status (auditoria_eventos) com eventos já reconstituíveis dos arrays já
// carregados (abertura, apontamentos, fotos, adicionais, garantias). Nenhum
// dado inventado — cada linha vem de um campo que já existe.
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

watch(osId, carregar, { immediate: true })
</script>

<template>
  <div v-if="carregando" class="estado-carregando">Carregando...</div>
  <div v-else-if="os" class="os-detalhe">

    <!-- ===== CABEÇALHO-RESUMO ===== -->
    <div class="cabecalho-os">
      <div class="cabecalho-esquerda">
        <div class="cabecalho-titulo-linha">
          <Button icon="pi pi-arrow-left" text @click="router.push('/os')" />
          <h2>OS — {{ os.veiculo?.placa }} <span v-if="os.veiculo?.prefixo">({{ os.veiculo.prefixo }})</span></h2>
        </div>
        <div class="cabecalho-info-grid">
          <div class="info-bloco">
            <span class="info-label">Cliente</span>
            <span class="info-valor">{{ os.cliente?.nome }}</span>
          </div>
          <div class="info-bloco">
            <span class="info-label">Veículo</span>
            <span class="info-valor">{{ os.veiculo?.modelo || '—' }}</span>
          </div>
          <div class="info-bloco">
            <span class="info-label">Tipo de OS</span>
            <Tag :value="os.tipo === 'interna' ? 'Interna' : 'Externa'" :severity="os.tipo === 'interna' ? 'secondary' : 'info'" />
          </div>
          <div class="info-bloco">
            <span class="info-label">Abertura</span>
            <span class="info-valor">{{ new Date(os.data_abertura).toLocaleString('pt-BR') }}</span>
          </div>
          <div class="info-bloco">
            <span class="info-label">Previsão de conclusão</span>
            <span class="info-valor-linha">
              <span v-if="os.previsao_conclusao" class="info-valor">{{ new Date(os.previsao_conclusao).toLocaleString('pt-BR') }}</span>
              <span v-else class="hint">Não definida</span>
              <Button v-if="podeDefinirPrazo && !osEncerrada" icon="pi pi-pencil" size="small" text @click="abrirPrazo" aria-label="Definir/Alterar previsão" />
            </span>
          </div>
        </div>
      </div>

      <div class="cabecalho-direita">
        <Tag :severity="STATUS_OS[os.status]?.severidade" :value="STATUS_OS[os.status]?.label ?? os.status" class="status-tag-grande" />
        <div class="cabecalho-acoes" v-if="podeTransicionar || ['aguardando_teste', 'concluida', 'liberada'].includes(os.status) || (os.status === 'concluida' && os.tipo === 'externa' && podeGerarCobranca) || os.os_origem_id">
          <!-- ação primária: única transição não-destrutiva quando há só uma -->
          <Button
            v-for="t in transicoesNaoDanger"
            :key="t.next"
            :label="t.label"
            size="small"
            :class="{ 'btn-gradiente': transicoesNaoDanger.length === 1 }"
            :outlined="transicoesNaoDanger.length > 1"
            @click="confirmarTransicao(t)"
          />
          <Button v-if="os.status === 'aguardando_teste'" label="Concluir (checklist)" size="small" class="btn-gradiente" @click="concluir" />
          <Button v-if="os.status === 'concluida'" label="Liberar" size="small" class="btn-gradiente" @click="liberar" />
          <Button
            v-if="os.status === 'concluida' && os.tipo === 'externa' && podeGerarCobranca"
            label="Gerar Cobrança"
            size="small"
            icon="pi pi-wallet"
            outlined
            @click="router.push({ path: '/financeiro/cobrancas', query: { cliente_id: os.cliente.id, os_id: os.id } })"
          />
          <Button
            v-if="dentroDoPrazoGarantia && podeAbrirGarantia"
            label="Abrir Garantia"
            size="small"
            icon="pi pi-shield"
            :class="{ 'btn-gradiente': os.status === 'liberada' }"
            :outlined="os.status !== 'liberada'"
            @click="confirmarAbrirGarantia"
          />
          <!-- destrutiva: sempre separada, nunca disputa peso visual com a primária -->
          <Button v-if="transicaoDanger" :label="transicaoDanger.label" size="small" severity="danger" outlined @click="confirmarTransicao(transicaoDanger)" />
          <!-- ETAPA 6 (P1-C) — item 4/5, peso mínimo (link), independente do status -->
          <Button
            v-if="['concluida', 'liberada'].includes(os.status)"
            label="Relatório de Encerramento"
            size="small"
            icon="pi pi-file"
            text
            @click="router.push('/os/' + osId + '/relatorio-encerramento')"
          />
          <Button
            v-if="os.os_origem_id"
            label="Relatório de Garantia"
            size="small"
            icon="pi pi-shield"
            text
            @click="router.push('/os/' + osId + '/relatorio-garantia')"
          />
        </div>
      </div>
    </div>

    <!-- ===== BARRA DE ETAPAS ===== -->
    <div v-if="mostrarBarraEtapas" class="barra-etapas">
      <template v-for="(etapa, i) in ETAPAS_OS" :key="etapa.status">
        <div class="etapa" :class="{ 'etapa-concluida': i < indiceEtapaAtual, 'etapa-atual': i === indiceEtapaAtual }">
          <div class="etapa-icone"><i :class="i < indiceEtapaAtual ? 'pi pi-check' : etapa.icone"></i></div>
          <span class="etapa-label">{{ etapa.label }}</span>
          <Tag v-if="i === indiceEtapaAtual && emAguardandoAprovacao" severity="warn" value="aguardando aprovação" class="etapa-selo" />
        </div>
        <div v-if="i < ETAPAS_OS.length - 1" class="etapa-linha" :class="{ 'etapa-linha-concluida': i < indiceEtapaAtual }"></div>
      </template>
    </div>
    <div v-else-if="os.status === 'cancelada'" class="badge-terminal badge-cancelada">
      <i class="pi pi-times-circle"></i> OS cancelada
    </div>

    <!-- ===== ABAS ===== -->
    <Tabs v-model:value="tabAtiva" class="tabs-os">
      <TabList>
        <Tab value="geral"><i class="pi pi-th-large" style="margin-right:6px"></i>Visão Geral</Tab>
        <Tab value="execucao"><i class="pi pi-wrench" style="margin-right:6px"></i>Execução</Tab>
        <Tab value="pecas"><i class="pi pi-box" style="margin-right:6px"></i>Peças</Tab>
        <Tab value="fotos"><i class="pi pi-image" style="margin-right:6px"></i>Fotos</Tab>
        <Tab value="adicionais"><i class="pi pi-plus-circle" style="margin-right:6px"></i>Adicionais</Tab>
        <Tab v-if="podeVerHistorico" value="historico"><i class="pi pi-history" style="margin-right:6px"></i>Histórico</Tab>
      </TabList>
      <TabPanels>

        <!-- ---------- VISÃO GERAL ---------- -->
        <TabPanel value="geral">
          <div v-if="osOrigem || osGarantias.length > 0 || dentroDoPrazoGarantia" class="card">
            <h3>Garantia</h3>
            <p v-if="osOrigem" class="hint">
              Esta OS é garantia da
              <router-link :to="'/os/' + osOrigem.id">OS {{ osOrigem.veiculo?.placa }}<span v-if="osOrigem.veiculo?.prefixo"> ({{ osOrigem.veiculo.prefixo }})</span></router-link>
              — sem cobrança ao cliente.
            </p>
            <div v-if="osGarantias.length > 0" class="hint">
              Garantia(s) aberta(s) a partir desta OS:
              <router-link v-for="g in osGarantias" :key="g.id" :to="'/os/' + g.id" style="margin-right: 0.5rem">
                {{ g.veiculo?.placa }} ({{ rotuloStatus(g.status) }})
              </router-link>
            </div>
            <p v-if="dentroDoPrazoGarantia" class="hint">Garantia até {{ prazoGarantiaAte.toLocaleDateString('pt-BR') }}.</p>
          </div>

          <div v-if="os.tipo === 'interna' && os.custo_calculado_em" class="card">
            <h3>Custo Interno</h3>
            <p class="hint">
              Peças {{ formatarMoeda(os.custo_pecas) }} + mão de obra {{ formatarMoeda(os.custo_mao_obra) }}
              ({{ os.horas_apontadas_total }}h × {{ formatarMoeda(os.custo_hora_aplicado) }}) = <strong>{{ formatarMoeda(os.custo_total) }}</strong>
              — sem cobrança (cliente interno).
            </p>
          </div>

          <div class="card">
            <h3>Previsão de Conclusão</h3>
            <p v-if="os.previsao_conclusao">{{ new Date(os.previsao_conclusao).toLocaleString('pt-BR') }}</p>
            <p v-else class="hint">Não definida.</p>
            <Button v-if="podeDefinirPrazo && !osEncerrada" label="Definir previsão" icon="pi pi-calendar" size="small" outlined @click="abrirPrazo" />
          </div>

          <div class="card">
            <h3>Checklist Técnico</h3>
            <div v-if="!os.checklist_template_id && podeTransicionar" class="form-linha">
              <Select :options="checklistTemplates" optionLabel="nome" optionValue="id" placeholder="Definir checklist" @update:modelValue="definirChecklist" />
            </div>
            <div v-else-if="!os.checklist_template_id" class="estado-vazio-card">
              <i class="pi pi-list-check"></i>
              <div>
                <strong>Nenhum checklist definido</strong>
                <p>Um encarregado ou administrador técnico precisa vincular um checklist a esta OS.</p>
              </div>
            </div>
            <ul v-else class="checklist">
              <li v-for="item in checklistItens" :key="item.id">
                <Checkbox
                  :modelValue="respostaDoItem(item.id)?.ok ?? false"
                  binary
                  :disabled="!podeResponderChecklist"
                  @update:modelValue="(v) => alternarResposta(item, v)"
                />
                <span>{{ item.descricao }}</span>
                <Tag v-if="item.obrigatorio" severity="danger" value="obrigatório" />
              </li>
            </ul>
          </div>

          <div class="card" v-if="os.orcamento_id && itensMaoDeObra.length > 0">
            <h3>Mão de Obra Prevista</h3>
            <p class="card-subtitulo">Vinculada ao orçamento desta OS — itens sem peça não têm sinal automático de execução.</p>
            <ul class="checklist">
              <li v-for="item in itensMaoDeObra" :key="item.id">
                <span>{{ item.descricao }} ({{ item.quantidade }})</span>
                <Tag :severity="item.execucao_status === 'executado' ? 'success' : item.execucao_status === 'cancelado' ? 'danger' : 'warn'" :value="item.execucao_status" />
                <template v-if="podeMarcarExecucao && !['executado', 'cancelado'].includes(item.execucao_status)">
                  <Button label="Marcar executado" size="small" text @click="marcarItemExecutado(item)" />
                  <Button label="Dispensar (cancelar)" size="small" text severity="danger" @click="abrirCancelarItem(item)" />
                </template>
              </li>
            </ul>
          </div>

          <div class="card">
            <h3>Resumo da OS</h3>
            <p class="card-subtitulo">Contagem operacional a partir do que já foi registrado nesta OS.</p>
            <div class="resumo-grid">
              <div class="resumo-item">
                <span class="resumo-valor">{{ resumoOS.execucoesAtivas }}</span>
                <span class="resumo-label">apontamento(s) em andamento</span>
              </div>
              <div class="resumo-item">
                <span class="resumo-valor">{{ resumoOS.totalPecasQtd }}</span>
                <span class="resumo-label">movimentação(ões) de peça</span>
              </div>
              <div class="resumo-item">
                <span class="resumo-valor">{{ formatarMoeda(resumoOS.totalPecasValor) }}</span>
                <span class="resumo-label">custo de peças baixadas</span>
              </div>
              <div class="resumo-item">
                <span class="resumo-valor">{{ resumoOS.totalFotos }}</span>
                <span class="resumo-label">foto(s) anexada(s)</span>
              </div>
              <div class="resumo-item">
                <span class="resumo-valor">{{ resumoOS.adicionaisAbertos }}/{{ resumoOS.adicionaisTotal }}</span>
                <span class="resumo-label">adicional(is) aguardando decisão</span>
              </div>
            </div>
          </div>
        </TabPanel>

        <!-- ---------- EXECUÇÃO ---------- -->
        <TabPanel value="execucao">
          <div class="card">
            <h3>Apontamento de Execução</h3>
            <div class="form-linha" v-if="podeApontar">
              <Select v-model="formApontamento.etapa" :options="etapas" placeholder="Etapa" />
              <InputText v-model="formApontamento.observacao" placeholder="Observação (opcional)" />
              <Button label="Iniciar" size="small" @click="iniciarApontamento" />
            </div>
            <DataTable :value="executores" dataKey="id" size="small">
              <template #empty>
                <div class="estado-vazio-card">
                  <i class="pi pi-clock"></i>
                  <div>
                    <strong>Nenhum apontamento registrado</strong>
                    <p>Inicie um apontamento acima para começar a registrar o tempo de execução.</p>
                  </div>
                </div>
              </template>
              <Column header="Executor">
                <template #body="{ data }">
                  {{ data.usuario?.nome }}
                  <Tag v-if="data.ativo === false" severity="danger" value="removido" style="margin-left:0.3rem;font-size:0.65rem" />
                </template>
              </Column>
              <Column field="etapa" header="Etapa" />
              <Column header="Início"><template #body="{ data }">{{ new Date(data.inicio).toLocaleString('pt-BR') }}</template></Column>
              <Column header="Fim">
                <template #body="{ data }">
                  <span v-if="data.fim">{{ new Date(data.fim).toLocaleString('pt-BR') }}</span>
                  <!-- CON-007 (ETAPA 4 P1-A): encerrar só disponível enquanto a OS não está fechada -->
                  <Button v-else-if="data.usuario_id === auth.profile.id && !osEncerrada" label="Encerrar" size="small" text @click="encerrarApontamento(data)" />
                </template>
              </Column>
              <Column field="observacao" header="Observação" />
              <!-- ETAPA 6 (P1-C) — item 8 (EXE-003): encerrar participação, nunca apagar histórico -->
              <Column header="">
                <template #body="{ data }">
                  <Button v-if="podeRemoverExecutor && data.ativo !== false && !osEncerrada" label="Remover" size="small" text severity="danger" @click="abrirRemoverExecutor(data)" />
                </template>
              </Column>
            </DataTable>
            <p v-if="osEncerrada" class="hint">OS encerrada — apontamentos não são mais editáveis diretamente (correção formal auditada disponível ao encarregado/admin técnico).</p>
          </div>
        </TabPanel>

        <!-- ---------- PEÇAS ---------- -->
        <TabPanel value="pecas">
          <div class="card">
            <h3>Peças Utilizadas</h3>
            <!-- EST-004/GAR-005 (P1-A) + item 8 (P1-B, adicionais): quando existe item
                 elegível (orçamento, garantia OU adicional aprovado), a baixa exige
                 escolher o ITEM — a peça é derivada dele, nunca uma peça livre fora
                 do escopo aprovado. A origem (orçamento x adicional) fica sempre
                 identificável no ledger (orcamento_item_id x os_adicional_item_id). -->
            <div class="form-linha" v-if="podeBaixarPeca && podeMovimentarEstoque && itensParaBaixa.length > 0">
              <Select
                v-model="formBaixa.chave"
                :options="itensParaBaixa"
                optionLabel="descricao"
                optionValue="chave"
                filter
                placeholder="Item aprovado (orçamento/adicional/garantia)"
                @update:modelValue="selecionouItemBaixa"
              >
                <template #option="{ option }">
                  <Tag v-if="option.origem === 'adicional'" severity="warn" value="adicional" style="margin-right:0.3rem;font-size:0.65rem" />
                  {{ option.descricao }} — {{ option.peca?.descricao }} (restam {{ option.restante }} de {{ option.quantidade }})
                </template>
              </Select>
              <InputNumber v-model="formBaixa.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
              <Button label="Baixar" size="small" @click="baixarPeca" :disabled="!formBaixa.chave" />
            </div>
            <p v-else-if="podeBaixarPeca && podeMovimentarEstoque && !podeBaixarLivre" class="hint">
              Nenhum item de peça aprovado (orçamento/adicional) disponível para baixa nesta OS.
            </p>
            <div class="form-linha" v-else-if="podeBaixarPeca && podeMovimentarEstoque">
              <Select v-model="formBaixa.peca_id" :options="pecas" optionLabel="descricao" optionValue="id" filter placeholder="Peça" />
              <InputNumber v-model="formBaixa.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
              <Button label="Baixar" size="small" @click="baixarPeca" />
            </div>
            <p v-else-if="podeBaixarPeca" class="hint">Baixa de peças só é permitida com a OS em diagnóstico ou execução.</p>
            <DataTable :value="movimentos" dataKey="id" size="small">
              <template #empty>
                <div class="estado-vazio-card">
                  <i class="pi pi-box"></i>
                  <div>
                    <strong>Nenhuma peça baixada</strong>
                    <p>Peças utilizadas nesta OS aparecerão aqui assim que forem baixadas do estoque.</p>
                  </div>
                </div>
              </template>
              <Column header="Peça"><template #body="{ data }">{{ data.peca?.descricao }} ({{ data.peca?.sku }})</template></Column>
              <Column field="quantidade" header="Qtde" />
              <Column header="Origem">
                <template #body="{ data }">
                  <Tag v-if="data.os_adicional_item_id" severity="warn" value="adicional" />
                  <Tag v-else-if="data.orcamento_item_id" severity="info" value="orçamento" />
                  <span v-else class="hint">avulsa</span>
                </template>
              </Column>
              <Column header="Custo Unit."><template #body="{ data }">{{ (data.custo_unitario ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</template></Column>
              <Column header="Data"><template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template></Column>
            </DataTable>
          </div>
        </TabPanel>

        <!-- ---------- FOTOS ---------- -->
        <TabPanel value="fotos">
          <div class="card">
            <h3>Fotos</h3>
            <p v-if="checklistTemplateAtual" class="hint">
              Este tipo de serviço exige:
              <Tag :severity="checklistTemplateAtual.foto_antes_obrigatoria ? 'danger' : 'secondary'" :value="checklistTemplateAtual.foto_antes_obrigatoria ? 'foto antes obrigatória' : 'foto antes opcional'" style="margin-right:0.3rem" />
              <Tag :severity="checklistTemplateAtual.foto_depois_obrigatoria ? 'danger' : 'secondary'" :value="checklistTemplateAtual.foto_depois_obrigatoria ? 'foto depois obrigatória' : 'foto depois opcional'" />
            </p>
            <div class="form-linha" v-if="podeAnexarFoto && !osEncerrada">
              <Select v-model="formFoto.tipo" :options="[{ label: 'Antes', value: 'antes' }, { label: 'Depois', value: 'depois' }, { label: 'Outro', value: 'outro' }]" optionLabel="label" optionValue="value" />
              <input type="file" accept="image/jpeg,image/png,image/webp" @change="onArquivoFotoSelecionado" />
              <InputText v-model="formFoto.observacao" placeholder="Observação (opcional)" />
              <Button label="Enviar" size="small" :loading="enviandoFoto" @click="enviarFoto" />
            </div>
            <ul v-if="osFotos.length > 0" class="checklist">
              <li v-for="f in osFotos" :key="f.id">
                <Tag :severity="f.tipo === 'antes' ? 'info' : f.tipo === 'depois' ? 'success' : 'secondary'" :value="f.tipo" />
                <span>{{ f.arquivo_path.split('/').pop() }}</span>
                <span class="hint">por {{ f.enviado_por_profile?.nome }} em {{ new Date(f.enviado_em).toLocaleString('pt-BR') }}</span>
              </li>
            </ul>
            <div v-else class="estado-vazio-card">
              <i class="pi pi-image"></i>
              <div>
                <strong>Nenhuma foto anexada</strong>
                <p>Adicione imagens de antes, durante ou depois para compor o histórico visual da OS.</p>
              </div>
            </div>
          </div>
        </TabPanel>

        <!-- ---------- ADICIONAIS ---------- -->
        <TabPanel value="adicionais">
          <div class="card">
            <div class="cabecalho-secao">
              <h3 style="margin:0">Adicionais</h3>
              <Button v-if="podeIdentificarAdicional && !osEncerrada" label="Identificar Necessidade" icon="pi pi-plus" size="small" @click="abrirNovoAdicional" />
            </div>
            <div v-if="osAdicionais.length === 0" class="estado-vazio-card">
              <i class="pi pi-plus-circle"></i>
              <div>
                <strong>Nenhum adicional identificado</strong>
                <p>Necessidades identificadas durante a execução aparecerão aqui, aguardando precificação e decisão do cliente.</p>
              </div>
            </div>
            <div v-for="adicional in osAdicionais" :key="adicional.id" class="cartao-adicional">
              <div class="cabecalho-secao">
                <div>
                  <strong>AD-{{ String(adicional.numero).padStart(3, '0') }}</strong>
                  <Tag :severity="severidadeStatusAdicional[adicional.status]" :value="adicional.status" style="margin-left:0.5rem" />
                  <span class="hint" style="margin-left:0.5rem">{{ adicional.motivo }}</span>
                </div>
                <div>
                  <span class="hint" style="margin-right:0.75rem">
                    Aprovado: <strong style="color:#4ade80">{{ formatarMoeda(valorAdicional(adicional, 'aprovado')) }}</strong>
                    &nbsp;Rejeitado: <strong style="color:#f87171">{{ formatarMoeda(valorAdicional(adicional, 'rejeitado')) }}</strong>
                  </span>
                  <Button v-if="podePrecificarAdicional && !osEncerrada" label="Incluir item" size="small" text @click="abrirIncluirItemAdicional(adicional)" />
                  <Button v-if="podeCancelarAdicional && adicional.status === 'aguardando_aprovacao'" label="Cancelar" size="small" text severity="danger" @click="abrirCancelarAdicional(adicional)" />
                </div>
              </div>
              <table class="tabela-itens-decisao" v-if="adicional.os_adicional_itens?.length">
                <thead>
                  <tr><th>Item</th><th>Valor</th><th>Decisão</th><th>Meio</th><th>Execução</th><th>Ação</th></tr>
                </thead>
                <tbody>
                  <tr v-for="item in adicional.os_adicional_itens" :key="item.id">
                    <td>{{ item.descricao }}<span v-if="item.peca"> — {{ item.peca.descricao }}</span> <span class="hint">({{ item.quantidade }}x)</span></td>
                    <td>{{ formatarMoeda(item.valor_total) }}</td>
                    <td><Tag :severity="tagDecisaoItemAdicional[item.status_aprovacao]" :value="item.status_aprovacao" /></td>
                    <td>{{ item.meio_aprovacao || '—' }}</td>
                    <td><Tag v-if="item.status_aprovacao === 'aprovado'" :severity="item.execucao_status === 'executado' ? 'success' : item.execucao_status === 'cancelado' ? 'danger' : 'warn'" :value="item.execucao_status" /><span v-else class="hint">—</span></td>
                    <td>
                      <template v-if="item.status_aprovacao === 'pendente' && podeDecidirAdicional">
                        <Button label="Decidir" size="small" @click="abrirDecisaoAdicional(item)" />
                      </template>
                      <template v-else-if="item.status_aprovacao === 'aprovado' && !item.peca_id && podeMarcarExecucao && !['executado', 'cancelado'].includes(item.execucao_status)">
                        <Button label="Executado" size="small" text @click="marcarItemAdicionalExecutado(item)" />
                        <Button label="Dispensar" size="small" text severity="danger" @click="abrirCancelarItem(item, 'adicional')" />
                      </template>
                      <span v-else class="hint">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </TabPanel>

        <!-- ---------- HISTÓRICO ---------- -->
        <TabPanel v-if="podeVerHistorico" value="historico">
          <div class="card">
            <h3>Histórico</h3>
            <p class="card-subtitulo">Linha do tempo com mudanças de status, apontamentos, fotos, adicionais e garantias desta OS.</p>
            <div v-if="eventosHistorico.length === 0" class="estado-vazio-card">
              <i class="pi pi-history"></i>
              <div>
                <strong>Sem eventos registrados</strong>
                <p>Assim que houver movimentação nesta OS, ela aparecerá aqui.</p>
              </div>
            </div>
            <ul v-else class="timeline">
              <li v-for="(ev, i) in eventosHistorico" :key="i" class="timeline-item">
                <div class="timeline-icone"><i :class="ev.icone"></i></div>
                <div class="timeline-corpo">
                  <span class="timeline-titulo">{{ ev.titulo }}</span>
                  <span v-if="ev.detalhe" class="hint">{{ ev.detalhe }}</span>
                  <span class="timeline-data">{{ new Date(ev.data).toLocaleString('pt-BR') }}</span>
                </div>
              </li>
            </ul>
          </div>
        </TabPanel>

      </TabPanels>
    </Tabs>

    <!-- ===== DIÁLOGOS (inalterados na lógica — só reposicionados) ===== -->

    <!-- GAR-005 (ETAPA 4 P1-A): escolher itens da própria OS ao abrir uma garantia -->
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

    <!-- ETAPA 6 (P1-C) — Decisão 3 (PEN-003): prazo manual -->
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

    <!-- ETAPA 6 (P1-C) — item 8 (EXE-003): remoção formal de executor -->
    <Dialog v-model:visible="dialogoRemoverExecutorAberto" modal header="Encerrar Participação do Executor" style="width: 420px">
      <p class="hint">Isto encerra a participação futura do executor nesta OS. O histórico de apontamento já registrado NUNCA é apagado.</p>
      <Textarea v-model="motivoRemocaoExecutor" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoRemoverExecutorAberto = false" />
        <Button label="Confirmar" severity="danger" @click="confirmarRemoverExecutor" />
      </template>
    </Dialog>

    <!-- CON-002 (ETAPA 4 P1-A): motivo obrigatório para dispensar item aprovado (orçamento ou adicional) -->
    <Dialog v-model:visible="dialogoCancelarItemAberto" modal header="Dispensar item aprovado" style="width: 420px">
      <p class="hint">Cancelar um item aprovado exige motivo — fica registrado na trilha de auditoria.</p>
      <Textarea v-model="motivoCancelamento" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelarItemAberto = false" />
        <Button label="Confirmar dispensa" severity="danger" @click="confirmarCancelarItem" />
      </template>
    </Dialog>

    <!-- ETAPA 5 (P1-B) — ADC-001: identificar necessidade (executor/encarregado/admin) -->
    <Dialog v-model:visible="dialogoNovoAdicionalAberto" modal header="Identificar Necessidade de Adicional" style="width: 460px">
      <p class="hint">Descreva o que foi identificado durante a execução. O encarregado/admin técnico vai precificar e enviar para decisão do cliente em seguida.</p>
      <Textarea v-model="formNovoAdicional.motivo" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovoAdicionalAberto = false" />
        <Button label="Registrar" @click="criarAdicional" />
      </template>
    </Dialog>

    <!-- ETAPA 5 (P1-B) — encarregado/admin precifica (peça opcional, quantidade, valor) -->
    <Dialog v-model:visible="dialogoItemAdicionalAberto" modal header="Incluir Item Precificado" style="width: 480px">
      <div class="form-campo">
        <label>Peça (opcional — vazio = mão de obra)</label>
        <Select v-model="formItemAdicional.peca_id" :options="pecas" optionLabel="descricao" optionValue="id" filter showClear placeholder="Peça" @update:modelValue="selecionouPecaAdicional" />
      </div>
      <div class="form-campo">
        <label>Descrição</label>
        <InputText v-model="formItemAdicional.descricao" />
      </div>
      <div class="form-linha">
        <InputNumber v-model="formItemAdicional.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" />
        <InputNumber v-model="formItemAdicional.valor_unitario" placeholder="Valor Unit." mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Justificativa (opcional)</label>
        <Textarea v-model="formItemAdicional.justificativa" rows="2" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoItemAdicionalAberto = false" />
        <Button label="Incluir" @click="incluirItemAdicional" />
      </template>
    </Dialog>

    <!-- ETAPA 5 (P1-B) — ADC-003/004 + APR-004/005/006: decisão do item de adicional -->
    <Dialog v-model:visible="dialogoDecisaoAdicionalAberto" modal header="Decisão do Cliente — Item de Adicional" style="width: 460px">
      <div class="form-campo">
        <label>Meio de aprovação</label>
        <Select v-model="formDecisaoAdicional.meio_aprovacao" :options="meiosAprovacaoAdicional" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo">
        <label>Autorizado por (nome do cliente/responsável)</label>
        <InputText v-model="formDecisaoAdicional.autorizado_por_nome" />
      </div>
      <div class="form-campo" v-if="formDecisaoAdicional.meio_aprovacao === 'email'">
        <label>Comprovante (evidência do e-mail)</label>
        <input type="file" @change="onArquivoDecisaoAdicionalSelecionado" accept="image/*,application/pdf,.eml,.msg" />
      </div>
      <div class="form-campo" v-if="formDecisaoAdicional.meio_aprovacao === 'verbal_documentado'">
        <label>Observação (obrigatória)</label>
        <Textarea v-model="formDecisaoAdicional.observacao" rows="2" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoDecisaoAdicionalAberto = false" />
        <Button label="Rejeitar" severity="danger" text @click="decidirItemAdicional('rejeitado')" />
        <Button label="Aprovar" severity="success" @click="decidirItemAdicional('aprovado')" />
      </template>
    </Dialog>

    <!-- ETAPA 5 (P1-B) — cancelamento formal do adicional (header sem itens decididos ainda) -->
    <Dialog v-model:visible="dialogoCancelarAdicionalAberto" modal header="Cancelar Adicional" style="width: 420px">
      <p class="hint">Cancela o adicional inteiro (itens ainda pendentes viram rejeitados) — fica registrado na trilha de auditoria.</p>
      <Textarea v-model="motivoCancelamentoAdicional" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelarAdicionalAberto = false" />
        <Button label="Confirmar cancelamento" severity="danger" @click="confirmarCancelarAdicional" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.estado-carregando {
  color: var(--text-muted);
  padding: 40px 0;
}

/* ===== Cabeçalho ===== */
.cabecalho-os {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 20px;
  flex-wrap: wrap;
  margin-bottom: 18px;
}
.cabecalho-titulo-linha {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-bottom: 12px;
}
.cabecalho-titulo-linha h2 {
  margin: 0;
  font-size: 1.3rem;
  color: var(--text-heading);
}
.cabecalho-info-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 14px 24px;
  max-width: 640px;
}
.info-bloco {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.info-label {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  color: var(--text-muted);
}
.info-valor {
  font-size: 13.5px;
  color: var(--text-body);
  font-weight: 600;
}
.info-valor-linha {
  display: flex;
  align-items: center;
  gap: 4px;
}
.cabecalho-direita {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 12px;
}
.status-tag-grande {
  font-size: 0.95rem;
  padding: 6px 14px;
}
.cabecalho-acoes {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  justify-content: flex-end;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}

/* ===== Barra de etapas ===== */
.barra-etapas {
  display: flex;
  align-items: center;
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 18px 20px;
  margin-bottom: 18px;
  overflow-x: auto;
}
.etapa {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  min-width: 84px;
  position: relative;
}
.etapa-icone {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-hover);
  border: 2px solid var(--border-panel);
  color: var(--text-faint);
  font-size: 14px;
}
.etapa-concluida .etapa-icone {
  background: var(--success-bg);
  border-color: var(--success);
  color: var(--success);
}
.etapa-atual .etapa-icone {
  background: var(--accent-soft-bg);
  border-color: var(--accent-1);
  color: var(--accent-text);
}
.etapa-label {
  font-size: 11.5px;
  color: var(--text-muted);
  white-space: nowrap;
}
.etapa-atual .etapa-label {
  color: var(--text-heading);
  font-weight: 700;
}
.etapa-selo {
  position: absolute;
  top: -8px;
  right: -12px;
  font-size: 0.6rem;
}
.etapa-linha {
  flex: 1;
  height: 2px;
  background: var(--border-panel);
  margin: 0 4px;
  margin-bottom: 22px;
  min-width: 20px;
}
.etapa-linha-concluida {
  background: var(--success);
}
.badge-terminal {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  border-radius: var(--card-radius);
  font-weight: 700;
  font-size: 13.5px;
  margin-bottom: 18px;
}
.badge-cancelada {
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger);
}

/* ===== Abas ===== */
.tabs-os {
  margin-top: 4px;
}

/* ===== Cards (mesmo padrão de DashboardView.vue) ===== */
.card {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 20px;
  margin-bottom: 14px;
}
.card h3 {
  margin: 0 0 14px;
  font-size: 13.5px;
  font-weight: 700;
  color: var(--text-heading);
}
.card-subtitulo {
  margin: -8px 0 14px;
  font-size: 12px;
  color: var(--text-muted);
}

/* ===== Estado vazio (dentro de card) ===== */
.estado-vazio-card {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 16px 4px;
  color: var(--text-faint);
}
.estado-vazio-card i {
  font-size: 22px;
  margin-top: 2px;
}
.estado-vazio-card strong {
  display: block;
  color: var(--text-secondary);
  font-size: 13px;
  margin-bottom: 2px;
}
.estado-vazio-card p {
  margin: 0;
  font-size: 12.5px;
  line-height: 1.4;
}

/* ===== Resumo (grid de números) ===== */
.resumo-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 14px;
}
.resumo-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.resumo-valor {
  font-size: 19px;
  font-weight: 800;
  color: var(--text-heading);
}
.resumo-label {
  font-size: 11.5px;
  color: var(--text-muted);
}

/* ===== Histórico (timeline) ===== */
.timeline {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
}
.timeline-item {
  display: flex;
  gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid var(--border-row);
}
.timeline-item:last-child {
  border-bottom: none;
}
.timeline-icone {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--surface-hover);
  color: var(--accent-text);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  font-size: 12px;
}
.timeline-corpo {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.timeline-titulo {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-body);
}
.timeline-data {
  font-size: 11px;
  color: var(--text-faint);
}

/* ===== Blocos reaproveitados do arquivo original ===== */
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.75rem;
  flex-wrap: wrap;
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
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
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
.cabecalho-secao {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 10px;
}
.cartao-adicional {
  border: 1px solid var(--border-panel);
  border-radius: 10px;
  padding: 0.75rem 1rem;
  margin-top: 0.75rem;
  background: var(--surface-hover);
}
.tabela-itens-decisao {
  width: 100%;
  border-collapse: collapse;
  margin-top: 0.75rem;
}
.tabela-itens-decisao th,
.tabela-itens-decisao td {
  text-align: left;
  padding: 0.4rem 0.5rem;
  border-bottom: 1px solid var(--border-row);
  font-size: 0.85rem;
  vertical-align: middle;
  color: var(--text-body);
}
.tabela-itens-decisao th {
  color: var(--text-table-header);
  font-weight: 600;
  font-size: 0.75rem;
  text-transform: uppercase;
}

/* ===== Responsividade ===== */
@media (max-width: 760px) {
  .cabecalho-os {
    flex-direction: column;
  }
  .cabecalho-direita {
    align-items: flex-start;
    width: 100%;
  }
  .cabecalho-acoes {
    justify-content: flex-start;
    width: 100%;
  }
  .barra-etapas {
    justify-content: flex-start;
  }
  .form-linha {
    flex-direction: column;
    align-items: stretch;
  }
  .form-linha > * {
    width: 100%;
  }
}
</style>
