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
import DatePicker from 'primevue/datepicker'
import Select from 'primevue/select'
import Tag from 'primevue/tag'

const toast = useToast()
const confirm = useConfirm()

const notas = ref([])
const pecas = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)
const nfEmEdicao = ref(null)

const severidadeStatus = { rascunho: 'warn', confirmada: 'success', estornada: 'danger' }

const formVazio = () => ({ numero: '', fornecedor: '', data_emissao: new Date() })
const form = ref(formVazio())
const itens = ref([]) // { peca_id, quantidade, valor_unitario }

async function carregar() {
  carregando.value = true
  const [respNotas, respPecas] = await Promise.all([
    supabase
      .from('notas_fiscais_entrada')
      .select('id, numero, fornecedor, status, data_emissao, nf_entrada_itens(id, peca_id, quantidade, valor_unitario, pecas(descricao))')
      .order('criado_em', { ascending: false }),
    supabase.from('pecas').select('id, sku, descricao').is('deleted_at', null).order('descricao'),
  ])

  if (respNotas.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar notas', detail: respNotas.error.message, life: 5000 })
  } else {
    notas.value = respNotas.data
  }
  pecas.value = respPecas.data ?? []
  carregando.value = false
}

function abrirNova() {
  nfEmEdicao.value = null
  form.value = formVazio()
  itens.value = [{ peca_id: null, quantidade: 1, valor_unitario: 0 }]
  dialogoAberto.value = true
}

function abrirEdicaoRascunho(nf) {
  nfEmEdicao.value = nf
  form.value = { numero: nf.numero, fornecedor: nf.fornecedor, data_emissao: new Date(nf.data_emissao) }
  itens.value = nf.nf_entrada_itens.map((i) => ({ id: i.id, peca_id: i.peca_id, quantidade: i.quantidade, valor_unitario: i.valor_unitario }))
  dialogoAberto.value = true
}

function adicionarItem() {
  itens.value.push({ peca_id: null, quantidade: 1, valor_unitario: 0 })
}

function removerItem(index) {
  itens.value.splice(index, 1)
}

async function salvar() {
  if (itens.value.length === 0 || itens.value.some((i) => !i.peca_id || i.quantidade <= 0)) {
    toast.add({ severity: 'warn', summary: 'Revise os itens', detail: 'Cada item precisa de peça e quantidade maior que zero.', life: 4000 })
    return
  }

  salvando.value = true
  const payloadNf = {
    numero: form.value.numero,
    fornecedor: form.value.fornecedor,
    data_emissao: form.value.data_emissao.toISOString().slice(0, 10),
  }

  let nfId = nfEmEdicao.value?.id

  if (nfEmEdicao.value) {
    const { error } = await supabase.from('notas_fiscais_entrada').update(payloadNf).eq('id', nfId)
    if (error) {
      salvando.value = false
      toast.add({ severity: 'error', summary: 'Erro ao salvar cabeçalho', detail: error.message, life: 5000 })
      return
    }
    // Substitui os itens: remove os antigos e insere os atuais (só é possível em rascunho).
    await supabase.from('nf_entrada_itens').delete().eq('nf_id', nfId)
  } else {
    const { data, error } = await supabase.from('notas_fiscais_entrada').insert(payloadNf).select('id').single()
    if (error) {
      salvando.value = false
      toast.add({ severity: 'error', summary: 'Erro ao criar nota', detail: error.message, life: 5000 })
      return
    }
    nfId = data.id
  }

  const itensPayload = itens.value.map((i) => ({
    nf_id: nfId,
    peca_id: i.peca_id,
    quantidade: i.quantidade,
    valor_unitario: i.valor_unitario,
  }))
  const { error: erroItens } = await supabase.from('nf_entrada_itens').insert(itensPayload)
  salvando.value = false

  if (erroItens) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar itens', detail: erroItens.message, life: 5000 })
    return
  }

  toast.add({ severity: 'success', summary: 'Nota fiscal salva em rascunho', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function confirmarTransicao(nf, acao) {
  const textos = {
    confirmar: { msg: `Confirmar a nota ${nf.numero}? Isso dará entrada definitiva no estoque e recalculará o custo médio.`, fn: rpcConfirmar },
    estornar: { msg: `Estornar a nota ${nf.numero}? Isso reverterá a entrada no estoque.`, fn: rpcEstornar },
  }
  const t = textos[acao]
  confirm.require({
    message: t.msg,
    header: 'Confirmar ação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Confirmar',
    rejectLabel: 'Cancelar',
    accept: () => t.fn(nf),
  })
}

async function rpcConfirmar(nf) {
  const { error } = await supabase.rpc('rpc_confirmar_nf_entrada', { p_nf_id: nf.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao confirmar', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Nota confirmada, estoque atualizado', life: 3000 })
  await carregar()
}

async function rpcEstornar(nf) {
  const { error } = await supabase.rpc('rpc_estornar_nf_entrada', { p_nf_id: nf.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao estornar', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Nota estornada, estoque revertido', life: 3000 })
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Entrada de Notas Fiscais</h2>
      <Button label="Nova Nota" icon="pi pi-plus" @click="abrirNova" />
    </div>

    <DataTable :value="notas" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column field="numero" header="Número" />
      <Column field="fornecedor" header="Fornecedor" />
      <Column field="data_emissao" header="Emissão" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Ações" style="width: 220px">
        <template #body="{ data }">
          <Button v-if="data.status === 'rascunho'" icon="pi pi-pencil" text rounded @click="abrirEdicaoRascunho(data)" />
          <Button
            v-if="data.status === 'rascunho'"
            label="Confirmar"
            size="small"
            severity="success"
            @click="confirmarTransicao(data, 'confirmar')"
          />
          <Button
            v-if="data.status === 'confirmada'"
            label="Estornar"
            size="small"
            severity="danger"
            @click="confirmarTransicao(data, 'estornar')"
          />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal :header="nfEmEdicao ? 'Editar Nota (rascunho)' : 'Nova Nota Fiscal'" style="width: 640px">
      <div class="linha-form">
        <div class="form-campo">
          <label>Número</label>
          <InputText v-model="form.numero" />
        </div>
        <div class="form-campo">
          <label>Fornecedor</label>
          <InputText v-model="form.fornecedor" />
        </div>
        <div class="form-campo">
          <label>Data de Emissão</label>
          <DatePicker v-model="form.data_emissao" dateFormat="dd/mm/yy" />
        </div>
      </div>

      <h4>Itens</h4>
      <div v-for="(item, index) in itens" :key="index" class="linha-item">
        <Select
          v-model="item.peca_id"
          :options="pecas"
          optionLabel="descricao"
          optionValue="id"
          filter
          placeholder="Peça"
          class="item-peca"
        />
        <InputNumber v-model="item.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" class="item-qtd" />
        <InputNumber
          v-model="item.valor_unitario"
          placeholder="Valor Unit."
          mode="currency"
          currency="BRL"
          locale="pt-BR"
          class="item-valor"
        />
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerItem(index)" />
      </div>
      <Button label="Adicionar item" icon="pi pi-plus" text size="small" @click="adicionarItem" />

      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar Rascunho" :loading="salvando" @click="salvar" />
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
.linha-form {
  display: flex;
  gap: 1rem;
  margin-bottom: 1rem;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  flex: 1;
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
  flex: 2;
}
.item-qtd,
.item-valor {
  flex: 1;
}
</style>
