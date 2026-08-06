<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Tag from 'primevue/tag'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'

const toast = useToast()
const auth = useAuthStore()

const podeGerenciar = () => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const pecas = ref([])
const carregando = ref(true)
const filtro = ref('')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)

const formVazio = () => ({ id: null, sku: '', descricao: '', unidade: 'UN', estoque_minimo: 0 })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase
    .from('pecas')
    .select('id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo')
    .is('deleted_at', null)
    .order('descricao')
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar peças', detail: error.message, life: 5000 })
  } else {
    pecas.value = data
  }
  carregando.value = false
}

function abrirNovo() {
  editando.value = null
  form.value = formVazio()
  dialogoAberto.value = true
}

function abrirEdicao(peca) {
  editando.value = peca
  form.value = { id: peca.id, sku: peca.sku, descricao: peca.descricao, unidade: peca.unidade, estoque_minimo: peca.estoque_minimo }
  dialogoAberto.value = true
}

async function salvar() {
  salvando.value = true
  const payload = {
    sku: form.value.sku,
    descricao: form.value.descricao,
    unidade: form.value.unidade,
    estoque_minimo: form.value.estoque_minimo ?? 0,
  }
  const query = editando.value
    ? supabase.from('pecas').update(payload).eq('id', editando.value.id)
    : supabase.from('pecas').insert(payload)

  const { error } = await query
  salvando.value = false

  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Peça salva', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Peças</h2>
      <Button v-if="podeGerenciar()" label="Nova Peça" icon="pi pi-plus" @click="abrirNovo" />
    </div>

    <IconField class="busca">
      <InputIcon class="pi pi-search" />
      <InputText v-model="filtro" placeholder="Buscar por SKU ou descrição" />
    </IconField>

    <DataTable
      :value="pecas"
      :loading="carregando"
      :filters="{ global: { value: filtro, matchMode: 'contains' } }"
      :globalFilterFields="['sku', 'descricao']"
      paginator
      :rows="15"
      dataKey="id"
      stripedRows
    >
      <Column field="sku" header="SKU" sortable />
      <Column field="descricao" header="Descrição" sortable />
      <Column field="unidade" header="UN" />
      <Column header="Saldo" sortable sortField="saldo_atual">
        <template #body="{ data }">
          <Tag :severity="data.saldo_atual <= data.estoque_minimo ? 'danger' : 'success'">
            {{ data.saldo_atual }}
          </Tag>
        </template>
      </Column>
      <Column field="estoque_minimo" header="Mínimo" />
      <Column header="Custo Médio">
        <template #body="{ data }">{{ formatarMoeda(data.custo_medio) }}</template>
      </Column>
      <Column v-if="podeGerenciar()" header="Ações" style="width: 80px">
        <template #body="{ data }">
          <Button icon="pi pi-pencil" text rounded @click="abrirEdicao(data)" />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Peça' : 'Nova Peça'" style="width: 420px">
      <div class="form-campo">
        <label>SKU</label>
        <InputText v-model="form.sku" :disabled="!!editando" />
      </div>
      <div class="form-campo">
        <label>Descrição</label>
        <InputText v-model="form.descricao" />
      </div>
      <div class="form-campo">
        <label>Unidade</label>
        <InputText v-model="form.unidade" />
      </div>
      <div class="form-campo">
        <label>Estoque Mínimo</label>
        <InputNumber v-model="form.estoque_minimo" :minFractionDigits="0" :maxFractionDigits="3" />
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
.busca {
  margin-bottom: 1rem;
  max-width: 320px;
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
