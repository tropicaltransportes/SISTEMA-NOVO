<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputNumber from 'primevue/inputnumber'
import Tag from 'primevue/tag'

const toast = useToast()

const faixas = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)

const formVazio = () => ({ valor_min: 0, valor_max: null, percentual_max: 0 })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.from('orcamento_faixa_acrescimo').select('*').order('valor_min')
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar faixas', detail: error.message, life: 5000 })
  } else {
    faixas.value = data
  }
  carregando.value = false
}

function abrirNova() {
  form.value = formVazio()
  dialogoAberto.value = true
}

async function salvar() {
  salvando.value = true
  const { error } = await supabase.from('orcamento_faixa_acrescimo').insert({
    valor_min: form.value.valor_min,
    valor_max: form.value.valor_max,
    percentual_max: form.value.percentual_max,
  })
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar faixa', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Faixa salva', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

async function alternarAtivo(faixa) {
  const { error } = await supabase.from('orcamento_faixa_acrescimo').update({ ativo: !faixa.ativo }).eq('id', faixa.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao atualizar', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Faixas de Acréscimo Pós-Orçamento</h2>
      <Button label="Nova Faixa" icon="pi pi-plus" @click="abrirNova" />
    </div>
    <p class="aviso">
      Pendência da diretoria: valores reais ainda não definidos. Enquanto não houver faixa ativa cobrindo o valor de um
      orçamento, a RPC de acréscimo bloqueia o lançamento (comportamento seguro por padrão). Teto absoluto fixo de
      R$ 5.000,00 sempre se aplica, independente da faixa.
    </p>

    <DataTable :value="faixas" :loading="carregando" dataKey="id" stripedRows>
      <Column header="Valor Mín."><template #body="{ data }">{{ data.valor_min.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</template></Column>
      <Column header="Valor Máx.">
        <template #body="{ data }">{{ data.valor_max != null ? data.valor_max.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) : 'sem limite' }}</template>
      </Column>
      <Column header="Percentual Máx."><template #body="{ data }">{{ data.percentual_max }}%</template></Column>
      <Column header="Status">
        <template #body="{ data }"><Tag :severity="data.ativo ? 'success' : 'secondary'" :value="data.ativo ? 'ativa' : 'inativa'" /></template>
      </Column>
      <Column header="Ações" style="width: 120px">
        <template #body="{ data }">
          <Button :label="data.ativo ? 'Inativar' : 'Ativar'" size="small" text @click="alternarAtivo(data)" />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal header="Nova Faixa de Acréscimo" style="width: 420px">
      <div class="form-campo">
        <label>Valor Mínimo</label>
        <InputNumber v-model="form.valor_min" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Valor Máximo (vazio = sem limite)</label>
        <InputNumber v-model="form.valor_max" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Percentual Máximo de Acréscimo</label>
        <InputNumber v-model="form.percentual_max" suffix="%" :minFractionDigits="0" :maxFractionDigits="2" />
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
.aviso {
  background: #fef3c7;
  color: #92400e;
  padding: 0.75rem 1rem;
  border-radius: 8px;
  font-size: 0.85rem;
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
