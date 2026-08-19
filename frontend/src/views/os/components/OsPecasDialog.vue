<script setup>
import { ref, watch } from 'vue'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import InputNumber from 'primevue/inputnumber'
import Button from 'primevue/button'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'

// OS-UX-02 — conteúdo movido da antiga aba "Peças" para dialog sob demanda
// (item 19 do pedido). Mesma RPC (rpc_baixar_peca_os), mesmos parâmetros —
// só o formulário de baixa passou a viver localmente neste componente em
// vez de um ref do pai (o pai só recebe o payload já resolvido).
const props = defineProps({
  movimentos: { type: Array, default: () => [] },
  pecas: { type: Array, default: () => [] },
  itensParaBaixa: { type: Array, default: () => [] },
  podeBaixarPeca: Boolean,
  podeMovimentarEstoque: Boolean,
  podeBaixarLivre: Boolean,
  baixarPeca: { type: Function, required: true },
})

const visible = defineModel('visible', { default: false })

const form = ref({ chave: null, peca_id: null, quantidade: 1 })
watch(visible, (v) => {
  if (v) form.value = { chave: null, peca_id: null, quantidade: 1 }
})

function selecionouItem() {
  const item = props.itensParaBaixa.find((i) => i.chave === form.value.chave)
  form.value.peca_id = item?.peca_id ?? null
}

async function confirmarBaixa() {
  await props.baixarPeca({ chave: form.value.chave, peca_id: form.value.peca_id, quantidade: form.value.quantidade })
  form.value = { chave: null, peca_id: null, quantidade: 1 }
}
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Peças" style="width: 640px">
    <div class="form-linha" v-if="podeBaixarPeca && podeMovimentarEstoque && itensParaBaixa.length > 0">
      <Select
        v-model="form.chave"
        :options="itensParaBaixa"
        optionLabel="descricao"
        optionValue="chave"
        filter
        placeholder="Item aprovado (orçamento/adicional/garantia)"
        @update:modelValue="selecionouItem"
      >
        <template #option="{ option }">
          <Tag v-if="option.origem === 'adicional'" severity="warn" value="adicional" style="margin-right:0.3rem;font-size:0.65rem" />
          {{ option.descricao }} — {{ option.peca?.descricao }} (restam {{ option.restante }} de {{ option.quantidade }})
        </template>
      </Select>
      <InputNumber v-model="form.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
      <Button label="Baixar" size="small" @click="confirmarBaixa" :disabled="!form.chave" />
    </div>
    <p v-else-if="podeBaixarPeca && podeMovimentarEstoque && !podeBaixarLivre" class="hint">
      Nenhum item de peça aprovado (orçamento/adicional) disponível para baixa nesta OS.
    </p>
    <div class="form-linha" v-else-if="podeBaixarPeca && podeMovimentarEstoque">
      <Select v-model="form.peca_id" :options="pecas" optionLabel="descricao" optionValue="id" filter placeholder="Peça" />
      <InputNumber v-model="form.quantidade" :minFractionDigits="0" :maxFractionDigits="3" placeholder="Qtde" />
      <Button label="Baixar" size="small" @click="confirmarBaixa" />
    </div>
    <p v-else-if="podeBaixarPeca" class="hint">Baixa de peças só é permitida com a OS em diagnóstico ou execução.</p>

    <div v-if="movimentos.length === 0" class="estado-vazio-card">
      <i class="pi pi-box"></i>
      <div>
        <strong>Nenhuma peça baixada</strong>
        <p>Peças utilizadas nesta OS aparecerão aqui assim que forem baixadas do estoque.</p>
      </div>
    </div>
    <DataTable v-else :value="movimentos" dataKey="id" size="small">
      <Column header="Peça"><template #body="{ data }">{{ data.peca?.descricao }} ({{ data.peca?.sku }})</template></Column>
      <Column field="quantidade" header="Qtde" />
      <Column header="Origem">
        <template #body="{ data }">
          <Tag v-if="data.os_adicional_item_id" severity="warn" value="adicional" />
          <Tag v-else-if="data.orcamento_item_id" severity="info" value="orçamento" />
          <span v-else class="hint">avulsa</span>
        </template>
      </Column>
      <Column header="Custo Unit."><template #body="{ data }">{{ (data.custo_unitario ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</template></Column>
      <Column header="Data"><template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template></Column>
    </DataTable>
  </Dialog>
</template>

<style scoped>
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.75rem;
  flex-wrap: wrap;
}
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
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
