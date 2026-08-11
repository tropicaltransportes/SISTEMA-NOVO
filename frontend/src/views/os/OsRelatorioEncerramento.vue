<script setup>
// ETAPA 6 (P1-C) — item 4 (CON-005/CON-006/DOC-003): relatório de
// encerramento. Consulta rpc_relatorio_encerramento_os — representação dos
// dados já registrados, não altera a OS.
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

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(v) {
  return v ? new Date(v).toLocaleString('pt-BR') : '—'
}

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.rpc('rpc_relatorio_encerramento_os', { p_os_id: osId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar relatório', detail: error.message, life: 6000 })
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
      <h2>Relatório de Encerramento — OS {{ r.veiculo.placa }}</h2>
      <p><strong>Cliente:</strong> {{ r.cliente.nome }} ({{ r.cliente.tipo }}) &nbsp;|&nbsp; <strong>Veículo:</strong> {{ r.veiculo.modelo }} — {{ r.veiculo.placa }}</p>
      <p><strong>Abertura:</strong> {{ formatarData(r.os.data_abertura) }} &nbsp;|&nbsp; <strong>Previsão:</strong> {{ formatarData(r.os.previsao_conclusao) }} &nbsp;|&nbsp; <strong>Liberação:</strong> {{ formatarData(r.os.data_liberacao) }}</p>
      <p><strong>Status:</strong> <Tag :value="r.os.status" /> &nbsp;|&nbsp; <strong>Tipo:</strong> {{ r.os.tipo }}</p>

      <template v-if="r.os.tipo === 'interna'">
        <h3>Custo Interno</h3>
        <p>Peças: {{ formatarMoeda(r.os.custo_pecas) }} &nbsp;+&nbsp; Mão de obra: {{ formatarMoeda(r.os.custo_mao_obra) }} ({{ r.os.horas_apontadas_total }}h × {{ formatarMoeda(r.os.custo_hora_aplicado) }}) &nbsp;=&nbsp; <strong>Total: {{ formatarMoeda(r.os.custo_total) }}</strong></p>
      </template>
      <template v-else>
        <h3>Cobrança</h3>
        <p v-if="r.cobranca">Valor: {{ formatarMoeda(r.cobranca.valor_total) }} — Status: <Tag :value="r.cobranca.status" /></p>
        <p v-else class="hint">Nenhuma cobrança vinculada.</p>
      </template>

      <h3>Orçamento Original</h3>
      <table class="tabela-relatorio" v-if="r.orcamento_original">
        <thead><tr><th>Item</th><th>Qtde</th><th>Valor Unit.</th><th>Decisão</th><th>Execução</th></tr></thead>
        <tbody>
          <tr v-for="i in r.orcamento_original.itens" :key="i.id">
            <td>{{ i.descricao }}</td><td>{{ i.quantidade }}</td><td>{{ formatarMoeda(i.valor_unitario) }}</td>
            <td><Tag :severity="i.status_aprovacao === 'aprovado' ? 'success' : i.status_aprovacao === 'rejeitado' ? 'danger' : 'warn'" :value="i.status_aprovacao" /></td>
            <td>{{ i.execucao_status }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="hint">OS sem orçamento (interna).</p>

      <h3>Adicionais</h3>
      <div v-for="a in r.adicionais" :key="a.id">
        <p><strong>AD-{{ String(a.numero).padStart(3, '0') }}</strong> — {{ a.motivo }} (<Tag :value="a.status" />)</p>
        <table class="tabela-relatorio">
          <tbody>
            <tr v-for="i in a.itens" :key="i.id">
              <td>{{ i.descricao }}</td><td>{{ i.quantidade }}</td><td>{{ formatarMoeda(i.valor_total) }}</td>
              <td><Tag :severity="i.status_aprovacao === 'aprovado' ? 'success' : i.status_aprovacao === 'rejeitado' ? 'danger' : 'warn'" :value="i.status_aprovacao" /></td>
              <td>{{ i.execucao_status }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="r.adicionais.length === 0" class="hint">Nenhum adicional.</p>

      <h3>Executores</h3>
      <ul>
        <li v-for="e in r.executores" :key="e.usuario_id">
          {{ e.nome }} — {{ e.etapa }} — {{ formatarData(e.inicio) }} a {{ formatarData(e.fim) }} ({{ e.horas ?? '—' }}h)
          <Tag v-if="!e.ativo" severity="danger" value="removido" style="margin-left:0.3rem;font-size:0.65rem" />
        </li>
      </ul>

      <h3>Checklist</h3>
      <ul>
        <li v-for="(c, idx) in r.checklist" :key="idx">
          {{ c.descricao }} <Tag v-if="c.obrigatorio" severity="danger" value="obrigatório" style="font-size:0.65rem" /> —
          <Tag :severity="c.ok ? 'success' : 'warn'" :value="c.ok ? 'ok' : 'pendente'" />
        </li>
      </ul>

      <h3>Fotos ({{ r.fotos.length }})</h3>
      <ul>
        <li v-for="f in r.fotos" :key="f.id">{{ f.tipo }} — {{ f.arquivo_path }} — {{ formatarData(f.enviado_em) }}</li>
      </ul>

      <h3>Peças Utilizadas</h3>
      <table class="tabela-relatorio">
        <tbody>
          <tr v-for="(p, idx) in r.pecas_utilizadas" :key="idx">
            <td>{{ p.peca_id }}</td><td>{{ p.quantidade }}</td><td>{{ formatarMoeda(p.custo_unitario) }}</td><td>{{ p.tipo }}</td>
          </tr>
        </tbody>
      </table>

      <template v-if="r.garantia_aberta_desta_os && r.garantia_aberta_desta_os.length">
        <h3>Garantia</h3>
        <p v-for="(g, idx) in r.garantia_aberta_desta_os" :key="idx">
          <router-link :to="'/os/' + g.os_garantia_id + '/relatorio-garantia'" class="no-print-link">OS de garantia ({{ g.status }})</router-link>
        </p>
      </template>
    </div>
  </div>
</template>

<style scoped>
.pagina-relatorio { max-width: 900px; }
.acoes-topo { display: flex; justify-content: space-between; margin-bottom: 1rem; }
.tabela-relatorio { width: 100%; border-collapse: collapse; margin: 0.5rem 0 1rem; }
.tabela-relatorio th, .tabela-relatorio td { text-align: left; padding: 0.35rem 0.5rem; border-bottom: 1px solid #e5e7eb; font-size: 0.85rem; }
.hint { color: #6b7280; font-size: 0.85rem; }
@media print { .no-print { display: none !important; } }
</style>
