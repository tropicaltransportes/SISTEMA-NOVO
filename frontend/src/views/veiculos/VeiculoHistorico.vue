<script setup>
// ETAPA 6 (P1-C) — item 7 (CAD-012): histórico cronológico do veículo.
// Consulta rpc_historico_veiculo (leitura, agrega dados já existentes —
// não duplica nada). Permite navegar do histórico para a OS correspondente.
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()

const veiculoId = computed(() => route.params.id)
const dados = ref(null)
const carregando = ref(true)

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(v) {
  return v ? new Date(v).toLocaleString('pt-BR') : '—'
}

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.rpc('rpc_historico_veiculo', { p_veiculo_id: veiculoId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar histórico', detail: error.message, life: 6000 })
    carregando.value = false
    return
  }
  dados.value = data
  carregando.value = false
}

carregar()
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/veiculos')" />
      <Button label="Imprimir / PDF" icon="pi pi-print" size="small" @click="window.print()" />
    </div>
    <div v-if="carregando">Carregando...</div>
    <div v-else-if="dados">
      <h2>Histórico do Veículo — {{ dados.veiculo.placa }} <span v-if="dados.veiculo.prefixo">({{ dados.veiculo.prefixo }})</span></h2>
      <p class="hint">{{ dados.veiculo.modelo }} <span v-if="dados.veiculo.ano">— {{ dados.veiculo.ano }}</span></p>

      <h3>Ordens de Serviço ({{ dados.ordens_servico.length }})</h3>
      <table class="tabela-relatorio">
        <thead>
          <tr>
            <th>Abertura</th><th>Tipo</th><th>Status</th><th>Previsão</th><th>Liberação</th>
            <th>Custo/Valor</th><th>Executores</th><th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="os in dados.ordens_servico" :key="os.os_id">
            <td>{{ formatarData(os.data_abertura) }}</td>
            <td>
              {{ os.tipo }}
              <Tag v-if="os.e_garantia_de" severity="warn" value="garantia" style="margin-left:0.3rem;font-size:0.65rem" />
            </td>
            <td><Tag :value="os.status" /></td>
            <td>{{ formatarData(os.previsao_conclusao) }}</td>
            <td>{{ formatarData(os.data_liberacao) }}</td>
            <td>
              <span v-if="os.tipo === 'interna'">Custo: {{ formatarMoeda(os.custo_total) }}</span>
              <span v-else>Faturado: {{ formatarMoeda(os.valor_faturado) }}</span>
            </td>
            <td>{{ (os.executores || []).join(', ') }}</td>
            <td class="no-print"><Button label="Abrir" size="small" text @click="router.push('/os/' + os.os_id)" /></td>
          </tr>
        </tbody>
      </table>

      <h3>Orçamentos ({{ dados.orcamentos.length }})</h3>
      <table class="tabela-relatorio">
        <thead><tr><th>Versão</th><th>Status</th><th>Valor Total</th><th>Criado em</th></tr></thead>
        <tbody>
          <tr v-for="o in dados.orcamentos" :key="o.id">
            <td>V{{ o.versao }}</td>
            <td><Tag :value="o.status" /></td>
            <td>{{ formatarMoeda(o.valor_total) }}</td>
            <td>{{ formatarData(o.criado_em) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-if="dados.ordens_servico.length === 0 && dados.orcamentos.length === 0" class="hint">Nenhum histórico registrado para este veículo ainda.</p>
      <p class="hint">Quilometragem: não rastreada no sistema atual (nenhuma tabela registra odômetro por veículo/OS).</p>
    </div>
  </div>
</template>

<style scoped>
.pagina-relatorio { max-width: 900px; }
.acoes-topo { display: flex; justify-content: space-between; margin-bottom: 1rem; }
.tabela-relatorio { width: 100%; border-collapse: collapse; margin: 0.75rem 0 1.5rem; }
.tabela-relatorio th, .tabela-relatorio td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #e5e7eb; font-size: 0.85rem; }
.hint { color: #6b7280; font-size: 0.85rem; }
@media print {
  .no-print { display: none !important; }
}
</style>
