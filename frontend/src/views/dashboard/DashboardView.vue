<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import DatePicker from 'primevue/datepicker'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import Chart from 'primevue/chart'

const router = useRouter()
const auth = useAuthStore()
const toast = useToast()

const podeVerServicos = computed(() => ['encarregado', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))
const podeVerFinanceiro = computed(() => ['suporte_administrativo', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))
const podeVerEstoque = computed(() => ['suporte_administrativo', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))

const carregando = ref(true)

const statusOrdem = ['aberta', 'em_diagnostico', 'aguardando_aprovacao', 'em_execucao', 'aguardando_teste', 'concluida', 'liberada', 'reaberta_garantia', 'cancelada']
const severidadeStatus = {
  aberta: 'info', em_diagnostico: 'warn', aguardando_aprovacao: 'warn', em_execucao: 'warn',
  aguardando_teste: 'warn', concluida: 'success', liberada: 'success', reaberta_garantia: 'danger', cancelada: 'danger',
}

function inicioDoMes() {
  const d = new Date()
  return new Date(d.getFullYear(), d.getMonth(), 1)
}
function fimDoMes() {
  const d = new Date()
  return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59)
}
const periodoInicio = ref(inicioDoMes())
const periodoFim = ref(fimDoMes())
function resetarMesAtual() {
  periodoInicio.value = inicioDoMes()
  periodoFim.value = fimDoMes()
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function dentroDoPeriodo(dataStr) {
  if (!dataStr) return false
  const d = new Date(dataStr)
  return d >= periodoInicio.value && d <= periodoFim.value
}

// ---------- Serviços ----------
const ordensServico = ref([])

const osAbertas = computed(() => ordensServico.value.filter((o) => !['liberada', 'cancelada'].includes(o.status)).length)
const osLiberadasNoPeriodo = computed(() => ordensServico.value.filter((o) => o.status === 'liberada' && dentroDoPeriodo(o.data_liberacao)))
const tempoMedioLiberacaoDias = computed(() => {
  const lista = osLiberadasNoPeriodo.value
  if (lista.length === 0) return null
  const totalDias = lista.reduce((s, o) => s + (new Date(o.data_liberacao) - new Date(o.data_abertura)) / 86400000, 0)
  return (totalDias / lista.length).toFixed(1)
})
const osPorStatusChart = computed(() => ({
  labels: statusOrdem,
  datasets: [{ label: 'OS', backgroundColor: '#6366f1', data: statusOrdem.map((s) => ordensServico.value.filter((o) => o.status === s).length) }],
}))
const osAntigasAbertas = computed(() => {
  const hoje = Date.now()
  return ordensServico.value
    .filter((o) => !['liberada', 'cancelada'].includes(o.status) && (hoje - new Date(o.data_abertura)) / 86400000 > 7)
    .map((o) => ({ ...o, diasAberta: Math.floor((hoje - new Date(o.data_abertura)) / 86400000) }))
    .sort((a, b) => new Date(a.data_abertura) - new Date(b.data_abertura))
})

// ---------- Financeiro ----------
const parcelas = ref([])
const recebimentos = ref([])
const margemPeriodo = ref(0)

function saldoParcela(p) {
  const recebido = p.recebimentos.reduce((s, r) => s + r.valor_recebido, 0)
  return Math.max(0, p.valor - recebido)
}
const totalAReceber = computed(() => parcelas.value.filter((p) => p.status === 'pendente').reduce((s, p) => s + saldoParcela(p), 0))
const totalVencido = computed(() => {
  const hoje = new Date().toISOString().slice(0, 10)
  return parcelas.value.filter((p) => p.status === 'pendente' && p.vencimento < hoje).reduce((s, p) => s + saldoParcela(p), 0)
})
const recebidoNoPeriodo = computed(() => recebimentos.value.filter((r) => dentroDoPeriodo(r.data_recebimento)).reduce((s, r) => s + r.valor_recebido, 0))

const recebidoPorMesChart = computed(() => {
  const meses = []
  const hoje = new Date()
  for (let i = 5; i >= 0; i--) {
    meses.push(new Date(hoje.getFullYear(), hoje.getMonth() - i, 1))
  }
  const labels = meses.map((m) => m.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }))
  const data = meses.map((m) => {
    const inicio = m
    const fim = new Date(m.getFullYear(), m.getMonth() + 1, 0, 23, 59, 59)
    return recebimentos.value
      .filter((r) => { const d = new Date(r.data_recebimento); return d >= inicio && d <= fim })
      .reduce((s, r) => s + r.valor_recebido, 0)
  })
  return { labels, datasets: [{ label: 'Recebido', borderColor: '#16a34a', backgroundColor: '#16a34a33', fill: true, tension: 0.3, data }] }
})

const chartOptionsBase = { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }

// ---------- Estoque ----------
const pecas = ref([])
const pecasRuptura = computed(() => pecas.value.filter((p) => p.saldo_atual === 0))
const pecasAbaixoMinimo = computed(() => pecas.value.filter((p) => p.saldo_atual > 0 && p.saldo_atual < p.estoque_minimo))
const valorTotalEstoque = computed(() => pecas.value.reduce((s, p) => s + p.saldo_atual * p.custo_medio, 0))

async function calcularMargemPeriodo() {
  const osElegiveis = ordensServico.value.filter(
    (o) => o.tipo === 'externa' && !o.os_origem_id && o.status === 'liberada' && dentroDoPeriodo(o.data_liberacao)
  )
  if (osElegiveis.length === 0) {
    margemPeriodo.value = 0
    return
  }
  const osIds = osElegiveis.map((o) => o.id)
  const [respOrigens, respMovimentos] = await Promise.all([
    supabase.from('cobranca_origens').select('os_id, cobranca:cobrancas(valor_total, status)').in('os_id', osIds),
    supabase.from('estoque_movimentos').select('origem_id, quantidade, custo_unitario').eq('origem_tipo', 'os').in('origem_id', osIds),
  ])
  const receitaPorOs = {}
  for (const o of respOrigens.data ?? []) {
    if (o.cobranca && o.cobranca.status !== 'cancelada') receitaPorOs[o.os_id] = (receitaPorOs[o.os_id] ?? 0) + o.cobranca.valor_total
  }
  const custoPorOs = {}
  for (const m of respMovimentos.data ?? []) {
    custoPorOs[m.origem_id] = (custoPorOs[m.origem_id] ?? 0) + m.quantidade * m.custo_unitario
  }
  margemPeriodo.value = osIds.reduce((s, id) => s + (receitaPorOs[id] ?? 0) - (custoPorOs[id] ?? 0), 0)
}

async function carregar() {
  carregando.value = true
  const consultas = []
  if (podeVerServicos.value) {
    consultas.push(
      supabase.from('ordens_servico').select('id, tipo, status, data_abertura, data_liberacao, os_origem_id, veiculo:veiculos(placa, prefixo), cliente:clientes(nome)')
    )
  }
  if (podeVerFinanceiro.value) {
    consultas.push(supabase.from('parcelas').select('id, valor, vencimento, status, cobranca_id, recebimentos(valor_recebido)'))
    consultas.push(supabase.from('recebimentos').select('valor_recebido, data_recebimento'))
  }
  if (podeVerEstoque.value) {
    consultas.push(supabase.from('pecas').select('id, sku, descricao, saldo_atual, estoque_minimo, custo_medio').is('deleted_at', null))
  }

  const respostas = await Promise.all(consultas)
  for (const r of respostas) {
    if (r.error) toast.add({ severity: 'error', summary: 'Erro ao carregar dashboard', detail: r.error.message, life: 6000 })
  }

  let i = 0
  if (podeVerServicos.value) ordensServico.value = respostas[i++].data ?? []
  if (podeVerFinanceiro.value) {
    parcelas.value = respostas[i++].data ?? []
    recebimentos.value = respostas[i++].data ?? []
  }
  if (podeVerEstoque.value) pecas.value = respostas[i++].data ?? []

  if (podeVerServicos.value && podeVerFinanceiro.value) await calcularMargemPeriodo()

  carregando.value = false
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Dashboard Executivo</h2>
      <div class="filtro-periodo">
        <DatePicker v-model="periodoInicio" dateFormat="dd/mm/yy" showIcon @update:modelValue="calcularMargemPeriodo" />
        <span>até</span>
        <DatePicker v-model="periodoFim" dateFormat="dd/mm/yy" showIcon @update:modelValue="calcularMargemPeriodo" />
        <Button label="Mês atual" size="small" text @click="resetarMesAtual(); calcularMargemPeriodo()" />
      </div>
    </div>

    <div v-if="carregando">Carregando...</div>

    <template v-else>
      <section v-if="podeVerServicos" class="secao-dashboard">
        <h3>Serviços</h3>
        <div class="tiles">
          <div class="tile">
            <span class="tile-valor">{{ osAbertas }}</span>
            <span class="tile-label">OS em aberto</span>
          </div>
          <div class="tile">
            <span class="tile-valor">{{ osLiberadasNoPeriodo.length }}</span>
            <span class="tile-label">Liberadas no período</span>
          </div>
          <div class="tile">
            <span class="tile-valor">{{ tempoMedioLiberacaoDias ?? '—' }}</span>
            <span class="tile-label">Dias médios até liberação (no período)</span>
          </div>
        </div>
        <div class="grafico">
          <h4>OS por status (atual)</h4>
          <Chart type="bar" :data="osPorStatusChart" :options="chartOptionsBase" style="max-height: 280px" />
        </div>
        <h4>OS abertas há mais de 7 dias</h4>
        <DataTable :value="osAntigasAbertas" dataKey="id" size="small" paginator :rows="8">
          <Column header="Veículo"><template #body="{ data }">{{ data.veiculo?.placa }}</template></Column>
          <Column header="Cliente"><template #body="{ data }">{{ data.cliente?.nome }}</template></Column>
          <Column header="Status"><template #body="{ data }"><Tag :severity="severidadeStatus[data.status]" :value="data.status" /></template></Column>
          <Column field="diasAberta" header="Dias em aberto" />
          <Column header="">
            <template #body="{ data }"><Button label="Abrir" size="small" text @click="router.push('/os/' + data.id)" /></template>
          </Column>
        </DataTable>
      </section>

      <section v-if="podeVerFinanceiro" class="secao-dashboard">
        <h3>Financeiro</h3>
        <div class="tiles">
          <div class="tile">
            <span class="tile-valor">{{ formatarMoeda(totalAReceber) }}</span>
            <span class="tile-label">A receber</span>
          </div>
          <div class="tile tile-alerta">
            <span class="tile-valor">{{ formatarMoeda(totalVencido) }}</span>
            <span class="tile-label">Vencido</span>
          </div>
          <div class="tile">
            <span class="tile-valor">{{ formatarMoeda(recebidoNoPeriodo) }}</span>
            <span class="tile-label">Recebido no período</span>
          </div>
          <div class="tile" v-if="podeVerServicos">
            <span class="tile-valor">{{ formatarMoeda(margemPeriodo) }}</span>
            <span class="tile-label">Margem no período (OS externas)</span>
          </div>
        </div>
        <div class="grafico">
          <h4>Recebido por mês (últimos 6 meses)</h4>
          <Chart type="line" :data="recebidoPorMesChart" :options="chartOptionsBase" style="max-height: 280px" />
        </div>
      </section>

      <section v-if="podeVerEstoque" class="secao-dashboard">
        <h3>Estoque</h3>
        <div class="tiles">
          <div class="tile tile-alerta">
            <span class="tile-valor">{{ pecasRuptura.length }}</span>
            <span class="tile-label">Peças em ruptura</span>
          </div>
          <div class="tile">
            <span class="tile-valor">{{ pecasAbaixoMinimo.length }}</span>
            <span class="tile-label">Abaixo do mínimo</span>
          </div>
          <div class="tile">
            <span class="tile-valor">{{ formatarMoeda(valorTotalEstoque) }}</span>
            <span class="tile-label">Valor total em estoque</span>
          </div>
        </div>
        <DataTable v-if="pecasRuptura.length + pecasAbaixoMinimo.length > 0" :value="[...pecasRuptura, ...pecasAbaixoMinimo]" dataKey="id" size="small">
          <Column field="sku" header="SKU" />
          <Column field="descricao" header="Descrição" />
          <Column field="saldo_atual" header="Saldo" />
          <Column field="estoque_minimo" header="Mínimo" />
        </DataTable>
      </section>
    </template>
  </div>
</template>

<style scoped>
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
  flex-wrap: wrap;
  gap: 1rem;
}
.filtro-periodo {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.secao-dashboard {
  margin-bottom: 2rem;
  padding-bottom: 1.5rem;
  border-bottom: 1px solid #e5e7eb;
}
.tiles {
  display: flex;
  gap: 1rem;
  flex-wrap: wrap;
  margin: 0.75rem 0 1.25rem;
}
.tile {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 1rem 1.25rem;
  min-width: 180px;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}
.tile-alerta {
  border-color: #fca5a5;
  background: #fef2f2;
}
.tile-valor {
  font-size: 1.5rem;
  font-weight: 700;
}
.tile-label {
  font-size: 0.8rem;
  color: #6b7280;
}
.grafico {
  margin-bottom: 1.5rem;
  max-width: 720px;
}
</style>
