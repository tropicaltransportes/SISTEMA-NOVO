<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'

const router = useRouter()
const toast = useToast()
const confirm = useConfirm()

const clientes = ref([])
const carregando = ref(true)
const filtro = ref('')
const filtroTipo = ref('todos')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)

const opcoesTipo = [
  { label: 'Externo', value: 'externo' },
  { label: 'Interno (frota própria)', value: 'interno' },
]

const opcoesFiltroTipo = [
  { label: 'Todos', value: 'todos' },
  { label: 'Internos', value: 'interno' },
  { label: 'Externos', value: 'externo' },
]

const formVazio = () => ({ id: null, tipo: 'externo', nome: '', documento: '', telefone: '', email: '' })
const form = ref(formVazio())

const clientesFiltrados = computed(() => {
  if (filtroTipo.value === 'todos') return clientes.value
  return clientes.value.filter((c) => c.tipo === filtroTipo.value)
})

const gradientesAvatar = [
  'linear-gradient(135deg,#8b5cf6,#6d28d9)',
  'linear-gradient(135deg,#38bdf8,#0ea5e9)',
  'linear-gradient(135deg,#4ade80,#16a34a)',
  'linear-gradient(135deg,#facc15,#d97706)',
  'linear-gradient(135deg,#f87171,#dc2626)',
]
function avatarGradiente(cliente) {
  const chave = cliente.nome ?? cliente.id ?? ''
  const hash = [...chave].reduce((s, c) => s + c.charCodeAt(0), 0)
  return gradientesAvatar[hash % gradientesAvatar.length]
}
function contagemVeiculos(cliente) {
  return cliente.veiculos?.[0]?.count ?? 0
}

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase
    .from('clientes')
    .select('id, tipo, nome, documento, telefone, email, veiculos(count)')
    .is('deleted_at', null)
    .order('nome')
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar clientes', detail: error.message, life: 5000 })
  } else {
    clientes.value = data
  }
  carregando.value = false
}

function abrirNovo() {
  editando.value = null
  form.value = formVazio()
  dialogoAberto.value = true
}

function abrirEdicao(cliente) {
  editando.value = cliente
  form.value = { ...cliente }
  dialogoAberto.value = true
}

async function salvar() {
  salvando.value = true
  const payload = {
    tipo: form.value.tipo,
    nome: form.value.nome,
    documento: form.value.documento || null,
    telefone: form.value.telefone || null,
    email: form.value.email || null,
  }
  const query = editando.value
    ? supabase.from('clientes').update(payload).eq('id', editando.value.id)
    : supabase.from('clientes').insert(payload)

  const { error } = await query
  salvando.value = false

  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Cliente salvo', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function confirmarInativacao(cliente) {
  confirm.require({
    message: `Inativar o cliente "${cliente.nome}"? O histórico é preservado.`,
    header: 'Confirmar inativação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Inativar',
    rejectLabel: 'Cancelar',
    accept: () => inativar(cliente),
  })
}

async function inativar(cliente) {
  const { error } = await supabase
    .from('clientes')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', cliente.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao inativar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Cliente inativado', life: 3000 })
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <div class="pills">
        <button
          v-for="opcao in opcoesFiltroTipo"
          :key="opcao.value"
          type="button"
          class="pill"
          :class="{ 'pill-ativa': filtroTipo === opcao.value }"
          @click="filtroTipo = opcao.value"
        >
          {{ opcao.label }}
        </button>
      </div>
      <Button label="Novo Cliente" icon="pi pi-plus" class="btn-gradiente" @click="abrirNovo" />
    </div>

    <IconField class="busca">
      <InputIcon class="pi pi-search" />
      <InputText v-model="filtro" placeholder="Buscar por nome ou documento" />
    </IconField>

    <div class="panel">
      <DataTable
        :value="clientesFiltrados"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['nome', 'documento']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        @row-click="(e) => router.push(`/clientes/${e.data.id}`)"
        style="cursor: pointer"
      >
        <Column header="Nome" sortable sortField="nome">
          <template #body="{ data }">
            <div class="linha-nome">
              <span class="avatar-cliente" :style="{ background: avatarGradiente(data) }"></span>
              <span>{{ data.nome }}</span>
            </div>
          </template>
        </Column>
        <Column field="documento" header="Documento" />
        <Column field="telefone" header="Telefone" />
        <Column field="email" header="E-mail" />
        <Column field="tipo" header="Tipo">
          <template #body="{ data }">
            <Tag :severity="data.tipo === 'interno' ? 'info' : 'success'" :value="data.tipo" />
          </template>
        </Column>
        <Column header="Veículos">
          <template #body="{ data }">{{ contagemVeiculos(data) }}</template>
        </Column>
        <Column header="Ações" style="width: 140px">
          <template #body="{ data }">
            <Button icon="pi pi-pencil" text rounded @click.stop="abrirEdicao(data)" />
            <Button
              v-if="data.tipo !== 'interno'"
              icon="pi pi-ban"
              text
              rounded
              severity="danger"
              @click.stop="confirmarInativacao(data)"
            />
          </template>
        </Column>
      </DataTable>
    </div>

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Cliente' : 'Novo Cliente'" style="width: 420px">
      <div class="form-campo">
        <label>Tipo</label>
        <Select v-model="form.tipo" :options="opcoesTipo" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo">
        <label>Nome</label>
        <InputText v-model="form.nome" />
      </div>
      <div class="form-campo">
        <label>Documento (CPF/CNPJ)</label>
        <InputText v-model="form.documento" />
      </div>
      <div class="form-campo">
        <label>Telefone</label>
        <InputText v-model="form.telefone" />
      </div>
      <div class="form-campo">
        <label>E-mail</label>
        <InputText v-model="form.email" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar" :loading="salvando" @click="salvar" />
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
.pills {
  display: flex;
  gap: 8px;
}
.pill {
  padding: 7px 15px;
  border-radius: 999px;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-muted-2);
  background: transparent;
  border: none;
  cursor: pointer;
  font-family: inherit;
}
.pill-ativa {
  color: var(--text-heading);
  background: var(--accent-soft-bg-strong);
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}
.busca {
  margin-bottom: 1rem;
  max-width: 320px;
}
.panel {
  background: var(--panel-card-bg);
  border-radius: var(--card-radius);
  padding: 6px 4px;
}
.linha-nome {
  display: flex;
  align-items: center;
  gap: 10px;
}
.avatar-cliente {
  width: 28px;
  height: 28px;
  border-radius: 999px;
  flex-shrink: 0;
  display: inline-block;
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
</style>
