<script setup>
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import Checkbox from 'primevue/checkbox'
import Tag from 'primevue/tag'

// OS-UX-02 — conteúdo movido da antiga aba "Visão Geral" (bloco Checklist
// Técnico) para um dialog sob demanda (item 18 do pedido). Mesma RPC
// (rpc_definir_checklist_os) e mesma escrita direta em tabela
// (os_checklist_respostas upsert) do arquivo original.
defineProps({
  checklistTemplateId: { type: [String, Number], default: null },
  checklistItens: { type: Array, default: () => [] },
  checklistTemplates: { type: Array, default: () => [] },
  podeResponderChecklist: Boolean,
  podeTransicionar: Boolean,
  respostaDoItem: { type: Function, required: true },
  definirChecklist: { type: Function, required: true },
  alternarResposta: { type: Function, required: true },
})

const visible = defineModel('visible', { default: false })
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Checklist" style="width: 520px">
    <div v-if="!checklistTemplateId && podeTransicionar" class="form-linha">
      <Select :options="checklistTemplates" optionLabel="nome" optionValue="id" placeholder="Definir checklist" @update:modelValue="definirChecklist" />
    </div>
    <div v-else-if="!checklistTemplateId" class="estado-vazio-card">
      <i class="pi pi-list-check"></i>
      <div>
        <strong>Nenhum checklist definido</strong>
        <p>Um encarregado ou administrador técnico precisa vincular um checklist a esta OS.</p>
      </div>
    </div>
    <ul v-else class="checklist">
      <li v-for="item in checklistItens" :key="item.id">
        <Checkbox
          :modelValue="respostaDoItem(item.id)?.ok ?? false"
          binary
          :disabled="!podeResponderChecklist"
          @update:modelValue="(v) => alternarResposta(item, v)"
        />
        <span>{{ item.descricao }}</span>
        <Tag v-if="item.obrigatorio" severity="danger" value="obrigatório" />
      </li>
    </ul>
  </Dialog>
</template>

<style scoped>
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  flex-wrap: wrap;
}
.checklist {
  list-style: none;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  margin: 0;
}
.checklist li {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.estado-vazio-card {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 16px 4px;
  color: var(--text-faint);
}
.estado-vazio-card i {
  font-size: 22px;
  margin-top: 2px;
}
.estado-vazio-card strong {
  display: block;
  color: var(--text-secondary);
  font-size: 13px;
  margin-bottom: 2px;
}
.estado-vazio-card p {
  margin: 0;
  font-size: 12.5px;
  line-height: 1.4;
}
</style>
