<script setup>
// ETAPA 6 (P1-C) — item 5 (GAR-007): relatório de garantia.
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const osId = computed(() => route.params.id)
const r = ref(null)
const carregando = ref(true)

function formatarData(v) { return v ? new Date(v).toLocaleString('pt-BR') : '—' }

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.rpc('rpc_relatorio_garantia_os', { p_os_garantia_id: osId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar relatório de garantia', detail: error.message, life: 6000 })
    carregando.value = false
    return
  }
  r.value = data
  carregando.value = false
}
carregar()
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/os/' + osId)" />
      <Button label="Imprimir / PDF" icon="pi pi-print" size="small" @click="window.print()" />
    </div>
    <div v-if="carregando">Carregando...</div>
    <div v-else-if="r">
      <h2>Relatório de Garantia — {{ r.veiculo.placa }}</h2>
      <p><strong>Cliente:</strong> {{ r.cliente.nome }}</p>
      <p><strong>OS de garantia:</strong> {{ r.os_garantia.id }} (<Tag :value="r.os_garantia.status" />)</p>
      <p>
        <strong>OS original:</strong>
        <router-link :to="'/os/' + r.os_original.id">{{ r.os_original.id }}</router-link>
        — liberada em {{ formatarData(r.os_original.data_liberacao) }}
      </p>
      <p><strong>Prazo de garantia:</strong> {{ r.prazo_garantia_dias }} dias — expira em {{ formatarData(r.prazo_garantia_expira_em) }}</p>

      <h3>Itens originais objeto da garantia</h3>
      <ul>
        <li v-for="(i, idx) in r.itens_originais_objeto_garantia" :key="idx">{{ i.descricao }} ({{ i.quantidade }}) — {{ i.motivo }}</li>
      </ul>
      <p v-if="!r.itens_originais_objeto_garantia.length" class="hint">Nenhum item original vinculado.</p>

      <h3>Itens de adicional objeto da garantia</h3>
      <ul>
        <li v-for="(i, idx) in r.itens_adicionais_objeto_garantia" :key="idx">{{ i.descricao }} ({{ i.quantidade }}) — {{ i.motivo }}</li>
      </ul>
      <p v-if="!r.itens_adicionais_objeto_garantia.length" class="hint">Nenhum item de adicional vinculado.</p>

      <h3>Execução realizada</h3>
      <ul>
        <li v-for="(e, idx) in r.execucao_realizada" :key="idx">Peça {{ e.peca_id }} — {{ e.quantidade }} — {{ formatarData(e.criado_em) }}</li>
      </ul>

      <h3>Responsáveis</h3>
      <ul>
        <li v-for="(p, idx) in r.responsaveis" :key="idx">{{ p.nome }} — {{ formatarData(p.inicio) }} a {{ formatarData(p.fim) }}</li>
      </ul>

      <h3>Conclusão</h3>
      <p>Status: <Tag :value="r.conclusao.status" /> — Liberação: {{ formatarData(r.conclusao.data_liberacao) }}</p>
    </div>
  </div>
</template>

<style scoped>
.pagina-relatorio { max-width: 900px; }
.acoes-topo { display: flex; justify-content: space-between; margin-bottom: 1rem; }
.hint { color: #6b7280; font-size: 0.85rem; }
@media print { .no-print { display: none !important; } }
</style>
