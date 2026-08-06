<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Checkbox from 'primevue/checkbox'
import Tag from 'primevue/tag'

const toast = useToast()

const templates = ref([])
const carregando = ref(true)
const dialogoTemplateAberto = ref(false)
const dialogoItensAberto = ref(false)
const salvando = ref(false)
const templateAtual = ref(null)
const nomeTemplate = ref('')
const itens = ref([])

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase
    .from('checklist_templates')
    .select('id, nome, ativo, checklist_template_itens(id, descricao, obrigatorio)')
    .order('nome')
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar checklists', detail: error.message, life: 5000 })
  } else {
    templates.value = data
  }
  carregando.value = false
}

function abrirNovoTemplate() {
  nomeTemplate.value = ''
  dialogoTemplateAberto.value = true
}

async function salvarTemplate() {
  if (!nomeTemplate.value) return
  salvando.value = true
  const { error } = await supabase.from('checklist_templates').insert({ nome: nomeTemplate.value })
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao criar checklist', detail: error.message, life: 5000 })
    return
  }
  dialogoTemplateAberto.value = false
  await carregar()
}

async function alternarAtivo(template) {
  const { error } = await supabase.from('checklist_templates').update({ ativo: !template.ativo }).eq('id', template.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao atualizar', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

function abrirItens(template) {
  templateAtual.value = template
  itens.value = template.checklist_template_itens.map((i) => ({ id: i.id, descricao: i.descricao, obrigatorio: i.obrigatorio }))
  dialogoItensAberto.value = true
}

function adicionarItem() {
  itens.value.push({ id: null, descricao: '', obrigatorio: true })
}
function removerItem(index) {
  itens.value.splice(index, 1)
}

async function salvarItens() {
  salvando.value = true
  await supabase.from('checklist_template_itens').delete().eq('template_id', templateAtual.value.id)
  const payload = itens.value.filter((i) => i.descricao).map((i) => ({ template_id: templateAtual.value.id, descricao: i.descricao, obrigatorio: i.obrigatorio }))
  const { error } = payload.length ? await supabase.from('checklist_template_itens').insert(payload) : { error: null }
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar itens', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Itens salvos', life: 3000 })
  dialogoItensAberto.value = false
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Checklists Técnicos</h2>
      <Button label="Novo Checklist" icon="pi pi-plus" @click="abrirNovoTemplate" />
    </div>

    <DataTable :value="templates" :loading="carregando" dataKey="id" stripedRows>
      <Column field="nome" header="Nome" />
      <Column header="Itens"><template #body="{ data }">{{ data.checklist_template_itens.length }}</template></Column>
      <Column header="Status">
        <template #body="{ data }"><Tag :severity="data.ativo ? 'success' : 'secondary'" :value="data.ativo ? 'ativo' : 'inativo'" /></template>
      </Column>
      <Column header="Ações" style="width: 220px">
        <template #body="{ data }">
          <Button label="Itens" size="small" text @click="abrirItens(data)" />
          <Button :label="data.ativo ? 'Inativar' : 'Ativar'" size="small" text @click="alternarAtivo(data)" />
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoTemplateAberto" modal header="Novo Checklist" style="width: 420px">
      <div class="form-campo">
        <label>Nome</label>
        <InputText v-model="nomeTemplate" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoTemplateAberto = false" />
        <Button label="Criar" :loading="salvando" @click="salvarTemplate" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoItensAberto" modal :header="`Itens — ${templateAtual?.nome}`" style="width: 560px">
      <div v-for="(item, index) in itens" :key="index" class="linha-item">
        <InputText v-model="item.descricao" placeholder="Descrição do item" class="item-descricao" />
        <label class="obrigatorio-label"><Checkbox v-model="item.obrigatorio" binary /> obrigatório</label>
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerItem(index)" />
      </div>
      <Button label="Adicionar item" icon="pi pi-plus" text size="small" @click="adicionarItem" />
      <template #footer>
        <Button label="Cancelar" text @click="dialogoItensAberto = false" />
        <Button label="Salvar Itens" :loading="salvando" @click="salvarItens" />
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
.linha-item {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.5rem;
}
.item-descricao {
  flex: 1;
}
.obrigatorio-label {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.85rem;
  white-space: nowrap;
}
</style>
