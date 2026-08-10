<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import Tag from 'primevue/tag'

const toast = useToast()
const confirm = useConfirm()

const ajustes = ref([])
const pecas = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)

const opcoesTipo = [
  { label: 'Entrada (soma ao estoque)', value: 'entrada' },
  { label: 'Saída / correção (subtrai do estoque)', value: 'saida' },
]

const formVazio = () => ({ peca_id: null, tipo: 'entrada', quantidade: 1, custo_unitario: 0, motivo: '' })
const form = ref(formVazio())

const pecaSelecionada = computed(() => pecas.value.find((p) => p.id === form.value.peca_id))

async function carregar() {
  carregando.value = true
  const [respAjustes, respPecas] = await Promise.all([
    supabase
      .from('ajustes_estoque')
      .select('id, tipo, quantidade, custo_unitario, motivo, criado_em, peca:pecas(sku, descricao), usuario:profiles(nome)')
      .order('criado_em', { ascending: false })
      .limit(50),
    supabase.from('pecas').select('id, sku, descricao, saldo_atual').is('deleted_at', null).order('descricao'),
  ])

  if (respAjustes.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar ajustes', detail: respAjustes.error.message, life: 5000 })
  } else {
    ajustes.value = respAjustes.data
  }
  pecas.value = respPecas.data ?? []
  carregando.value = false
}

function abrirNovo() {
  form.value = formVazio()
  dialogoAberto.value = true
}

function confirmarSalvar() {
  if (!form.value.peca_id) {
    toast.add({ severity: 'warn', summary: 'Selecione a peça', life: 4000 })
    return
  }
  if (!form.value.quantidade || form.value.quantidade <= 0) {
    toast.add({ severity: 'warn', summary: 'Informe uma quantidade maior que zero', life: 4000 })
    return
  }
  if (!form.value.motivo || !form.value.motivo.trim()) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo do ajuste', life: 4000 })
    return
  }

  const acao = form.value.tipo === 'entrada' ? 'somar' : 'subtrair'
  confirm.require({
    message: `Isso vai ${acao} ${form.value.quantidade} unidade(s) de "${pecaSelecionada.value?.descricao}" no estoque, fora do fluxo de nota fiscal. Confirma?`,
    header: 'Confirmar ajuste de estoque',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Confirmar',
    rejectLabel: 'Cancelar',
    accept: salvar,
  })
}

async function salvar() {
  salvando.value = true
  const { error } = await supabase.rpc('rpc_registrar_ajuste_estoque', {
    p_peca_id: form.value.peca_id,
    p_tipo: form.value.tipo,
    p_quantidade: form.value.quantidade,
    p_custo_unitario: form.value.tipo === 'entrada' ? form.value.custo_unitario : null,
    p_motivo: form.value.motivo,
  })
  salvando.value = false

  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar ajuste', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Ajuste registrado, estoque atualizado', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function formatarMoeda(valor) {
  return valor == null ? '—' : valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Ajustes de Estoque</h2>
      <Button label="Novo Ajuste" icon="pi pi-plus" @click="abrirNovo" />
    </div>
    <p class="hint">
      Use esta tela para registrar material recebido sem nota fiscal, ou para corrigir o saldo do sistema depois de
      uma contagem física de inventário. Toda nota fiscal real continua entrando pela tela de Entrada de NF.
    </p>

    <DataTable :value="ajustes" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column header="Peça">
        <template #body="{ data }">{{ data.peca?.sku }} — {{ data.peca?.descricao }}</template>
      </Column>
      <Column header="Tipo">
        <template #body="{ data }">
          <Tag :severity="data.tipo === 'entrada' ? 'success' : 'danger'" :value="data.tipo" />
        </template>
      </Column>
      <Column field="quantidade" header="Quantidade" />
      <Column header="Custo Unit.">
        <template #body="{ data }">{{ formatarMoeda(data.custo_unitario) }}</template>
      </Column>
      <Column field="motivo" header="Motivo" />
      <Column header="Por">
        <template #body="{ data }">{{ data.usuario?.nome }}</template>
      </Column>
      <Column header="Data">
        <template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal header="Novo Ajuste de Estoque" style="width: 480px">
      <div class="form-campo">
        <label>Peça</label>
        <Select
          v-model="form.peca_id"
          :options="pecas"
          optionLabel="descricao"
          optionValue="id"
          filter
          placeholder="Selecione a peça"
        />
        <span v-if="pecaSelecionada" class="hint">Saldo atual: {{ pecaSelecionada.saldo_atual }}</span>
      </div>
      <div class="form-campo">
        <label>Tipo de ajuste</label>
        <Select v-model="form.tipo" :options="opcoesTipo" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo">
        <label>Quantidade</label>
        <InputNumber v-model="form.quantidade" :minFractionDigits="0" :maxFractionDigits="3" />
      </div>
      <div class="form-campo" v-if="form.tipo === 'entrada'">
        <label>Custo unitário</label>
        <InputNumber v-model="form.custo_unitario" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Motivo (obrigatório)</label>
        <Textarea v-model="form.motivo" rows="3" autoResize placeholder="Ex.: material recebido sem NF do fornecedor X; ou: contagem física de 07/08 encontrou 3 unidades a menos" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Registrar Ajuste" :loading="salvando" @click="confirmarSalvar" />
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
.hint {
  color: #6b7280;
  font-size: 0.85rem;
  display: block;
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
