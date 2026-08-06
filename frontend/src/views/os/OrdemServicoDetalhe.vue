<script setup>
import { ref, computed, onMounted } from 'vue'
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

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const osId = route.params.id
const os = ref(null)
const checklistItens = ref([])
const respostas = ref([])
const executores = ref([])
const movimentos = ref([])
const pecas = ref([])
const checklistTemplates = ref([])
const carregando = ref(true)

const severidadeStatus = {
  aberta: 'info', em_diagnostico: 'warn', aguardando_aprovacao: 'warn', em_execucao: 'warn',
  aguardando_teste: 'warn', concluida: 'success', liberada: 'success', reaberta_garantia: 'danger', cancelada: 'danger',
}

const podeTransicionar = computed(() => ['encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeApontar = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeResponderChecklist = computed(() => ['executor', 'encarregado', 'administrador_tecnico'].includes(auth.perfil))
const podeBaixarPeca = computed(() => ['executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))

async function carregar() {
  carregando.value = true
  const [respOs, respExec, respMov, respPecas, respTemplates] = await Promise.all([
    supabase
      .from('ordens_servico')
      .select('id, tipo, status, data_abertura, data_liberacao, checklist_template_id, orcamento_id, veiculo:veiculos(id, placa, prefixo, modelo), cliente:clientes(id, nome, tipo)')
      .eq('id', osId)
      .single(),
    supabase.from('os_executores').select('id, usuario_id, etapa, inicio, fim, observacao, usuario:profiles(nome)').eq('os_id', osId).order('inicio', { ascending: false }),
    supabase.from('estoque_movimentos').select('id, quantidade, custo_unitario, criado_em, peca:pecas(sku, descricao)').eq('origem_tipo', 'os').eq('origem_id', osId).order('criado_em', { ascending: false }),
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

  if (os.value.checklist_template_id) {
    const [respItens, respResp] = await Promise.all([
      supabase.from('checklist_template_itens').select('id, descricao, obrigatorio').eq('template_id', os.value.checklist_template_id),
      supabase.from('os_checklist_respostas').select('id, template_item_id, ok').eq('os_id', osId),
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
  const { error } = await supabase.rpc('rpc_transicionar_os', { p_os_id: osId, p_novo_status: next })
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
  const { error } = await supabase.rpc('rpc_concluir_os', { p_os_id: osId })
  if (error) {
    toast.add({ severity: 'error', summary: 'Não é possível concluir', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS concluída', life: 3000 })
  await carregar()
}

async function liberar() {
  const { error } = await supabase.rpc('rpc_liberar_os', { p_os_id: osId })
  if (error) {
    toast.add({ severity: 'error', summary: 'Não é possível liberar', detail: error.message, life: 7000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS liberada', life: 3000 })
  await carregar()
}

// ---------- Checklist ----------
async function definirChecklist(templateId) {
  const { error } = await supabase.rpc('rpc_definir_checklist_os', { p_os_id: osId, p_checklist_template_id: templateId })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao definir checklist', detail: error.message, life: 6000 })
    return
  }
  await carregar()
}

async function alternarResposta(item, valor) {
  const { error } = await supabase.from('os_checklist_respostas').upsert(
    { os_id: osId, template_item_id: item.id, ok: valor, respondido_por: auth.profile.id, respondido_em: new Date().toISOString() },
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
    os_id: osId,
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

async function encerrarApontamento(exec) {
  const { error } = await supabase.from('os_executores').update({ fim: new Date().toISOString() }).eq('id', exec.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao encerrar apontamento', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

// ---------- Baixa de peça ----------
const formBaixa = ref({ peca_id: null, quantidade: 1 })
const podeMovimentarEstoque = computed(() => ['em_diagnostico', 'em_execucao'].includes(os.value?.status))

async function baixarPeca() {
  if (!formBaixa.value.peca_id || !formBaixa.value.quantidade) {
    toast.add({ severity: 'warn', summary: 'Selecione a peça e a quantidade', life: 4000 })
    return
  }
  const { error } = await supabase.rpc('rpc_baixar_peca_os', {
    p_os_id: osId,
    p_peca_id: formBaixa.value.peca_id,
    p_quantidade: formBaixa.value.quantidade,
  })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao baixar peça', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Peça baixada do estoque', life: 3000 })
  formBaixa.value = { peca_id: null, quantidade: 1 }
  await carregar()
}

onMounted(carregar)
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
      <Button v-if="os.status === 'concluida'" label="Liberar" size="small" severity="success" @click="liberar" />
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
            <Button v-else-if="data.usuario_id === auth.profile.id" label="Encerrar" size="small" text @click="encerrarApontamento(data)" />
          </template>
        </Column>
        <Column field="observacao" header="Observação" />
      </DataTable>
    </div>

    <div class="secao">
      <h3>Peças Utilizadas</h3>
      <div class="form-linha" v-if="podeBaixarPeca && podeMovimentarEstoque">
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
