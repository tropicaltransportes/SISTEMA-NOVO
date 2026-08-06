<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'administrador_tecnico'].includes(auth.perfil)

const ordens = ref([])
const veiculos = ref([])
const orcamentosAprovados = ref([])
const checklistTemplates = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)

const severidadeStatus = {
  aberta: 'info',
  em_diagnostico: 'warn',
  aguardando_aprovacao: 'warn',
  em_execucao: 'warn',
  aguardando_teste: 'warn',
  concluida: 'success',
  liberada: 'success',
  reaberta_garantia: 'danger',
  cancelada: 'danger',
}

const formVazio = () => ({ veiculo_id: null, tipo: null, orcamento_id: null, checklist_template_id: null, solicitacao_id: null })
const form = ref(formVazio())

const veiculoSelecionado = computed(() => veiculos.value.find((v) => v.id === form.value.veiculo_id))
const orcamentosDoVeiculo = computed(() => orcamentosAprovados.value.filter((o) => o.veiculo_id === form.value.veiculo_id))

async function carregar() {
  carregando.value = true
  const [respOs, respVeiculos, respOrc, respTemplates] = await Promise.all([
    supabase
      .from('ordens_servico')
      .select('id, tipo, status, data_abertura, data_liberacao, veiculo:veiculos(id, placa), cliente:clientes(id, nome)')
      .order('data_abertura', { ascending: false }),
    supabase.from('veiculos').select('id, placa, cliente_id, cliente:clientes(tipo)').is('deleted_at', null).order('placa'),
    supabase.from('orcamentos').select('id, veiculo_id, versao, valor_total').eq('status', 'aprovado'),
    supabase.from('checklist_templates').select('id, nome').eq('ativo', true).order('nome'),
  ])

  if (respOs.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar OS', detail: respOs.error.message, life: 5000 })
  } else {
    ordens.value = respOs.data
  }
  veiculos.value = respVeiculos.data ?? []
  orcamentosAprovados.value = respOrc.data ?? []
  checklistTemplates.value = respTemplates.data ?? []
  carregando.value = false
}

function abrirNova() {
  form.value = formVazio()
  if (route.query.veiculo_id) form.value.veiculo_id = route.query.veiculo_id
  if (route.query.orcamento_id) form.value.orcamento_id = route.query.orcamento_id
  if (route.query.solicitacao_id) form.value.solicitacao_id = route.query.solicitacao_id
  if (veiculoSelecionado.value) form.value.tipo = veiculoSelecionado.value.cliente?.tipo === 'interno' ? 'interna' : 'externa'
  dialogoAberto.value = true
}

function aoSelecionarVeiculo() {
  form.value.tipo = veiculoSelecionado.value?.cliente?.tipo === 'interno' ? 'interna' : 'externa'
  form.value.orcamento_id = null
}

async function criar() {
  if (!form.value.veiculo_id) {
    toast.add({ severity: 'warn', summary: 'Selecione o veículo', life: 4000 })
    return
  }
  if (form.value.tipo === 'externa' && !form.value.orcamento_id) {
    toast.add({ severity: 'warn', summary: 'OS externa exige um orçamento aprovado', life: 4000 })
    return
  }
  salvando.value = true
  const { data, error } = await supabase.rpc('rpc_criar_os', {
    p_veiculo_id: form.value.veiculo_id,
    p_tipo: form.value.tipo,
    p_orcamento_id: form.value.orcamento_id || null,
    p_solicitacao_id: form.value.solicitacao_id || null,
    p_checklist_template_id: form.value.checklist_template_id || null,
  })
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao criar OS', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'OS criada', life: 3000 })
  dialogoAberto.value = false
  if (Object.keys(route.query).length) router.replace({ path: '/os' })
  router.push(`/os/${data}`)
}

onMounted(() => {
  carregar().then(() => {
    if (route.query.veiculo_id) abrirNova()
  })
})
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Ordens de Serviço</h2>
      <Button v-if="podeGerir()" label="Nova OS" icon="pi pi-plus" @click="abrirNova" />
    </div>

    <DataTable :value="ordens" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows @row-click="(e) => router.push(`/os/${e.data.id}`)" style="cursor: pointer">
      <Column header="Veículo">
        <template #body="{ data }">{{ data.veiculo?.placa }}</template>
      </Column>
      <Column header="Cliente">
        <template #body="{ data }">{{ data.cliente?.nome }}</template>
      </Column>
      <Column field="tipo" header="Tipo" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Abertura">
        <template #body="{ data }">{{ new Date(data.data_abertura).toLocaleString('pt-BR') }}</template>
      </Column>
      <Column header="" style="width: 60px">
        <template #body="{ data }">
          <Button icon="pi pi-arrow-right" text rounded @click="router.push(`/os/${data.id}`)" />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal header="Nova Ordem de Serviço" style="width: 460px">
      <div class="form-campo">
        <label>Veículo</label>
        <Select
          v-model="form.veiculo_id"
          :options="veiculos"
          optionLabel="placa"
          optionValue="id"
          filter
          placeholder="Selecione o veículo"
          @update:modelValue="aoSelecionarVeiculo"
        />
      </div>
      <div class="form-campo" v-if="form.tipo">
        <label>Tipo</label>
        <Tag :severity="form.tipo === 'interna' ? 'info' : 'success'" :value="form.tipo" />
      </div>
      <div class="form-campo" v-if="form.tipo === 'externa'">
        <label>Orçamento aprovado</label>
        <Select
          v-model="form.orcamento_id"
          :options="orcamentosDoVeiculo"
          optionValue="id"
          filter
          placeholder="Selecione o orçamento aprovado"
        >
          <template #option="{ option }">v{{ option.versao }} — R$ {{ option.valor_total }}</template>
          <template #value="{ value }">
            <span v-if="value">{{ orcamentosDoVeiculo.find((o) => o.id === value) ? `v${orcamentosDoVeiculo.find((o) => o.id === value).versao}` : '' }}</span>
          </template>
        </Select>
      </div>
      <div class="form-campo">
        <label>Checklist técnico (opcional)</label>
        <Select v-model="form.checklist_template_id" :options="checklistTemplates" optionLabel="nome" optionValue="id" filter showClear placeholder="Selecionar checklist" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Criar OS" :loading="salvando" @click="criar" />
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
</style>
