<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'

const toast = useToast()
const confirm = useConfirm()

const veiculos = ref([])
const clientes = ref([])
const carregando = ref(true)
const filtro = ref('')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)

const formVazio = () => ({ id: null, cliente_id: null, placa: '', prefixo: '', modelo: '', ano: null })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  const [respVeiculos, respClientes] = await Promise.all([
    supabase
      .from('veiculos')
      .select('id, placa, prefixo, modelo, ano, cliente_id, cliente:clientes(nome)')
      .is('deleted_at', null)
      .order('placa'),
    supabase.from('clientes').select('id, nome').is('deleted_at', null).order('nome'),
  ])

  if (respVeiculos.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar veículos', detail: respVeiculos.error.message, life: 5000 })
  } else {
    veiculos.value = respVeiculos.data
  }
  clientes.value = respClientes.data ?? []
  carregando.value = false
}

function abrirNovo() {
  editando.value = null
  form.value = formVazio()
  dialogoAberto.value = true
}

function abrirEdicao(veiculo) {
  editando.value = veiculo
  form.value = {
    id: veiculo.id,
    cliente_id: veiculo.cliente_id,
    placa: veiculo.placa,
    prefixo: veiculo.prefixo,
    modelo: veiculo.modelo,
    ano: veiculo.ano,
  }
  dialogoAberto.value = true
}

async function salvar() {
  salvando.value = true
  const payload = {
    cliente_id: form.value.cliente_id,
    placa: form.value.placa.toUpperCase(),
    prefixo: form.value.prefixo || null,
    modelo: form.value.modelo || null,
    ano: form.value.ano || null,
  }
  const query = editando.value
    ? supabase.from('veiculos').update(payload).eq('id', editando.value.id)
    : supabase.from('veiculos').insert(payload)

  const { error } = await query
  salvando.value = false

  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Veículo salvo', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function confirmarInativacao(veiculo) {
  confirm.require({
    message: `Inativar o veículo de placa "${veiculo.placa}"? O histórico é preservado.`,
    header: 'Confirmar inativação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Inativar',
    rejectLabel: 'Cancelar',
    accept: () => inativar(veiculo),
  })
}

async function inativar(veiculo) {
  const { error } = await supabase
    .from('veiculos')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', veiculo.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao inativar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Veículo inativado', life: 3000 })
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Veículos</h2>
      <Button label="Novo Veículo" icon="pi pi-plus" @click="abrirNovo" />
    </div>

    <IconField class="busca">
      <InputIcon class="pi pi-search" />
      <InputText v-model="filtro" placeholder="Buscar por placa, prefixo ou proprietário" />
    </IconField>

    <DataTable
      :value="veiculos"
      :loading="carregando"
      :filters="{ global: { value: filtro, matchMode: 'contains' } }"
      :globalFilterFields="['placa', 'prefixo', 'cliente.nome']"
      paginator
      :rows="15"
      dataKey="id"
      stripedRows
    >
      <Column field="placa" header="Placa" sortable />
      <Column field="prefixo" header="Prefixo" sortable />
      <Column field="modelo" header="Modelo" />
      <Column field="ano" header="Ano" />
      <Column header="Proprietário">
        <template #body="{ data }">{{ data.cliente?.nome }}</template>
      </Column>
      <Column header="Ações" style="width: 100px">
        <template #body="{ data }">
          <Button icon="pi pi-pencil" text rounded @click="abrirEdicao(data)" />
          <Button icon="pi pi-ban" text rounded severity="danger" @click="confirmarInativacao(data)" />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Veículo' : 'Novo Veículo'" style="width: 420px">
      <div class="form-campo">
        <label>Proprietário</label>
        <Select
          v-model="form.cliente_id"
          :options="clientes"
          optionLabel="nome"
          optionValue="id"
          filter
          placeholder="Selecione o cliente"
        />
      </div>
      <div class="form-campo">
        <label>Placa</label>
        <InputText v-model="form.placa" />
      </div>
      <div class="form-campo">
        <label>Prefixo (frota)</label>
        <InputText v-model="form.prefixo" />
      </div>
      <div class="form-campo">
        <label>Modelo</label>
        <InputText v-model="form.modelo" />
      </div>
      <div class="form-campo">
        <label>Ano</label>
        <InputNumber v-model="form.ano" :useGrouping="false" />
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
