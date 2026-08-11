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

const severidadeStatus = {
  aberta: 'info', em_diagnostico: 'warn', aguardando_aprovacao: 'warn', em_execucao: 'warn',
  aguardando_teste: 'warn', concluida: 'success', liberada: 'success', reaberta_garantia: 'danger', cancelada: 'danger',
}

const podeTransicionar = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeApontar = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeResponderChecklist = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeBaixarPeca = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeGerarCobranca = computed(() => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))
const podeAbrirGarantia = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))

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
      .select('id, tipo, status, data_abertura, data_liberacao, checklist_template_id, orcamento_id, os_origem_id, veiculo:veiculos(id, placa, prefixo, modelo), cliente:clientes(id, nome, tipo)')
      .eq('id', osId.value)
      .single(),
    supabase.from('os_executores').select('id, usuario_id, etapa, inicio, fim, observacao, usuario:profiles(nome)').eq('os_id', osId.value).order('inicio', { ascending: false }),
    supabase.from('estoque_movimentos').select('id, quantidade, custo_unitario, criado_em, orcamento_item_id, tipo, peca:pecas(sku, descricao)').eq('origem_tipo', 'os').eq('origem_id', osId.value).order('criado_em', { ascending: false }),
    supabase.from('pecas').select('id, sku, descricao, saldo_atual').is('deleted_at', null).order('descricao'),
    supabase.from('checklist_templates').select('id, nome').eq('ativo', true).order('nome'),
  ])

  if (respOs.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar OS', detail: respOs.error.message, life: 5000 })
    carregando.value = false
    return
  }
  os.value = respOs.data
  executores.value = respExec.data ?? []
  movimentos.value = respMov.data ?? []
  pecas.value = respPecas.data ?? []
  checklistTemplates.value = respTemplates.data ?? []

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
      .select('id, peca_id, descricao, quantidade, execucao_status, peca:pecas(sku, descricao)')
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

// ---------- Baixa de peça ----------
// ETAPA 4 (P1-A) — item D (EST-004): quando a OS tem orçamento (ou é
// garantia com item vinculado), a baixa exige escolher o ITEM aprovado —
// a peça é derivada do item, não escolhida livremente (rpc_baixar_peca_os
// agora exige p_orcamento_item_id nesses casos e bloqueia peça fora do
// escopo aprovado).
const formBaixa = ref({ peca_id: null, quantidade: 1, orcamento_item_id: null })
const podeMovimentarEstoque = computed(() => ['em_diagnostico', 'em_execucao'].includes(os.value?.status))
const exigeVinculoItem = computed(() => !!os.value?.orcamento_id || !!os.value?.os_origem_id)
// Lista de itens elegíveis para baixa: da própria OS quando tem orçamento,
// ou os vinculados via garantia quando a OS é retorno de garantia.
const itensParaBaixa = computed(() => {
  if (os.value?.orcamento_id) {
    return orcamentoItens.value
      .filter((i) => i.peca_id)
      .map((i) => ({ ...i, restante: i.quantidade - quantidadeJaBaixada(i.id) }))
  }
  if (os.value?.os_origem_id) {
    return garantiaItensVinculados.value
      .filter((v) => v.item?.peca_id)
      .map((v) => ({ id: v.item.id, peca_id: v.item.peca_id, descricao: v.item.descricao, quantidade: v.item.quantidade, peca: v.item.peca, restante: v.item.quantidade - quantidadeJaBaixada(v.item.id) }))
  }
  return []
})
function quantidadeJaBaixada(orcamentoItemId) {
  // saída soma, estorno_saída subtrai — reflete o líquido realmente
  // consumido deste item nesta OS (mesmo cálculo do backend em
  // sincronizar_execucao_item_orcamento).
  return movimentos.value
    .filter((m) => m.orcamento_item_id === orcamentoItemId)
    .reduce((soma, m) => soma + (m.tipo === 'estorno_saida' ? -Number(m.quantidade) : Number(m.quantidade)), 0)
}
function selecionouItemBaixa() {
  const item = itensParaBaixa.value.find((i) => i.id === formBaixa.value.orcamento_item_id)
  formBaixa.value.peca_id = item?.peca_id ?? null
}

async function baixarPeca() {
  if (exigeVinculoItem.value && !formBaixa.value.orcamento_item_id) {
    toast.add({ severity: 'warn', summary: 'Selecione o item do orçamento/garantia', life: 4000 })
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
    p_orcamento_item_id: formBaixa.value.orcamento_item_id || null,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao baixar peça', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Peça baixada do estoque', life: 3000 })
  formBaixa.value = { peca_id: null, quantidade: 1, orcamento_item_id: null }
  await carregar()
}

// ---------- Itens de mão de obra (item E / CON-002) ----------
// Itens sem peça (mão de obra) não têm sinal automático de execução —
// precisam ser marcados manualmente antes de a OS poder ser concluída.
const itensMaoDeObra = computed(() => orcamentoItens.value.filter((i) => !i.peca_id))
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

function abrirCancelarItem(item) {
  itemParaCancelar.value = item
  motivoCancelamento.value = ''
  dialogoCancelarItemAberto.value = true
}

async function confirmarCancelarItem() {
  if (!motivoCancelamento.value || motivoCancelamento.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_marcar_item_orcamento_execucao', {
    p_orcamento_item_id: itemParaCancelar.value.id,
    p_status: 'cancelado',
    p_motivo: motivoCancelamento.value,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao cancelar item', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Item dispensado (auditado)', life: 3000 })
  dialogoCancelarItemAberto.value = false
  await carregar()
}

watch(osId, carregar, { immediate: true })
</script>

<template>
  <div v-if="carregando">Carregando...</div>
  <div v-else-if="os">
    <div class="cabecalho">
      <div>
        <Button icon="pi pi-arrow-left" text @click="router.push('/os')" />
        <h2 style="display:inline">OS — {{ os.veiculo?.placa }} <span v-if="os.veiculo?.prefixo">({{ os.veiculo.prefixo }})</span></h2>
      </div>
      <Tag :severity="severidadeStatus[os.status]" :value="os.status" style="font-size: 1rem" />
    </div>

    <p><strong>Cliente:</strong> {{ os.cliente?.nome }} &nbsp;|&nbsp; <strong>Tipo:</strong> {{ os.tipo }} &nbsp;|&nbsp; <strong>Aberta em:</strong> {{ new Date(os.data_abertura).toLocaleString('pt-BR') }}</p>
    <p v-if="os.data_liberacao"><strong>Liberada em:</strong> {{ new Date(os.data_liberacao).toLocaleString('pt-BR') }}</p>

    <p v-if="osOrigem" class="hint">
      Esta OS é garantia da
      <router-link :to="'/os/' + osOrigem.id">OS {{ osOrigem.veiculo?.placa }}<span v-if="osOrigem.veiculo?.prefixo"> ({{ osOrigem.veiculo.prefixo }})</span></router-link>
      — sem cobrança ao cliente.
    </p>
    <div v-if="osGarantias.length > 0" class="hint">
      Garantia(s) aberta(s) a partir desta OS:
      <router-link v-for="g in osGarantias" :key="g.id" :to="'/os/' + g.id" style="margin-right: 0.5rem">
        {{ g.veiculo?.placa }} ({{ g.status }})
      </router-link>
    </div>
    <p v-if="dentroDoPrazoGarantia" class="hint">Garantia até {{ prazoGarantiaAte.toLocaleDateString('pt-BR') }}.</p>

    <div class="acoes-status" v-if="podeTransicionar">
      <Button
        v-for="t in transicoesDisponiveis"
        :key="t.next"
        :label="t.label"
        size="small"
        :severity="t.danger ? 'danger' : 'primary'"
        :outlined="t.danger"
        @click="confirmarTransicao(t)"
      />
      <Button v-if="os.status === 'aguardando_teste'" label="Concluir (checklist)" size="small" severity="success" @click="concluir" />
      <Button
        v-if="os.status === 'concluida' && os.tipo === 'externa' && podeGerarCobranca"
        label="Gerar Cobrança"
        size="small"
        icon="pi pi-wallet"
        @click="router.push({ path: '/financeiro/cobrancas', query: { cliente_id: os.cliente.id, os_id: os.id } })"
      />
      <Button v-if="os.status === 'concluida'" label="Liberar" size="small" severity="success" @click="liberar" />
      <Button
        v-if="dentroDoPrazoGarantia && podeAbrirGarantia"
        label="Abrir Garantia"
        size="small"
        icon="pi pi-shield"
        severity="warn"
        @click="confirmarAbrirGarantia"
      />
    </div>

    <div class="secao">
      <h3>Checklist Técnico</h3>
      <div v-if="!os.checklist_template_id && podeTransicionar" class="form-linha">
        <Select :options="checklistTemplates" optionLabel="nome" optionValue="id" placeholder="Definir checklist" @update:modelValue="definirChecklist" />
      </div>
      <p v-else-if="!os.checklist_template_id" class="hint">Nenhum checklist definido.</p>
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

    <div class="secao">
      <h3>Apontamento de Execução</h3>
      <div class="form-linha" v-if="podeApontar">
        <Select v-model="formApontamento.etapa" :options="etapas" placeholder="Etapa" />
        <InputText v-model="formApontamento.observacao" placeholder="Observação (opcional)" />
        <Button label="Iniciar" size="small" @click="iniciarApontamento" />
      </div>
      <DataTable :value="executores" dataKey="id" size="small">
        <Column header="Executor"><template #body="{ data }">{{ data.usuario?.nome }}</template></Column>
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
      </DataTable>
      <p v-if="osEncerrada" class="hint">OS encerrada — apontamentos não são mais editáveis diretamente (correção formal auditada disponível ao encarregado/admin técnico).</p>
    </div>

    <div class="secao" v-if="os.orcamento_id && itensMaoDeObra.length > 0">
      <h3>Itens de Mão de Obra do Orçamento (CON-002)</h3>
      <p class="hint">Itens sem peça não têm sinal automático de execução — marque manualmente antes de concluir a OS.</p>
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

    <div class="secao">
      <h3>Peças Utilizadas</h3>
      <!-- EST-004/GAR-005 (ETAPA 4 P1-A): quando a OS tem orçamento (ou é garantia
           vinculada), a baixa exige escolher o ITEM aprovado — a peça é derivada
           dele, nunca uma peça livre fora do escopo aprovado. -->
      <div class="form-linha" v-if="podeBaixarPeca && podeMovimentarEstoque && exigeVinculoItem">
        <Select
          v-model="formBaixa.orcamento_item_id"
          :options="itensParaBaixa"
          optionLabel="descricao"
          optionValue="id"
          filter
          placeholder="Item aprovado (orçamento/garantia)"
          @update:modelValue="selecionouItemBaixa"
        >
          <template #option="{ option }">
            {{ option.descricao }} — {{ option.peca?.descricao }} (restam {{ option.restante }} de {{ option.quantidade }})
          </template>
        </Select>
        <InputNumber v-model="formBaixa.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
        <Button label="Baixar" size="small" @click="baixarPeca" :disabled="!formBaixa.orcamento_item_id" />
      </div>
      <p v-else-if="podeBaixarPeca && podeMovimentarEstoque && exigeVinculoItem && itensParaBaixa.length === 0" class="hint">
        Nenhum item de peça aprovado disponível para baixa nesta OS.
      </p>
      <div class="form-linha" v-else-if="podeBaixarPeca && podeMovimentarEstoque">
        <Select v-model="formBaixa.peca_id" :options="pecas" optionLabel="descricao" optionValue="id" filter placeholder="Peça" />
        <InputNumber v-model="formBaixa.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
        <Button label="Baixar" size="small" @click="baixarPeca" />
      </div>
      <p v-else-if="podeBaixarPeca" class="hint">Baixa de peças só é permitida com a OS em diagnóstico ou execução.</p>
      <DataTable :value="movimentos" dataKey="id" size="small">
        <Column header="Peça"><template #body="{ data }">{{ data.peca?.descricao }} ({{ data.peca?.sku }})</template></Column>
        <Column field="quantidade" header="Qtde" />
        <Column header="Custo Unit."><template #body="{ data }">{{ (data.custo_unitario ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</template></Column>
        <Column header="Data"><template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template></Column>
      </DataTable>
    </div>

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

    <!-- CON-002 (ETAPA 4 P1-A): motivo obrigatório para dispensar item aprovado -->
    <Dialog v-model:visible="dialogoCancelarItemAberto" modal header="Dispensar item aprovado" style="width: 420px">
      <p class="hint">Cancelar um item aprovado do orçamento exige motivo — fica registrado na trilha de auditoria.</p>
      <Textarea v-model="motivoCancelamento" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelarItemAberto = false" />
        <Button label="Confirmar dispensa" severity="danger" @click="confirmarCancelarItem" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}
.secao {
  margin-top: 1.5rem;
  padding-top: 1rem;
  border-top: 1px solid #e5e7eb;
}
.acoes-status {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
  margin: 1rem 0;
}
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
  color: #6b7280;
  font-size: 0.85rem;
}
</style>
