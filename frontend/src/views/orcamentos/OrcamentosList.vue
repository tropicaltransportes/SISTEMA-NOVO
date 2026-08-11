<script setup>
import { ref, onMounted } from 'vue'
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

const severidadeStatus = {
  rascunho: 'secondary',
  enviado: 'warn',
  aprovado: 'success',
  parcialmente_aprovado: 'warn',
  rejeitado: 'danger',
  substituido: 'contrast',
}

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

async function carregar() {
  carregando.value = true
  const [respOrc, respVeiculos, respPecas] = await Promise.all([
    supabase
      .from('orcamentos')
      .select(
        'id, versao, status, valor_total, autorizado_por_nome, comprovante_path, criado_em, solicitacao_id, veiculo:veiculos(id, placa, cliente_id), cliente:clientes(id, nome, tipo), orcamento_itens(id, peca_id, descricao, quantidade, valor_unitario, status_aprovacao, meio_aprovacao, autorizado_por_nome, autorizado_em, registrado_por, comprovante_path, observacao), orcamento_acrescimos(id, valor_acrescimo, justificativa, criado_em)'
      )
      .order('criado_em', { ascending: false }),
    supabase.from('veiculos').select('id, placa, prefixo, cliente_id, cliente:clientes(nome, tipo)').is('deleted_at', null).order('placa'),
    supabase.from('pecas').select('id, sku, descricao').is('deleted_at', null).order('descricao'),
  ])

  if (respOrc.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar orçamentos', detail: respOrc.error.message, life: 5000 })
  } else {
    orcamentos.value = respOrc.data
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
  dialogoItensAberto.value = true
}

function adicionarItemPeca() {
  itens.value.push({ id: null, peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0 })
}
function adicionarItemMaoDeObra() {
  itens.value.push({ id: null, peca_id: null, descricao: 'Mão de obra', quantidade: 1, valor_unitario: 0 })
}
function removerItem(index) {
  itens.value.splice(index, 1)
}
function selecionouPeca(item) {
  const p = pecas.value.find((x) => x.id === item.peca_id)
  if (p && !item.descricao) item.descricao = p.descricao
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

const tagDecisao = { pendente: 'warn', aprovado: 'success', rejeitado: 'danger' }

onMounted(() => {
  carregar().then(() => {
    if (route.query.veiculo_id && !route.query.orcamento_id) abrirNovo()
  })
})
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Orçamentos</h2>
      <Button v-if="podeGerir()" label="Novo Orçamento" icon="pi pi-plus" @click="abrirNovo" />
    </div>

    <DataTable :value="orcamentos" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column header="Veículo">
        <template #body="{ data }">{{ data.veiculo?.placa }}</template>
      </Column>
      <Column header="Cliente">
        <template #body="{ data }">{{ data.cliente?.nome }}</template>
      </Column>
      <Column field="versao" header="Versão" style="width: 90px" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Valor Original">
        <template #body="{ data }">{{ formatarMoeda(data.valor_total) }}</template>
      </Column>
      <!-- ETAPA 5 (P1-B) — APR-002: totais por decisão de item, não mais só o valor_total do orçamento inteiro. -->
      <Column header="Valor Aprovado">
        <template #body="{ data }"><span style="color:#15803d;font-weight:600">{{ formatarMoeda(valorAprovado(data)) }}</span></template>
      </Column>
      <Column header="Valor Rejeitado">
        <template #body="{ data }"><span style="color:#b91c1c">{{ formatarMoeda(valorRejeitado(data)) }}</span></template>
      </Column>
      <Column header="Acréscimos" v-if="true">
        <template #body="{ data }">
          {{ formatarMoeda(data.orcamento_acrescimos.reduce((s, a) => s + a.valor_acrescimo, 0)) }}
        </template>
      </Column>
      <Column header="Ações" style="width: 460px">
        <template #body="{ data }">
          <template v-if="data.status === 'rascunho' && podeGerir()">
            <Button icon="pi pi-list" label="Itens" size="small" text @click="abrirItens(data)" />
            <Button icon="pi pi-percentage" label="Desconto" size="small" text @click="abrirDesconto(data)" />
            <Button icon="pi pi-send" label="Enviar" size="small" @click="enviar(data)" />
          </template>
          <Button icon="pi pi-file-pdf" label="PDF" size="small" text @click="irParaPdf(data)" />
          <template v-if="data.status === 'enviado'">
            <Button v-if="podeAutorizar()" label="Autorização" size="small" text @click="abrirAutorizacao(data)" />
            <!-- ETAPA 5 (P1-B) — APR-002: decisão por item substitui o antigo aprovar/rejeitar tudo-ou-nada como fluxo principal. -->
            <Button v-if="podeAutorizar()" label="Decidir Itens" icon="pi pi-check-square" size="small" severity="success" @click="abrirDecisao(data)" />
            <Button v-if="podeGerir()" label="Aprovar tudo" size="small" text @click="confirmarAprovacao(data)" />
            <Button v-if="podeGerir()" label="Rejeitar tudo" size="small" severity="danger" text @click="confirmarRejeicao(data)" />
          </template>
          <template v-if="['aprovado', 'parcialmente_aprovado'].includes(data.status) && podeGerir()">
            <Button label="Ver decisões" size="small" text @click="abrirDecisao(data)" />
            <Button v-if="data.status === 'aprovado'" label="Acréscimo" size="small" text @click="abrirAcrescimo(data)" />
            <Button label="Criar OS" size="small" severity="success" @click="criarOs(data)" />
          </template>
          <Button
            v-if="['enviado', 'aprovado', 'parcialmente_aprovado', 'rejeitado'].includes(data.status) && podeGerir()"
            label="Nova Versão"
            size="small"
            text
            @click="novaVersao(data)"
          />
        </template>
      </Column>
    </DataTable>

    <!-- Novo orçamento -->
    <Dialog v-model:visible="dialogoNovoAberto" modal header="Novo Orçamento" style="width: 420px">
      <div class="form-campo">
        <label>Veículo</label>
        <Select
          v-model="formNovo.veiculo_id"
          :options="veiculos"
          optionLabel="placa"
          optionValue="id"
          filter
          placeholder="Selecione o veículo"
          :disabled="!!route.query.veiculo_id"
        />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovoAberto = false" />
        <Button label="Criar Rascunho" :loading="salvandoNovo" @click="criarRascunho" />
      </template>
    </Dialog>

    <!-- Itens -->
    <Dialog v-model:visible="dialogoItensAberto" modal header="Itens do Orçamento" style="width: 680px">
      <div v-for="(item, index) in itens" :key="index" class="linha-item">
        <Select
          v-model="item.peca_id"
          :options="pecas"
          optionLabel="descricao"
          optionValue="id"
          filter
          showClear
          placeholder="Peça (opcional)"
          class="item-peca"
          @update:modelValue="selecionouPeca(item)"
        />
        <InputText v-model="item.descricao" placeholder="Descrição" class="item-descricao" />
        <InputNumber v-model="item.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" class="item-qtd" />
        <InputNumber v-model="item.valor_unitario" placeholder="Valor Unit." mode="currency" currency="BRL" locale="pt-BR" class="item-valor" />
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerItem(index)" />
      </div>
      <div class="botoes-item">
        <Button label="Adicionar item de peça" icon="pi pi-plus" text size="small" @click="adicionarItemPeca" />
        <Button label="Adicionar mão de obra" icon="pi pi-plus" text size="small" @click="adicionarItemMaoDeObra" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoItensAberto = false" />
        <Button label="Salvar Itens" :loading="salvandoItens" @click="salvarItens" />
      </template>
    </Dialog>

    <!-- Autorização / comprovante -->
    <Dialog v-model:visible="dialogoAutorizacaoAberto" modal header="Autorização do Cliente" style="width: 420px">
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
    <Dialog v-model:visible="dialogoDecisaoAberto" modal header="Aprovação por Item" style="width: 720px">
      <div v-if="orcamentoAtual">
        <p class="hint">
          Valor original: <strong>{{ formatarMoeda(orcamentoAtual.valor_total) }}</strong> —
          Aprovado: <strong style="color:#15803d">{{ formatarMoeda(valorAprovado(orcamentoAtual)) }}</strong> —
          Rejeitado: <strong style="color:#b91c1c">{{ formatarMoeda(valorRejeitado(orcamentoAtual)) }}</strong>
        </p>

        <div class="form-campo" v-if="temItemPendente(orcamentoAtual) && podeAutorizar()">
          <label>Meio de aprovação (aplicado à próxima decisão)</label>
          <Select v-model="formDecisao.meio_aprovacao" :options="meiosAprovacao" optionLabel="label" optionValue="value" />
          <label>Autorizado por (nome do cliente/responsável)</label>
          <InputText v-model="formDecisao.autorizado_por_nome" placeholder="Nome de quem autorizou" />
          <template v-if="formDecisao.meio_aprovacao === 'email'">
            <label>Comprovante (evidência do e-mail)</label>
            <input type="file" @change="onArquivoDecisaoSelecionado" accept="image/*,application/pdf,.eml,.msg" />
          </template>
          <template v-if="formDecisao.meio_aprovacao === 'verbal_documentado'">
            <label>Observação (obrigatória — quem atendeu, quando, o que foi dito)</label>
            <Textarea v-model="formDecisao.observacao" rows="2" autoResize />
          </template>
        </div>

        <table class="tabela-itens-decisao">
          <thead>
            <tr><th>Item</th><th>Valor</th><th>Status</th><th>Meio</th><th>Autorizado por</th><th>Ação</th></tr>
          </thead>
          <tbody>
            <tr v-for="item in orcamentoAtual.orcamento_itens" :key="item.id">
              <td>{{ item.descricao }} <span class="hint">({{ item.quantidade }}x)</span></td>
              <td>{{ formatarMoeda(item.quantidade * item.valor_unitario) }}</td>
              <td><Tag :severity="tagDecisao[item.status_aprovacao]" :value="item.status_aprovacao" /></td>
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
    <Dialog v-model:visible="dialogoAcrescimoAberto" modal header="Registrar Acréscimo" style="width: 420px">
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
    <Dialog v-model:visible="dialogoDescontoAberto" modal header="Aplicar Desconto" style="width: 420px">
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
      <p class="hint">Bloqueado acima do teto configurado pelo administrador técnico; nunca reduz o valor final abaixo de zero. Se o orçamento já foi enviado/aprovado, use Nova Versão antes de alterar o desconto.</p>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoDescontoAberto = false" />
        <Button label="Aplicar" :loading="salvandoDesconto" @click="salvarDesconto" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  margin-bottom: 0.9rem;
}
.form-campo label {
  font-size: 0.8rem;
  color: #4b5563;
}
.linha-item {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.5rem;
}
.item-peca {
  flex: 1.5;
}
.item-descricao {
  flex: 2;
}
.item-qtd,
.item-valor {
  flex: 1;
}
.botoes-item {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.25rem;
}
.hint {
  color: #6b7280;
  font-size: 0.85rem;
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
  border-bottom: 1px solid #e5e7eb;
  font-size: 0.85rem;
  vertical-align: middle;
}
</style>
