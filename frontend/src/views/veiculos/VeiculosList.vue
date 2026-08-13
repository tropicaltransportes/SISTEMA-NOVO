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
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import Menu from 'primevue/menu'

const toast = useToast()
const confirm = useConfirm()
const router = useRouter()

const veiculos = ref([])
const clientes = ref([])
const carregando = ref(true)
const erro = ref(false)
const filtro = ref('')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)
const temFiltroAtivo = computed(() => filtro.value.trim() !== '')

const formVazio = () => ({ id: null, cliente_id: null, placa: '', prefixo: '', modelo: '', ano: null })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  erro.value = false
  const [respVeiculos, respClientes] = await Promise.all([
    supabase
      .from('veiculos')
      .select('id, placa, prefixo, modelo, ano, cliente_id, cliente:clientes(nome)')
      .is('deleted_at', null)
      .order('placa'),
    supabase.from('clientes').select('id, nome').is('deleted_at', null).order('nome'),
  ])

  if (respVeiculos.error) {
    erro.value = true
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

// ETAPA UX-VEICULOS-01 — reorganiza visualmente "Histórico" e "Inativar"
// (ambas já existentes) num menu de três pontos, no mesmo padrão adotado em
// ClientesList.vue; nenhuma ação nova foi criada.
const menuAcoes = ref()
const veiculoMenuAtual = ref(null)
const itensMenuAcoes = computed(() => [
  {
    label: 'Histórico',
    icon: 'pi pi-history',
    command: () => veiculoMenuAtual.value && router.push('/veiculos/' + veiculoMenuAtual.value.id + '/historico'),
  },
  {
    label: 'Inativar',
    icon: 'pi pi-ban',
    command: () => veiculoMenuAtual.value && confirmarInativacao(veiculoMenuAtual.value),
  },
])
function abrirMenuAcoes(event, veiculo) {
  veiculoMenuAtual.value = veiculo
  menuAcoes.value.toggle(event)
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="pagina-cabecalho-linha">
      <div class="pagina-cabecalho">
        <h1 class="pagina-titulo">Veículos</h1>
        <p class="pagina-subtitulo">Gerencie os veículos cadastrados na oficina.</p>
      </div>
      <Button label="Novo Veículo" icon="pi pi-plus" class="btn-gradiente" @click="abrirNovo" />
    </div>

    <div class="cabecalho">
      <IconField class="busca">
        <InputIcon class="pi pi-search" />
        <InputText v-model="filtro" placeholder="Buscar por placa, prefixo ou modelo" />
      </IconField>
    </div>

    <div class="panel">
      <DataTable
        :value="veiculos"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['placa', 'prefixo', 'modelo', 'cliente.nome']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        paginatorTemplate="CurrentPageReport FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink"
        currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} veículos"
      >
        <Column field="placa" header="Placa" sortable>
          <template #body="{ data }"><span class="placa-destaque">{{ data.placa }}</span></template>
        </Column>
        <Column field="prefixo" header="Prefixo" sortable>
          <template #body="{ data }">{{ data.prefixo || '—' }}</template>
        </Column>
        <Column field="modelo" header="Modelo">
          <template #body="{ data }"><span :title="data.modelo">{{ data.modelo || '—' }}</span></template>
        </Column>
        <Column field="ano" header="Ano" style="width: 90px" bodyClass="col-numero" />
        <Column header="Proprietário">
          <template #body="{ data }">{{ data.cliente?.nome || '—' }}</template>
        </Column>
        <Column header="Ações" style="width: 100px">
          <template #body="{ data }">
            <div class="acoes-linha">
              <Button icon="pi pi-pencil" text rounded size="small" aria-label="Editar" @click="abrirEdicao(data)" />
              <Button icon="pi pi-ellipsis-v" text rounded size="small" aria-label="Mais ações" @click="abrirMenuAcoes($event, data)" />
            </div>
          </template>
        </Column>

        <template #empty>
          <div class="estado-vazio-tabela">
            <i class="pi" :class="erro ? 'pi-exclamation-triangle' : 'pi-car'"></i>
            <p v-if="erro">Não foi possível carregar os veículos.</p>
            <p v-else-if="temFiltroAtivo">Nenhum veículo encontrado para esta busca.</p>
            <p v-else>Nenhum veículo cadastrado.</p>
            <Button v-if="!erro" label="Novo Veículo" icon="pi pi-plus" size="small" @click="abrirNovo" />
          </div>
        </template>
      </DataTable>
    </div>

    <Menu ref="menuAcoes" :model="itensMenuAcoes" :popup="true" />

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Veículo' : 'Novo Veículo'" style="width: 420px">
      <div class="bloco-form">
        <span class="bloco-form-titulo">Identificação</span>
        <div class="form-campo">
          <label>Placa</label>
          <InputText v-model="form.placa" />
        </div>
        <div class="form-campo">
          <label>Prefixo (frota)</label>
          <InputText v-model="form.prefixo" />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Veículo</span>
        <div class="form-campo">
          <label>Modelo</label>
          <InputText v-model="form.modelo" />
        </div>
        <div class="form-campo">
          <label>Ano</label>
          <InputNumber v-model="form.ano" :useGrouping="false" />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Vínculo</span>
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
      </div>

      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar" :loading="salvando" @click="salvar" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
/* ETAPA UX-VEICULOS-01 — mesma linguagem visual de ClientesList.vue
   (item 25: telas irmãs). Duplicado aqui em vez de extraído para uma folha
   compartilhada para não tocar num arquivo de uma etapa já entregue
   (ver MELHORIAS FUTURAS no relatório desta etapa). */
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

:deep(.col-numero) {
  text-align: center;
}

.acoes-linha {
  display: flex;
  align-items: center;
  gap: 2px;
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
  margin-bottom: 16px;
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
