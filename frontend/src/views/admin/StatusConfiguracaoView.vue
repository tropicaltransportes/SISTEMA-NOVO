<script setup>
// ETAPA 8 (RC2) — seção 2: bootstrap / configuração inicial.
// Mostra, item a item, se a configuração administrativa obrigatória do
// sistema já foi feita (rpc_status_configuracao_sistema). Não preenche nada
// sozinho — só reporta o que já existe, para que uma instalação incompleta
// nunca pareça operacional silenciosamente (ver docs/testing/TEST_REPORT_RC1.md,
// achado do anexos_config vazio após rebuild).
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import Button from 'primevue/button'

const toast = useToast()
const itens = ref([])
const carregando = ref(true)

const rotulos = {
  administrador_tecnico: 'Administrador técnico ativo',
  custo_hora_config: 'Custo/hora interno configurado',
  desconto_config: 'Teto de desconto configurado',
  anexos_config: 'Limites de anexos (fotos/comprovantes) configurados',
  centro_custo: 'Ao menos 1 centro de custo cadastrado',
  checklist_template: 'Ao menos 1 checklist template ativo',
}

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.rpc('rpc_status_configuracao_sistema')
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao consultar configuração inicial', detail: error.message, life: 6000 })
    itens.value = []
  } else {
    itens.value = data ?? []
  }
  carregando.value = false
}

const tudoConfigurado = computed(() => itens.value.length > 0 && itens.value.every((i) => i.configurado))
const pendentes = computed(() => itens.value.filter((i) => !i.configurado).length)

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Configuração Inicial do Sistema</h2>
      <Button label="Reconsultar" icon="pi pi-refresh" text @click="carregar" :loading="carregando" />
    </div>
    <p class="aviso" :class="{ 'aviso-ok': tudoConfigurado, 'aviso-pendente': !tudoConfigurado && itens.length }">
      <template v-if="carregando">Consultando...</template>
      <template v-else-if="tudoConfigurado">
        Todos os requisitos de configuração inicial estão presentes. Isso não substitui a revisão manual dos valores
        (custo/hora, teto de desconto, limites de anexos) — só confirma que eles EXISTEM.
      </template>
      <template v-else>
        {{ pendentes }} de {{ itens.length }} requisitos ainda PENDENTES. O sistema pode aparentar funcionar mesmo
        assim (nenhum valor é inventado automaticamente) — mas fluxos que dependem do item pendente vão falhar em
        runtime até um administrador técnico configurar. Ver `docs/PRODUCTION_INITIAL_CONFIGURATION.md`.
      </template>
    </p>

    <DataTable :value="itens" :loading="carregando" dataKey="item" stripedRows>
      <Column header="Requisito">
        <template #body="{ data }">{{ rotulos[data.item] ?? data.item }}</template>
      </Column>
      <Column header="Status" style="width: 160px">
        <template #body="{ data }">
          <Tag :severity="data.configurado ? 'success' : 'danger'" :value="data.configurado ? 'CONFIGURADO' : 'PENDENTE'" />
        </template>
      </Column>
      <Column header="Detalhe" field="detalhe" />
    </DataTable>
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
  padding: 0.75rem 1rem;
  border-radius: 8px;
  font-size: 0.85rem;
  margin-bottom: 1rem;
}
.aviso-ok {
  background: #dcfce7;
  color: #166534;
}
.aviso-pendente {
  background: #fef3c7;
  color: #92400e;
}
</style>
