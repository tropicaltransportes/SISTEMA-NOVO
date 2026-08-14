<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Textarea from 'primevue/textarea'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import Menu from 'primevue/menu'
import { STATUS_ORCAMENTO, STATUS_ITEM_ORCAMENTO } from '../../constants/statusVisual'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'administrador_tecnico'].includes(auth.perfil)
const podeAutorizar = () => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const orcamentos = ref([])
const veiculos = ref([])
const pecas = ref([])
const carregando = ref(true)
const erro = ref(false)
const filtro = ref('')
const temFiltroAtivo = computed(() => filtro.value.trim() !== '')

// ETAPA 5 (P1-B) — APR-002: totais calculados a partir do status_aprovacao
// de CADA item (valor originalmente orçado = soma de todos os itens, igual
// a valor_total já sempre foi; aprovado/rejeitado = soma filtrada por
// decisão do item).
function valorAprovado(orc) {
  return (orc.orcamento_itens ?? []).filter((i) => i.status_aprovacao === 'aprovado').reduce((s, i) => s + i.quantidade * i.valor_unitario, 0)
}
function valorRejeitado(orc) {
  return (orc.orcamento_itens ?? []).filter((i) => i.status_aprovacao === 'rejeitado').reduce((s, i) => s + i.quantidade * i.valor_unitario, 0)
}
function temItemPendente(orc) {
  return (orc.orcamento_itens ?? []).some((i) => i.status_aprovacao === 'pendente')
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(dataStr) {
  if (!dataStr) return '—'
  return new Date(dataStr).toLocaleDateString('pt-BR')
}
// ETAPA UX-ORCAMENTOS-01 — item 8: mesma fórmula usada no backend para o
// número legível (rpc_dados_pdf_orcamento, supabase/migrations/20260814111000_p1c_relatorios.sql:33
// — 'ORC-' || substr(o.id::text, 1, 8) || '-V' || o.versao). Não é um
// número novo: é o mesmo, calculado aqui com id/versao que a listagem já
// busca, para não precisar chamar a RPC (feita para 1 orçamento) por linha.
function numeroLegivel(orc) {
  return `ORC-${orc.id.slice(0, 8)}-V${orc.versao}`
}

async function carregar() {
  carregando.value = true
  erro.value = false
  const [respOrc, respVeiculos, respPecas] = await Promise.all([
    supabase
      .from('orcamentos')
      .select(
        'id, versao, status, valor_total, autorizado_por_nome, comprovante_path, criado_em, solicitacao_id, veiculo:veiculos(id, placa, prefixo, cliente_id), cliente:clientes(id, nome, tipo), orcamento_itens(id, peca_id, descricao, quantidade, valor_unitario, status_aprovacao, meio_aprovacao, autorizado_por_nome, autorizado_em, registrado_por, comprovante_path, observacao), orcamento_acrescimos(id, valor_acrescimo, justificativa, criado_em)'
      )
      .order('criado_em', { ascending: false }),
    supabase.from('veiculos').select('id, placa, prefixo, cliente_id, cliente:clientes(nome, tipo)').is('deleted_at', null).order('placa'),
    supabase.from('pecas').select('id, sku, descricao').is('deleted_at', null).order('descricao'),
  ])

  if (respOrc.error) {
    erro.value = true
    toast.add({ severity: 'error', summary: 'Erro ao carregar orçamentos', detail: respOrc.error.message, life: 5000 })
  } else {
    orcamentos.value = (respOrc.data ?? []).map((o) => ({ ...o, numero_legivel: numeroLegivel(o) }))
  }
  veiculos.value = respVeiculos.data ?? []
  pecas.value = respPecas.data ?? []
  carregando.value = false
}

// ---------- Criação (rascunho) ----------
const dialogoNovoAberto = ref(false)
const salvandoNovo = ref(false)
const formNovo = ref({ veiculo_id: null, solicitacao_id: null })
// ORC-016: chave de idempotência gerada uma única vez por abertura do
// formulário e reaproveitada em qualquer retry (clique duplo ou retry de
// rede) — protegida de verdade pelo índice único parcial
// ux_orcamentos_client_request_id no backend (não depende só do botão
// desabilitado, que não segura um retry de rede real). Só é trocada quando
// o diálogo é reaberto do zero (abrirNovo) ou depois de sucesso.
let clientRequestId = crypto.randomUUID()

function abrirNovo() {
  formNovo.value = {
    veiculo_id: route.query.veiculo_id || null,
    solicitacao_id: route.query.solicitacao_id || null,
  }
  clientRequestId = crypto.randomUUID()
  dialogoNovoAberto.value = true
}

// ETAPA UX-ORCAMENTOS-01 — item 17: mostra o cliente já derivado do
// veículo escolhido, só como informação (mesma lógica de criarRascunho,
// que já usa veiculo.cliente_id) — não cria vínculo novo, só exibe o que
// já seria usado ao salvar.
const veiculoSelecionadoNovo = computed(() => veiculos.value.find((v) => v.id === formNovo.value.veiculo_id) ?? null)

async function criarRascunho() {
  if (!formNovo.value.veiculo_id) {
    toast.add({ severity: 'warn', summary: 'Selecione o veículo', life: 4000 })
    return
  }
  if (salvandoNovo.value) return // trava extra de UI contra duplo clique; a garantia real é o backend
  const veiculo = veiculos.value.find((v) => v.id === formNovo.value.veiculo_id)
  salvandoNovo.value = true
  const { data, error } = await supabase
    .from('orcamentos')
    .insert({
      veiculo_id: veiculo.id,
      cliente_id: veiculo.cliente_id,
      solicitacao_id: formNovo.value.solicitacao_id || null,
      criado_por: auth.profile.id,
      client_request_id: clientRequestId,
    })
    .select('id')
    .single()
  salvandoNovo.value = false
  if (error) {
    if (error.code === '23505') {
      // Retry/duplo clique real: a 1ª tentativa (desta ou de outra aba/requisição
      // concorrente) já criou o orçamento com esta chave — busca o registro
      // existente em vez de mostrar erro ou deixar o usuário tentar de novo.
      const { data: existente } = await supabase
        .from('orcamentos')
        .select('id')
        .eq('client_request_id', clientRequestId)
        .single()
      if (existente) {
        toast.add({ severity: 'info', summary: 'Orçamento já criado', detail: 'Esta submissão já havia sido processada.', life: 4000 })
        dialogoNovoAberto.value = false
        await carregar()
        abrirItens(orcamentos.value.find((o) => o.id === existente.id))
        return
      }
    }
    toast.add({ severity: 'error', summary: 'Erro ao criar orçamento', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Orçamento criado em rascunho', life: 3000 })
  dialogoNovoAberto.value = false
  clientRequestId = crypto.randomUUID()
  if (route.query.solicitacao_id) router.replace({ path: '/orcamentos' })
  await carregar()
  abrirItens(orcamentos.value.find((o) => o.id === data.id))
}

// ---------- Itens (só em rascunho) ----------
const dialogoItensAberto = ref(false)
const orcamentoAtual = ref(null)
const itens = ref([])
const salvandoItens = ref(false)

function abrirItens(orc) {
  orcamentoAtual.value = orc
  itens.value = orc.orcamento_itens.map((i) => ({ id: i.id, peca_id: i.peca_id, descricao: i.descricao, quantidade: i.quantidade, valor_unitario: i.valor_unitario }))
  resetarFormNovoItem()
  dialogoItensAberto.value = true
}

// ETAPA UX-ORCAMENTOS-01 — item 18: substitui as N linhas todas
// editáveis-inline por um formulário único de "adicionar item" + tabela de
// itens já incluídos (só remoção). O array `itens` (mesmo shape de antes:
// {id, peca_id, descricao, quantidade, valor_unitario}) e `salvarItens()`
// continuam idênticos — é só a interação de montar esse array que mudou.
const formNovoItem = ref({ tipo: 'peca', peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0 })
function resetarFormNovoItem() {
  formNovoItem.value = { tipo: 'peca', peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0 }
}
function selecionouPecaNovoItem() {
  const p = pecas.value.find((x) => x.id === formNovoItem.value.peca_id)
  if (p && !formNovoItem.value.descricao) formNovoItem.value.descricao = p.descricao
}
function adicionarItemDoFormulario() {
  const f = formNovoItem.value
  const descricao = f.descricao || (f.tipo === 'mao_obra' ? 'Mão de obra' : '')
  if (!descricao || !f.quantidade || f.quantidade <= 0) {
    toast.add({ severity: 'warn', summary: 'Preencha descrição e quantidade (maior que zero) antes de adicionar', life: 4000 })
    return
  }
  itens.value.push({
    id: null,
    peca_id: f.tipo === 'peca' ? f.peca_id || null : null,
    descricao,
    quantidade: f.quantidade,
    valor_unitario: f.valor_unitario ?? 0,
  })
  resetarFormNovoItem()
}
function removerItem(index) {
  itens.value.splice(index, 1)
}
const totalItensAtual = computed(() => itens.value.reduce((s, i) => s + i.quantidade * i.valor_unitario, 0))
function tipoItem(item) {
  return item.peca_id ? 'Peça' : 'Mão de obra'
}

async function salvarItens() {
  if (itens.value.length === 0 || itens.value.some((i) => !i.descricao || i.quantidade <= 0)) {
    toast.add({ severity: 'warn', summary: 'Revise os itens', detail: 'Cada item precisa de descrição e quantidade maior que zero.', life: 4000 })
    return
  }
  salvandoItens.value = true
  await supabase.from('orcamento_itens').delete().eq('orcamento_id', orcamentoAtual.value.id)
  const payload = itens.value.map((i) => ({
    orcamento_id: orcamentoAtual.value.id,
    peca_id: i.peca_id || null,
    descricao: i.descricao,
    quantidade: i.quantidade,
    valor_unitario: i.valor_unitario,
  }))
  const { error } = await supabase.from('orcamento_itens').insert(payload)
  salvandoItens.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar itens', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Itens salvos', life: 3000 })
  dialogoItensAberto.value = false
  await carregar()
}

// ---------- Transições ----------
async function enviar(orc) {
  const { error } = await supabase.rpc('rpc_enviar_orcamento', { p_orcamento_id: orc.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao enviar', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Orçamento enviado', life: 3000 })
  await carregar()
}

function confirmarAprovacao(orc) {
  confirm.require({
    message: `Aprovar o orçamento (v${orc.versao}) de ${formatarMoeda(orc.valor_total)}?`,
    header: 'Confirmar aprovação',
    icon: 'pi pi-check-circle',
    acceptLabel: 'Aprovar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_aprovar_orcamento', { p_orcamento_id: orc.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao aprovar', detail: error.message, life: 6000 })
        return
      }
      toast.add({ severity: 'success', summary: 'Orçamento aprovado', life: 3000 })
      await carregar()
    },
  })
}

function confirmarRejeicao(orc) {
  confirm.require({
    message: 'Rejeitar este orçamento?',
    header: 'Confirmar rejeição',
    icon: 'pi pi-times-circle',
    acceptLabel: 'Rejeitar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_rejeitar_orcamento', { p_orcamento_id: orc.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao rejeitar', detail: error.message, life: 6000 })
        return
      }
      await carregar()
    },
  })
}

async function novaVersao(orc) {
  const { data, error } = await supabase.rpc('rpc_criar_versao_orcamento', { p_orcamento_id: orc.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao criar nova versão', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Nova versão criada em rascunho', life: 3000 })
  await carregar()
  abrirItens(orcamentos.value.find((o) => o.id === data))
}

function criarOs(orc) {
  router.push({
    path: '/os',
    query: { orcamento_id: orc.id, veiculo_id: orc.veiculo.id, cliente_id: orc.cliente.id, solicitacao_id: orc.solicitacao_id || '' },
  })
}

// ---------- Autorização (comprovante, cliente externo) ----------
const dialogoAutorizacaoAberto = ref(false)
const salvandoAutorizacao = ref(false)
const formAutorizacao = ref({ autorizado_por_nome: '', arquivo: null })

function abrirAutorizacao(orc) {
  orcamentoAtual.value = orc
  formAutorizacao.value = { autorizado_por_nome: orc.autorizado_por_nome || '', arquivo: null }
  dialogoAutorizacaoAberto.value = true
}

function onArquivoSelecionado(event) {
  formAutorizacao.value.arquivo = event.target.files[0] || null
}

async function salvarAutorizacao() {
  const orc = orcamentoAtual.value
  const ehExterno = orc.cliente?.tipo === 'externo'
  if (ehExterno && (!formAutorizacao.value.autorizado_por_nome || (!formAutorizacao.value.arquivo && !orc.comprovante_path))) {
    toast.add({ severity: 'warn', summary: 'Cliente externo exige nome do autorizador e comprovante', life: 5000 })
    return
  }
  salvandoAutorizacao.value = true
  let caminho = orc.comprovante_path || null
  if (formAutorizacao.value.arquivo) {
    const arquivo = formAutorizacao.value.arquivo
    const caminhoDestino = `${orc.id}/${Date.now()}-${arquivo.name}`
    const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, arquivo)
    if (erroUpload) {
      salvandoAutorizacao.value = false
      toast.add({ severity: 'error', summary: 'Erro ao enviar comprovante', detail: erroUpload.message, life: 6000 })
      return
    }
    caminho = caminhoDestino
  }

  const { error } = await supabase.rpc('rpc_registrar_autorizacao_orcamento', {
    p_orcamento_id: orc.id,
    p_autorizado_por_nome: formAutorizacao.value.autorizado_por_nome || null,
    p_comprovante_path: caminho,
  })
  salvandoAutorizacao.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar autorização', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Autorização registrada', life: 3000 })
  dialogoAutorizacaoAberto.value = false
  await carregar()
}

// ---------- Acréscimo (pós-aprovação) ----------
const dialogoAcrescimoAberto = ref(false)
const salvandoAcrescimo = ref(false)
const formAcrescimo = ref({ valor_acrescimo: 0, justificativa: '' })

function abrirAcrescimo(orc) {
  orcamentoAtual.value = orc
  formAcrescimo.value = { valor_acrescimo: 0, justificativa: '' }
  dialogoAcrescimoAberto.value = true
}

async function salvarAcrescimo() {
  if (!formAcrescimo.value.valor_acrescimo || !formAcrescimo.value.justificativa) {
    toast.add({ severity: 'warn', summary: 'Informe valor e justificativa', life: 4000 })
    return
  }
  salvandoAcrescimo.value = true
  const { error } = await supabase.rpc('rpc_registrar_acrescimo', {
    p_orcamento_id: orcamentoAtual.value.id,
    p_valor_acrescimo: formAcrescimo.value.valor_acrescimo,
    p_justificativa: formAcrescimo.value.justificativa,
  })
  salvandoAcrescimo.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Acréscimo recusado', detail: error.message, life: 8000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Acréscimo registrado', life: 3000 })
  dialogoAcrescimoAberto.value = false
  await carregar()
}

// ---------- Desconto (ETAPA 6/P1-C — Decisão 7: ORC-007/008/FIN-003/PEN-007) ----------
// Só em rascunho — depois de enviado/decidido, exige nova versão (o backend
// bloqueia explicitamente; a UI só espelha essa janela).
const dialogoDescontoAberto = ref(false)
const salvandoDesconto = ref(false)
const formDesconto = ref({ modo: 'percentual', percentual: null, valor: null, motivo: '' })

function abrirDesconto(orc) {
  orcamentoAtual.value = orc
  formDesconto.value = { modo: 'percentual', percentual: null, valor: null, motivo: '' }
  dialogoDescontoAberto.value = true
}

function irParaPdf(orc) {
  router.push('/orcamentos/' + orc.id + '/pdf')
}

async function salvarDesconto() {
  const f = formDesconto.value
  if (f.modo === 'percentual' && (f.percentual === null || f.percentual === undefined)) {
    toast.add({ severity: 'warn', summary: 'Informe o percentual de desconto', life: 4000 })
    return
  }
  if (f.modo === 'valor' && (f.valor === null || f.valor === undefined)) {
    toast.add({ severity: 'warn', summary: 'Informe o valor de desconto', life: 4000 })
    return
  }
  if (!f.motivo || f.motivo.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Motivo do desconto é obrigatório (mín. 5 caracteres)', life: 5000 })
    return
  }
  salvandoDesconto.value = true
  const { error } = await supabase.rpc('rpc_aplicar_desconto_orcamento', {
    p_orcamento_id: orcamentoAtual.value.id,
    p_percentual: f.modo === 'percentual' ? f.percentual : null,
    p_valor: f.modo === 'valor' ? f.valor : null,
    p_motivo: f.motivo,
  })
  salvandoDesconto.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Desconto recusado', detail: error.message, life: 8000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Desconto aplicado', life: 3000 })
  dialogoDescontoAberto.value = false
  await carregar()
}

// ---------- Decisão por item (ETAPA 5/P1-B — APR-002/004/005/006) ----------
// Aprovação deixou de ser tudo-ou-nada: cada item tem sua própria decisão
// (pendente/aprovado/rejeitado), com meio de aprovação estruturado
// (sistema/email/verbal_documentado) — reflexo direto de
// rpc_decidir_item_orcamento no backend, que é a autoridade real (este
// diálogo só evita oferecer uma decisão que o backend recusaria, ex.: item
// já decidido).
const dialogoDecisaoAberto = ref(false)
const meiosAprovacao = [
  { label: 'Sistema (botão)', value: 'sistema' },
  { label: 'E-mail (evidência obrigatória)', value: 'email' },
  { label: 'Verbal documentado (observação obrigatória)', value: 'verbal_documentado' },
]
const formDecisao = ref({ autorizado_por_nome: '', meio_aprovacao: 'sistema', observacao: '', arquivo: null })
const decidindoItemId = ref(null)

function abrirDecisao(orc) {
  orcamentoAtual.value = orc
  formDecisao.value = { autorizado_por_nome: orc.autorizado_por_nome || '', meio_aprovacao: 'sistema', observacao: '', arquivo: null }
  dialogoDecisaoAberto.value = true
}

function onArquivoDecisaoSelecionado(event) {
  formDecisao.value.arquivo = event.target.files[0] || null
}

async function decidirItem(item, decisao) {
  if (!formDecisao.value.autorizado_por_nome || formDecisao.value.autorizado_por_nome.trim().length < 2) {
    toast.add({ severity: 'warn', summary: 'Informe o nome de quem autorizou (cliente/responsável)', life: 5000 })
    return
  }
  if (formDecisao.value.meio_aprovacao === 'verbal_documentado' && formDecisao.value.observacao.trim().length < 10) {
    toast.add({ severity: 'warn', summary: 'Aprovação verbal documentada exige observação (mín. 10 caracteres)', life: 5000 })
    return
  }
  let comprovantePath = null
  if (formDecisao.value.meio_aprovacao === 'email') {
    if (!formDecisao.value.arquivo) {
      toast.add({ severity: 'warn', summary: 'Aprovação via e-mail exige o comprovante (evidência) anexado', life: 5000 })
      return
    }
    const caminhoDestino = `${orcamentoAtual.value.id}/item-${item.id}-${Date.now()}-${formDecisao.value.arquivo.name}`
    const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, formDecisao.value.arquivo)
    if (erroUpload) {
      toast.add({ severity: 'error', summary: 'Erro ao enviar comprovante', detail: erroUpload.message, life: 6000 })
      return
    }
    comprovantePath = caminhoDestino
  }

  decidindoItemId.value = item.id
  const { error } = await supabase.rpc('rpc_decidir_item_orcamento', {
    p_orcamento_item_id: item.id,
    p_decisao: decisao,
    p_meio_aprovacao: formDecisao.value.meio_aprovacao,
    p_autorizado_por_nome: formDecisao.value.autorizado_por_nome,
    p_comprovante_path: comprovantePath,
    p_observacao: formDecisao.value.observacao || null,
  })
  decidindoItemId.value = null
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar decisão', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: `Item ${decisao}`, life: 3000 })
  await carregar()
  // Reabre o mesmo orçamento atualizado (os itens já decididos somem da
  // lista de pendentes, o diálogo continua útil para os itens restantes).
  const atualizado = orcamentos.value.find((o) => o.id === orcamentoAtual.value.id)
  if (atualizado) orcamentoAtual.value = atualizado
  else dialogoDecisaoAberto.value = false
}

// ETAPA UX-ORCAMENTOS-01 — item 12: reduz a coluna Ações a 1-2 botões
// primários visíveis por status (preservados como já eram) + um menu de
// três pontos com o resto — mesmas condições de v-if de antes, só
// redistribuídas entre "botão" e "item de menu". Nenhuma ação nova, nenhuma
// condição alterada.
function construirMenuAcoes(orc) {
  if (!orc) return []
  const lista = []
  if (orc.status === 'rascunho' && podeGerir()) {
    lista.push({ label: 'Aplicar desconto', icon: 'pi pi-percentage', command: () => abrirDesconto(orc) })
  }
  if (orc.status === 'enviado') {
    if (podeAutorizar()) {
      lista.push({ label: 'Registrar autorização', icon: 'pi pi-verified', command: () => abrirAutorizacao(orc) })
    }
    if (podeGerir()) {
      lista.push({ label: 'Aprovar tudo', icon: 'pi pi-check-circle', command: () => confirmarAprovacao(orc) })
      lista.push({ label: 'Rejeitar tudo', icon: 'pi pi-times-circle', command: () => confirmarRejeicao(orc) })
    }
  }
  if (['aprovado', 'parcialmente_aprovado'].includes(orc.status) && podeGerir()) {
    lista.push({ label: 'Ver decisões', icon: 'pi pi-eye', command: () => abrirDecisao(orc) })
    if (orc.status === 'aprovado') {
      lista.push({ label: 'Registrar acréscimo', icon: 'pi pi-plus-circle', command: () => abrirAcrescimo(orc) })
    }
  }
  if (['enviado', 'aprovado', 'parcialmente_aprovado', 'rejeitado'].includes(orc.status) && podeGerir()) {
    lista.push({ label: 'Nova versão', icon: 'pi pi-copy', command: () => novaVersao(orc) })
  }
  return lista
}

const menuAcoes = ref()
const orcamentoMenuAtual = ref(null)
const itensMenuAcoesAtual = computed(() => construirMenuAcoes(orcamentoMenuAtual.value))
function abrirMenuAcoes(event, orc) {
  orcamentoMenuAtual.value = orc
  menuAcoes.value.toggle(event)
}

onMounted(() => {
  carregar().then(() => {
    if (route.query.veiculo_id && !route.query.orcamento_id) abrirNovo()
  })
})
</script>

<template>
  <div>
    <div class="pagina-cabecalho-linha">
      <div class="pagina-cabecalho">
        <h1 class="pagina-titulo">Orçamentos</h1>
        <p class="pagina-subtitulo">Gerencie os orçamentos emitidos pela oficina.</p>
      </div>
      <Button v-if="podeGerir()" label="Novo Orçamento" icon="pi pi-plus" class="btn-gradiente" @click="abrirNovo" />
    </div>

    <div class="cabecalho">
      <IconField class="busca">
        <InputIcon class="pi pi-search" />
        <InputText v-model="filtro" placeholder="Buscar por cliente, veículo, número ou placa" />
      </IconField>
    </div>

    <div class="panel">
      <DataTable
        :value="orcamentos"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['cliente.nome', 'veiculo.placa', 'numero_legivel']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        paginatorTemplate="CurrentPageReport FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink"
        currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} orçamentos"
      >
        <Column header="Nº Orçamento" style="width: 150px">
          <template #body="{ data }"><span class="placa-destaque">{{ data.numero_legivel }}</span></template>
        </Column>
        <Column header="Cliente">
          <template #body="{ data }">{{ data.cliente?.nome || '—' }}</template>
        </Column>
        <Column header="Veículo">
          <template #body="{ data }">
            <span class="placa-destaque">{{ data.veiculo?.placa || '—' }}</span>
            <span v-if="data.veiculo?.prefixo" class="prefixo-inline">({{ data.veiculo.prefixo }})</span>
          </template>
        </Column>
        <Column header="Versão" style="width: 80px" bodyClass="col-numero">
          <template #body="{ data }">V{{ data.versao }}</template>
        </Column>
        <Column header="Emitido em" style="width: 110px">
          <template #body="{ data }">{{ formatarData(data.criado_em) }}</template>
        </Column>
        <Column header="Status">
          <template #body="{ data }">
            <Tag :severity="STATUS_ORCAMENTO[data.status]?.severidade" :value="STATUS_ORCAMENTO[data.status]?.label ?? data.status" />
          </template>
        </Column>
        <Column header="Valor Original" bodyClass="col-valor">
          <template #body="{ data }"><span class="valor valor-original">{{ formatarMoeda(data.valor_total) }}</span></template>
        </Column>
        <!-- ETAPA 5 (P1-B) — APR-002: totais por decisão de item, não mais só o valor_total do orçamento inteiro. -->
        <Column header="Valor Aprovado" bodyClass="col-valor">
          <template #body="{ data }"><span class="valor valor-aprovado">{{ formatarMoeda(valorAprovado(data)) }}</span></template>
        </Column>
        <Column header="Valor Rejeitado" bodyClass="col-valor">
          <template #body="{ data }"><span class="valor valor-rejeitado">{{ formatarMoeda(valorRejeitado(data)) }}</span></template>
        </Column>
        <Column header="Acréscimos" bodyClass="col-valor">
          <template #body="{ data }">
            <span class="valor valor-acrescimo">{{ formatarMoeda(data.orcamento_acrescimos.reduce((s, a) => s + a.valor_acrescimo, 0)) }}</span>
          </template>
        </Column>
        <Column header="Ações" style="width: 210px">
          <template #body="{ data }">
            <div class="acoes-linha">
              <template v-if="data.status === 'rascunho' && podeGerir()">
                <Button label="Itens" size="small" text @click="abrirItens(data)" />
                <Button label="Enviar" icon="pi pi-send" size="small" @click="enviar(data)" />
              </template>
              <Button
                v-if="data.status === 'enviado' && podeAutorizar()"
                label="Decidir Itens"
                icon="pi pi-check-square"
                size="small"
                severity="success"
                @click="abrirDecisao(data)"
              />
              <Button
                v-if="['aprovado', 'parcialmente_aprovado'].includes(data.status) && podeGerir()"
                label="Criar OS"
                size="small"
                severity="success"
                @click="criarOs(data)"
              />
              <Button icon="pi pi-file-pdf" text rounded size="small" aria-label="PDF" @click="irParaPdf(data)" />
              <Button
                v-if="construirMenuAcoes(data).length"
                icon="pi pi-ellipsis-v"
                text
                rounded
                size="small"
                aria-label="Mais ações"
                @click="abrirMenuAcoes($event, data)"
              />
            </div>
          </template>
        </Column>

        <template #empty>
          <div class="estado-vazio-tabela">
            <i class="pi" :class="erro ? 'pi-exclamation-triangle' : 'pi-file-edit'"></i>
            <p v-if="erro">Não foi possível carregar os orçamentos.</p>
            <p v-else-if="temFiltroAtivo">Nenhum orçamento corresponde aos critérios informados.</p>
            <p v-else>Nenhum orçamento encontrado.</p>
            <Button v-if="!erro && podeGerir()" label="Novo Orçamento" icon="pi pi-plus" size="small" @click="abrirNovo" />
          </div>
        </template>
      </DataTable>
    </div>

    <Menu ref="menuAcoes" :model="itensMenuAcoesAtual" :popup="true" />

    <!-- Novo orçamento -->
    <Dialog v-model:visible="dialogoNovoAberto" modal header="Novo Orçamento" style="width: 440px">
      <div class="bloco-form">
        <span class="bloco-form-titulo">Veículo</span>
        <div class="form-campo">
          <Select
            v-model="formNovo.veiculo_id"
            :options="veiculos"
            optionLabel="placa"
            optionValue="id"
            filter
            placeholder="Selecione o veículo"
            :disabled="!!route.query.veiculo_id"
          />
          <p v-if="veiculoSelecionadoNovo?.cliente?.nome" class="info-derivada">
            Cliente: <strong>{{ veiculoSelecionadoNovo.cliente.nome }}</strong>
          </p>
        </div>
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovoAberto = false" />
        <Button label="Criar Rascunho" :loading="salvandoNovo" @click="criarRascunho" />
      </template>
    </Dialog>

    <!-- Itens -->
    <Dialog v-model:visible="dialogoItensAberto" modal header="Itens do Orçamento" style="width: 92vw; max-width: 820px">
      <div class="bloco-form">
        <span class="bloco-form-titulo">Adicionar item</span>
        <div class="item-add-grid">
          <Select
            v-model="formNovoItem.tipo"
            :options="[{ label: 'Peça', value: 'peca' }, { label: 'Mão de obra', value: 'mao_obra' }]"
            optionLabel="label"
            optionValue="value"
            class="add-tipo"
          />
          <Select
            v-if="formNovoItem.tipo === 'peca'"
            v-model="formNovoItem.peca_id"
            :options="pecas"
            optionLabel="descricao"
            optionValue="id"
            filter
            showClear
            placeholder="Peça (opcional)"
            class="add-peca"
            @update:modelValue="selecionouPecaNovoItem"
          />
          <InputText v-model="formNovoItem.descricao" placeholder="Descrição" class="add-descricao" />
          <InputNumber v-model="formNovoItem.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" class="add-qtd" />
          <InputNumber v-model="formNovoItem.valor_unitario" placeholder="Valor unit." mode="currency" currency="BRL" locale="pt-BR" class="add-valor" />
          <Button label="Adicionar" icon="pi pi-plus" size="small" class="add-botao" @click="adicionarItemDoFormulario" />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Itens incluídos</span>
        <div v-if="itens.length === 0" class="itens-vazio">Nenhum item adicionado ainda.</div>
        <table v-else class="itens-tabela">
          <thead>
            <tr><th>Item</th><th>Tipo</th><th>Qtde</th><th>Valor unit.</th><th>Subtotal</th><th></th></tr>
          </thead>
          <tbody>
            <tr v-for="(item, index) in itens" :key="index">
              <td>{{ item.descricao }}</td>
              <td><span class="badge-tipo-item" :class="item.peca_id ? 'badge-peca' : 'badge-mao-obra'">{{ tipoItem(item) }}</span></td>
              <td>{{ item.quantidade }}</td>
              <td>{{ formatarMoeda(item.valor_unitario) }}</td>
              <td>{{ formatarMoeda(item.quantidade * item.valor_unitario) }}</td>
              <td><Button icon="pi pi-trash" text rounded size="small" severity="danger" aria-label="Remover" @click="removerItem(index)" /></td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="item-total-footer">
        Total do orçamento: <strong>{{ formatarMoeda(totalItensAtual) }}</strong>
      </div>

      <template #footer>
        <Button label="Cancelar" text @click="dialogoItensAberto = false" />
        <Button label="Salvar Itens" :loading="salvandoItens" @click="salvarItens" />
      </template>
    </Dialog>

    <!-- Autorização / comprovante -->
    <Dialog v-model:visible="dialogoAutorizacaoAberto" modal header="Autorização do Cliente" style="width: 440px">
      <div class="form-campo">
        <label>Autorizado por (nome)</label>
        <InputText v-model="formAutorizacao.autorizado_por_nome" />
      </div>
      <div class="form-campo">
        <label>Comprovante (foto/PDF)</label>
        <input type="file" @change="onArquivoSelecionado" accept="image/*,application/pdf" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAutorizacaoAberto = false" />
        <Button label="Salvar" :loading="salvandoAutorizacao" @click="salvarAutorizacao" />
      </template>
    </Dialog>

    <!-- Decisão por item (ETAPA 5/P1-B — APR-002/004/005/006) -->
    <Dialog v-model:visible="dialogoDecisaoAberto" modal header="Aprovação por Item" style="width: 92vw; max-width: 780px">
      <div v-if="orcamentoAtual">
        <p class="resumo-decisao">
          Valor original: <strong>{{ formatarMoeda(orcamentoAtual.valor_total) }}</strong>
          <span class="valor valor-aprovado">Aprovado: {{ formatarMoeda(valorAprovado(orcamentoAtual)) }}</span>
          <span class="valor valor-rejeitado">Rejeitado: {{ formatarMoeda(valorRejeitado(orcamentoAtual)) }}</span>
        </p>

        <div class="bloco-form" v-if="temItemPendente(orcamentoAtual) && podeAutorizar()">
          <span class="bloco-form-titulo">Decisão</span>
          <div class="form-campo">
            <label>Meio de aprovação (aplicado à próxima decisão)</label>
            <Select v-model="formDecisao.meio_aprovacao" :options="meiosAprovacao" optionLabel="label" optionValue="value" />
          </div>
          <div class="form-campo">
            <label>Autorizado por (nome do cliente/responsável)</label>
            <InputText v-model="formDecisao.autorizado_por_nome" placeholder="Nome de quem autorizou" />
          </div>
          <div class="form-campo" v-if="formDecisao.meio_aprovacao === 'email'">
            <label>Comprovante (evidência do e-mail)</label>
            <input type="file" @change="onArquivoDecisaoSelecionado" accept="image/*,application/pdf,.eml,.msg" />
          </div>
          <div class="form-campo" v-if="formDecisao.meio_aprovacao === 'verbal_documentado'">
            <label>Observação (obrigatória — quem atendeu, quando, o que foi dito)</label>
            <Textarea v-model="formDecisao.observacao" rows="2" autoResize />
          </div>
        </div>

        <table class="itens-tabela">
          <thead>
            <tr><th>Item</th><th>Valor</th><th>Status</th><th>Meio</th><th>Autorizado por</th><th>Ação</th></tr>
          </thead>
          <tbody>
            <tr v-for="item in orcamentoAtual.orcamento_itens" :key="item.id">
              <td>{{ item.descricao }} <span class="hint">({{ item.quantidade }}x)</span></td>
              <td>{{ formatarMoeda(item.quantidade * item.valor_unitario) }}</td>
              <td><Tag :severity="STATUS_ITEM_ORCAMENTO[item.status_aprovacao]?.severidade" :value="STATUS_ITEM_ORCAMENTO[item.status_aprovacao]?.label ?? item.status_aprovacao" /></td>
              <td>{{ item.meio_aprovacao || '—' }}</td>
              <td>{{ item.autorizado_por_nome || '—' }}</td>
              <td>
                <template v-if="item.status_aprovacao === 'pendente' && podeAutorizar()">
                  <Button label="Aprovar" size="small" severity="success" :loading="decidindoItemId === item.id" @click="decidirItem(item, 'aprovado')" />
                  <Button label="Rejeitar" size="small" severity="danger" text :loading="decidindoItemId === item.id" @click="decidirItem(item, 'rejeitado')" />
                </template>
                <span v-else-if="item.status_aprovacao !== 'pendente'" class="hint">decidido</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <template #footer>
        <Button label="Fechar" text @click="dialogoDecisaoAberto = false" />
      </template>
    </Dialog>

    <!-- Acréscimo -->
    <Dialog v-model:visible="dialogoAcrescimoAberto" modal header="Registrar Acréscimo" style="width: 440px">
      <div class="form-campo">
        <label>Valor do Acréscimo</label>
        <InputNumber v-model="formAcrescimo.valor_acrescimo" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Justificativa</label>
        <Textarea v-model="formAcrescimo.justificativa" rows="3" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAcrescimoAberto = false" />
        <Button label="Registrar" :loading="salvandoAcrescimo" @click="salvarAcrescimo" />
      </template>
    </Dialog>

    <!-- Desconto (ETAPA 6/P1-C — Decisão 7) -->
    <Dialog v-model:visible="dialogoDescontoAberto" modal header="Aplicar Desconto" style="width: 440px">
      <p v-if="orcamentoAtual" class="resumo-decisao">
        Valor atual: <strong>{{ formatarMoeda(orcamentoAtual.valor_total) }}</strong>
      </p>

      <div class="form-campo">
        <label>Modo</label>
        <Select v-model="formDesconto.modo" :options="[{ label: 'Percentual', value: 'percentual' }, { label: 'Valor fixo (R$)', value: 'valor' }]" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo" v-if="formDesconto.modo === 'percentual'">
        <label>Percentual (%)</label>
        <InputNumber v-model="formDesconto.percentual" suffix="%" :minFractionDigits="0" :maxFractionDigits="2" />
      </div>
      <div class="form-campo" v-else>
        <label>Valor do desconto</label>
        <InputNumber v-model="formDesconto.valor" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Motivo (obrigatório)</label>
        <Textarea v-model="formDesconto.motivo" rows="3" autoResize placeholder="Mínimo 5 caracteres" />
      </div>

      <div class="info-box">
        <i class="pi pi-info-circle"></i>
        <div>
          <strong>Regras do desconto</strong>
          <ul>
            <li>respeita o teto configurado pelo administrador técnico;</li>
            <li>exige motivo (mínimo 5 caracteres);</li>
            <li>nunca reduz o valor final abaixo de zero;</li>
            <li>orçamento já enviado/aprovado exige Nova Versão antes de alterar o desconto.</li>
          </ul>
        </div>
      </div>

      <template #footer>
        <Button label="Cancelar" text @click="dialogoDescontoAberto = false" />
        <Button label="Aplicar" :loading="salvandoDesconto" @click="salvarDesconto" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
/* ETAPA UX-ORCAMENTOS-01 — mesma linguagem visual das telas irmãs
   (item 29: telas irmãs). Duplicado por não tocar em arquivos de etapas já
   entregues (ver MELHORIAS FUTURAS no relatório). */
.pagina-cabecalho-linha {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 14px;
  margin-bottom: 18px;
  flex-wrap: wrap;
}
.pagina-cabecalho {
  min-width: 0;
}
.pagina-titulo {
  margin: 0 0 4px;
  font-size: 24px;
  font-weight: 800;
  letter-spacing: -0.4px;
  color: var(--text-heading);
}
.pagina-subtitulo {
  margin: 0;
  font-size: 13.5px;
  color: var(--text-secondary);
}

.cabecalho {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}

.busca {
  flex: 1;
  min-width: 220px;
  max-width: 420px;
}
.busca :deep(.p-inputtext) {
  width: 100%;
  height: 40px;
  background: var(--surface);
  border-color: var(--border-panel);
  color: var(--text-body);
}
.busca :deep(.p-inputtext::placeholder) {
  color: var(--text-faint);
}
.busca :deep(.p-inputtext:enabled:focus) {
  border-color: var(--primary);
  box-shadow: 0 0 0 1px var(--primary);
}
.busca :deep(.p-inputicon) {
  color: var(--text-faint);
}

.panel {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 6px 4px;
  overflow-x: auto;
}

.placa-destaque {
  font-family: var(--font-mono);
  font-weight: 600;
  color: var(--text-heading);
  letter-spacing: 0.3px;
}
.prefixo-inline {
  margin-left: 6px;
  color: var(--text-muted);
  font-size: 12px;
}

:deep(.col-numero),
:deep(.col-valor) {
  text-align: right;
}
.valor {
  font-variant-numeric: tabular-nums;
}
.valor-original {
  color: var(--text-body);
}
.valor-aprovado {
  color: var(--success);
  font-weight: 600;
}
.valor-rejeitado {
  color: var(--danger);
}
.valor-acrescimo {
  color: var(--accent-text);
}

.acoes-linha {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
}

.estado-vazio-tabela {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 48px 20px;
  color: var(--text-faint);
}
.estado-vazio-tabela i {
  font-size: 26px;
}
.estado-vazio-tabela p {
  margin: 0;
  font-size: 13.5px;
}

.bloco-form {
  margin-bottom: 18px;
}
.bloco-form-titulo {
  display: block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-bottom: 8px;
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
.info-derivada {
  margin: 6px 0 0;
  font-size: 12.5px;
  color: var(--text-secondary);
}

/* Itens — formulário de adição */
.item-add-grid {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  flex-wrap: wrap;
  background: var(--surface-hover);
  border-radius: var(--card-radius);
  padding: 12px;
}
.add-tipo {
  flex: 1;
  min-width: 130px;
}
.add-peca {
  flex: 1.5;
  min-width: 160px;
}
.add-descricao {
  flex: 1.5;
  min-width: 160px;
}
.add-qtd,
.add-valor {
  flex: 1;
  min-width: 100px;
}
.add-botao {
  flex-shrink: 0;
}

.itens-vazio {
  color: var(--text-faint);
  font-size: 13px;
  padding: 16px 0;
}
.itens-tabela {
  width: 100%;
  border-collapse: collapse;
  margin-top: 0.5rem;
}
.itens-tabela th,
.itens-tabela td {
  text-align: left;
  padding: 0.5rem 0.6rem;
  border-bottom: 1px solid var(--border-panel);
  font-size: 0.85rem;
  vertical-align: middle;
  color: var(--text-body);
}
.itens-tabela th {
  color: var(--text-table-header);
  font-weight: 600;
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.3px;
}

.badge-tipo-item {
  display: inline-flex;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.3px;
}
.badge-peca {
  background: var(--info-bg);
  color: var(--info);
}
.badge-mao-obra {
  background: var(--accent-soft-bg);
  color: var(--accent-text);
}

.item-total-footer {
  text-align: right;
  font-size: 14px;
  color: var(--text-heading);
  padding-top: 8px;
  border-top: 1px solid var(--border-panel);
}
.item-total-footer strong {
  font-size: 17px;
  margin-left: 6px;
}

.resumo-decisao {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  align-items: baseline;
  font-size: 13px;
  color: var(--text-secondary);
  margin: 0 0 16px;
}
.resumo-decisao .valor {
  font-size: 13px;
}

.hint {
  color: var(--text-faint);
  font-size: 0.85rem;
}

.info-box {
  display: flex;
  gap: 10px;
  background: var(--accent-soft-bg);
  border-radius: var(--card-radius);
  padding: 12px 14px;
  margin-top: 8px;
  font-size: 12.5px;
  color: var(--text-secondary);
}
.info-box i {
  color: var(--accent-text);
  font-size: 15px;
  margin-top: 2px;
}
.info-box strong {
  display: block;
  color: var(--text-heading);
  margin-bottom: 4px;
  font-size: 12.5px;
}
.info-box ul {
  margin: 0;
  padding-left: 16px;
}
.info-box li {
  margin-bottom: 2px;
}

@media (max-width: 720px) {
  .pagina-cabecalho-linha {
    flex-direction: column;
    align-items: stretch;
  }
  .busca {
    max-width: none;
  }
}
</style>
