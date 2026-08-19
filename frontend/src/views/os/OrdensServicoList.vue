<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import Checkbox from 'primevue/checkbox'
import Menu from 'primevue/menu'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'administrador_tecnico'].includes(auth.perfil)
// FEATURE-OS-CANCELAMENTO-01 (BR-051)
const podeRestaurar = () => auth.perfil === 'administrador_tecnico'

const ordens = ref([])
const veiculos = ref([])
const orcamentosAprovados = ref([])
const checklistTemplates = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)
// FEATURE-OS-CANCELAMENTO-01 — mesmo padrão de
// frontend/src/views/orcamentos/OrcamentosList.vue: a RLS de ordens_servico
// já decide sozinha se administrador_tecnico recebe as linhas excluídas de
// volta; este toggle é só conveniência de UI sobre o que o banco já
// entregou, nunca a barreira de segurança.
const mostrarExcluidos = ref(false)
const filtroStatus = ref(null)

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
const opcoesStatus = [
  { label: 'Todas', value: null },
  { label: 'Ativas', value: 'ativas' },
  { label: 'Concluídas/Liberadas', value: 'concluidas' },
  { label: 'Canceladas', value: 'cancelada' },
]
const ordensFiltradas = computed(() => {
  if (!filtroStatus.value) return ordens.value
  if (filtroStatus.value === 'ativas') {
    return ordens.value.filter((o) => !['concluida', 'liberada', 'cancelada'].includes(o.status))
  }
  if (filtroStatus.value === 'concluidas') {
    return ordens.value.filter((o) => ['concluida', 'liberada'].includes(o.status))
  }
  return ordens.value.filter((o) => o.status === filtroStatus.value)
})

const formVazio = () => ({ veiculo_id: null, tipo: null, orcamento_id: null, checklist_template_id: null, solicitacao_id: null })
const form = ref(formVazio())

const veiculoSelecionado = computed(() => veiculos.value.find((v) => v.id === form.value.veiculo_id))
const orcamentosDoVeiculo = computed(() => orcamentosAprovados.value.filter((o) => o.veiculo_id === form.value.veiculo_id))

async function carregar() {
  carregando.value = true
  let queryOs = supabase
    .from('ordens_servico')
    .select(
      'id, tipo, status, data_abertura, data_liberacao, deleted_at, deleted_by, deleted_reason, cancelado_em, cancelado_por, cancelamento_motivo, veiculo:veiculos(id, placa), cliente:clientes(id, nome)'
    )
    .order('data_abertura', { ascending: false })
  // Filtro de conveniência (não é a barreira de segurança — a RLS já esconde
  // deleted_at de quem não é administrador_tecnico, ver BR-048).
  if (!(podeRestaurar() && mostrarExcluidos.value)) {
    queryOs = queryOs.is('deleted_at', null)
  }
  const [respOs, respVeiculos, respOrc, respTemplates] = await Promise.all([
    queryOs,
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

// ---------- Restaurar OS excluída (FEATURE-OS-CANCELAMENTO-01, BR-051) ----------
function confirmarRestaurar(osItem) {
  confirm.require({
    message: `Restaurar a OS excluída de ${osItem.veiculo?.placa || 'veículo'}? Ela volta a aparecer nas listagens normais.`,
    header: 'Confirmar restauração',
    icon: 'pi pi-refresh',
    acceptLabel: 'Restaurar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_restaurar_os_excluida', { p_os_id: osItem.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao restaurar', detail: error.message, life: 6000 })
        return
      }
      toast.add({ severity: 'success', summary: 'OS restaurada', life: 3000 })
      await carregar()
    },
  })
}

function construirMenuAcoes(osItem) {
  if (!osItem) return []
  const lista = []
  if (osItem.deleted_at && podeRestaurar()) {
    lista.push({ label: 'Restaurar OS', icon: 'pi pi-refresh', command: () => confirmarRestaurar(osItem) })
  }
  return lista
}
const menuAcoes = ref()
const osMenuAtual = ref(null)
const itensMenuAcoesAtual = computed(() => construirMenuAcoes(osMenuAtual.value))
function abrirMenuAcoes(event, osItem) {
  osMenuAtual.value = osItem
  menuAcoes.value.toggle(event)
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

    <div class="filtros-linha">
      <Select v-model="filtroStatus" :options="opcoesStatus" optionLabel="label" optionValue="value" placeholder="Todas" style="width: 220px" />
      <label v-if="podeRestaurar()" class="toggle-excluidos">
        <Checkbox v-model="mostrarExcluidos" binary @change="carregar" />
        Mostrar excluídas
      </label>
    </div>

    <DataTable :value="ordensFiltradas" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows @row-click="(e) => router.push(`/os/${e.data.id}`)" style="cursor: pointer">
      <Column header="Veículo">
        <template #body="{ data }">{{ data.veiculo?.placa }}</template>
      </Column>
      <Column header="Cliente">
        <template #body="{ data }">{{ data.cliente?.nome }}</template>
      </Column>
      <Column field="tipo" header="Tipo" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag v-if="data.deleted_at" severity="danger" value="Excluída" style="margin-right: 6px" />
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Abertura">
        <template #body="{ data }">{{ new Date(data.data_abertura).toLocaleString('pt-BR') }}</template>
      </Column>
      <Column header="" style="width: 90px">
        <template #body="{ data }">
          <Button v-if="construirMenuAcoes(data).length" icon="pi pi-ellipsis-v" text rounded size="small" aria-label="Mais ações" @click.stop="abrirMenuAcoes($event, data)" />
          <Button icon="pi pi-arrow-right" text rounded @click="router.push(`/os/${data.id}`)" />
        </template>
      </Column>
    </DataTable>
    <Menu ref="menuAcoes" :model="itensMenuAcoesAtual" :popup="true" />

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
.filtros-linha {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 1rem;
}
.toggle-excluidos {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--text-secondary);
  cursor: pointer;
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
