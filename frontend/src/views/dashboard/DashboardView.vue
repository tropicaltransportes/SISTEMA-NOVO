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
import Skeleton from 'primevue/skeleton'
import Message from 'primevue/message'
import { STATUS_OS, ORDEM_STATUS_OS } from '../../constants/statusVisual'

const router = useRouter()
const auth = useAuthStore()
const toast = useToast()

const podeVerServicos = computed(() => ['encarregado', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))
const podeVerFinanceiro = computed(() => ['suporte_administrativo', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))
const podeVerEstoque = computed(() => ['suporte_administrativo', 'diretoria', 'administrador_tecnico'].includes(auth.perfil))
// mesmo conjunto de perfis aceito por rpc_status_configuracao_sistema (ver
// supabase/migrations/20260816130000_rc2_status_configuracao_sistema.sql) —
// não inclui 'diretoria'.
const podeVerConfig = computed(() => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil))

const carregando = ref(true)
const erroCarregamento = ref(false)
const ultimaAtualizacao = ref(null)

const primeiroNome = computed(() => auth.profile?.nome?.split(' ')[0] ?? '')
const horaAtualizacao = computed(() =>
  ultimaAtualizacao.value
    ? ultimaAtualizacao.value.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
    : ''
)

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

const totalOS = computed(() => ordensServico.value.length)
const osAbertas = computed(() => ordensServico.value.filter((o) => !['liberada', 'cancelada'].includes(o.status)).length)
const osLiberadasNoPeriodo = computed(() => ordensServico.value.filter((o) => o.status === 'liberada' && dentroDoPeriodo(o.data_liberacao)))
const tempoMedioLiberacaoDias = computed(() => {
  const lista = osLiberadasNoPeriodo.value
  if (lista.length === 0) return null
  const totalDias = lista.reduce((s, o) => s + (new Date(o.data_liberacao) - new Date(o.data_abertura)) / 86400000, 0)
  return (totalDias / lista.length).toFixed(1)
})
const contagemPorStatus = computed(() => {
  const mapa = {}
  for (const s of ORDEM_STATUS_OS) mapa[s] = ordensServico.value.filter((o) => o.status === s).length
  return mapa
})
const osPorStatusChart = computed(() => ({
  labels: ORDEM_STATUS_OS.map((s) => STATUS_OS[s].label),
  datasets: [
    {
      label: 'OS',
      backgroundColor: ORDEM_STATUS_OS.map((s) => STATUS_OS[s].cor),
      borderRadius: 6,
      data: ORDEM_STATUS_OS.map((s) => contagemPorStatus.value[s]),
    },
  ],
}))
const osPorStatusDonut = computed(() => ({
  labels: ORDEM_STATUS_OS.map((s) => STATUS_OS[s].label),
  datasets: [
    {
      data: ORDEM_STATUS_OS.map((s) => contagemPorStatus.value[s]),
      backgroundColor: ORDEM_STATUS_OS.map((s) => STATUS_OS[s].cor),
      borderWidth: 0,
      hoverOffset: 4,
    },
  ],
}))
const donutOptions = {
  cutout: '70%',
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(30,34,43,0.95)',
      titleColor: '#f5f3ff',
      bodyColor: '#cfc9dd',
      borderColor: 'rgba(255,255,255,0.09)',
      borderWidth: 1,
    },
  },
}
const legendaStatus = computed(() =>
  ORDEM_STATUS_OS.map((s) => ({
    status: s,
    label: STATUS_OS[s].label,
    cor: STATUS_OS[s].cor,
    quantidade: contagemPorStatus.value[s],
    percentual: totalOS.value > 0 ? Math.round((contagemPorStatus.value[s] / totalOS.value) * 100) : 0,
  })).filter((item) => item.quantidade > 0)
)

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
const receitaExternaPeriodo = ref(0)
const qtdOsExternasPeriodo = ref(0)

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
const ticketMedioExterno = computed(() => (qtdOsExternasPeriodo.value > 0 ? receitaExternaPeriodo.value / qtdOsExternasPeriodo.value : null))

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
  return { labels, datasets: [{ label: 'Recebido', borderColor: '#8b5cf6', backgroundColor: 'rgba(139,92,246,0.15)', fill: true, tension: 0.3, data }] }
})

const chartOptionsBase = {
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(30,34,43,0.95)',
      titleColor: '#f5f3ff',
      bodyColor: '#cfc9dd',
      borderColor: 'rgba(255,255,255,0.09)',
      borderWidth: 1,
    },
  },
  scales: {
    x: {
      ticks: { color: '#776f8c' },
      grid: { color: 'rgba(255,255,255,0.04)', drawTicks: false },
    },
    y: {
      beginAtZero: true,
      ticks: { color: '#776f8c' },
      grid: { color: 'rgba(255,255,255,0.06)' },
    },
  },
}

// ---------- Estoque ----------
const pecas = ref([])
const pecasRuptura = computed(() => pecas.value.filter((p) => p.saldo_atual === 0))
const pecasAbaixoMinimo = computed(() => pecas.value.filter((p) => p.saldo_atual > 0 && p.saldo_atual < p.estoque_minimo))
const valorTotalEstoque = computed(() => pecas.value.reduce((s, p) => s + p.saldo_atual * p.custo_medio, 0))

// ---------- Configuração inicial (alerta) ----------
const itensConfig = ref([])
const pendentesConfig = computed(() => itensConfig.value.filter((i) => !i.configurado).length)

// ---------- KPIs (Bloco A) — só reaproveita valores já calculados acima ----------
const kpis = computed(() => {
  const lista = []
  if (podeVerServicos.value) {
    lista.push({ icone: 'pi pi-briefcase', titulo: 'OS em aberto', valor: String(osAbertas.value), tom: 'neutro' })
    lista.push({ icone: 'pi pi-check-circle', titulo: 'Liberadas no período', valor: String(osLiberadasNoPeriodo.value.length), tom: 'sucesso' })
    lista.push({
      icone: 'pi pi-clock',
      titulo: 'Tempo médio até liberação',
      valor: tempoMedioLiberacaoDias.value ?? '—',
      unidade: tempoMedioLiberacaoDias.value ? 'dias' : '',
      tom: 'neutro',
    })
  }
  if (podeVerFinanceiro.value) {
    lista.push({ icone: 'pi pi-wallet', titulo: 'A receber', valor: formatarMoeda(totalAReceber.value), tom: 'neutro' })
    lista.push({ icone: 'pi pi-arrow-down-left', titulo: 'Recebido no período', valor: formatarMoeda(recebidoNoPeriodo.value), tom: 'sucesso' })
  }
  if (podeVerEstoque.value) {
    lista.push({ icone: 'pi pi-box', titulo: 'Valor total em estoque', valor: formatarMoeda(valorTotalEstoque.value), tom: 'neutro' })
  }
  return lista
})

// ---------- Alertas e pendências (Bloco D) ----------
const alertas = computed(() => {
  const lista = []
  if (podeVerFinanceiro.value && totalVencido.value > 0) {
    lista.push({
      icone: 'pi pi-exclamation-circle',
      tom: 'critico',
      titulo: 'Cobranças vencidas',
      detalhe: `${formatarMoeda(totalVencido.value)} em parcelas pendentes vencidas`,
      acaoLabel: 'Ver financeiro',
      acaoRota: '/financeiro/cobrancas',
    })
  }
  if (podeVerEstoque.value && pecasRuptura.value.length > 0) {
    lista.push({
      icone: 'pi pi-times-circle',
      tom: 'critico',
      titulo: 'Peças em ruptura',
      detalhe: `${pecasRuptura.value.length} peça(s) com saldo zerado`,
      acaoLabel: 'Ver peças',
      acaoRota: '/estoque/pecas',
    })
  }
  if (podeVerEstoque.value && pecasAbaixoMinimo.value.length > 0) {
    lista.push({
      icone: 'pi pi-exclamation-triangle',
      tom: 'atencao',
      titulo: 'Peças abaixo do mínimo',
      detalhe: `${pecasAbaixoMinimo.value.length} peça(s) abaixo do estoque mínimo`,
      acaoLabel: 'Ver peças',
      acaoRota: '/estoque/pecas',
    })
  }
  if (podeVerConfig.value && pendentesConfig.value > 0) {
    lista.push({
      icone: 'pi pi-cog',
      tom: 'info',
      titulo: 'Configuração inicial pendente',
      detalhe: `${pendentesConfig.value} requisito(s) de configuração ainda pendente(s)`,
      acaoLabel: 'Ver configuração',
      acaoRota: '/admin/status-configuracao',
    })
  }
  return lista
})
const secaoAlertasVisivel = computed(() => podeVerFinanceiro.value || podeVerEstoque.value || podeVerConfig.value)

async function calcularMargemPeriodo() {
  const osElegiveis = ordensServico.value.filter(
    (o) => o.tipo === 'externa' && !o.os_origem_id && o.status === 'liberada' && dentroDoPeriodo(o.data_liberacao)
  )
  if (osElegiveis.length === 0) {
    margemPeriodo.value = 0
    receitaExternaPeriodo.value = 0
    qtdOsExternasPeriodo.value = 0
    return
  }
  const osIds = osElegiveis.map((o) => o.id)
  const [respOrigens, respMovimentos] = await Promise.all([
    supabase.from('cobranca_origens').select('os_id, cobranca:cobrancas(valor_total, status)').in('os_id', osIds),
    supabase.from('estoque_movimentos').select('origem_id, quantidade, custo_unitario').eq('origem_tipo', 'os').in('origem_id', osIds),
  ])
  if (respOrigens.error || respMovimentos.error) {
    erroCarregamento.value = true
    toast.add({
      severity: 'error',
      summary: 'Erro ao calcular margem do período',
      detail: respOrigens.error?.message || respMovimentos.error?.message,
      life: 6000,
    })
  }
  const receitaPorOs = {}
  for (const o of respOrigens.data ?? []) {
    if (o.cobranca && o.cobranca.status !== 'cancelada') receitaPorOs[o.os_id] = (receitaPorOs[o.os_id] ?? 0) + o.cobranca.valor_total
  }
  const custoPorOs = {}
  for (const m of respMovimentos.data ?? []) {
    custoPorOs[m.origem_id] = (custoPorOs[m.origem_id] ?? 0) + m.quantidade * m.custo_unitario
  }
  margemPeriodo.value = osIds.reduce((s, id) => s + (receitaPorOs[id] ?? 0) - (custoPorOs[id] ?? 0), 0)
  receitaExternaPeriodo.value = osIds.reduce((s, id) => s + (receitaPorOs[id] ?? 0), 0)
  qtdOsExternasPeriodo.value = osIds.length
}

async function carregar() {
  carregando.value = true
  erroCarregamento.value = false

  const consultas = []
  if (podeVerServicos.value) {
    consultas.push([
      'os',
      supabase.from('ordens_servico').select('id, tipo, status, data_abertura, data_liberacao, os_origem_id, veiculo:veiculos(placa, prefixo), cliente:clientes(nome)'),
    ])
  }
  if (podeVerFinanceiro.value) {
    consultas.push(['parcelas', supabase.from('parcelas').select('id, valor, vencimento, status, cobranca_id, recebimentos(valor_recebido)')])
    consultas.push(['recebimentos', supabase.from('recebimentos').select('valor_recebido, data_recebimento')])
  }
  if (podeVerEstoque.value) {
    consultas.push(['pecas', supabase.from('pecas').select('id, sku, descricao, saldo_atual, estoque_minimo, custo_medio').is('deleted_at', null)])
  }
  if (podeVerConfig.value) {
    consultas.push(['config', supabase.rpc('rpc_status_configuracao_sistema')])
  }

  const respostas = await Promise.all(consultas.map(([, promessa]) => promessa))
  const porChave = {}
  consultas.forEach(([chave], idx) => { porChave[chave] = respostas[idx] })

  for (const resp of Object.values(porChave)) {
    if (resp.error) {
      erroCarregamento.value = true
      toast.add({ severity: 'error', summary: 'Erro ao carregar dashboard', detail: resp.error.message, life: 6000 })
    }
  }

  if (podeVerServicos.value) ordensServico.value = porChave.os?.data ?? []
  if (podeVerFinanceiro.value) {
    parcelas.value = porChave.parcelas?.data ?? []
    recebimentos.value = porChave.recebimentos?.data ?? []
  }
  if (podeVerEstoque.value) pecas.value = porChave.pecas?.data ?? []
  if (podeVerConfig.value) itensConfig.value = porChave.config?.data ?? []

  if (podeVerServicos.value && podeVerFinanceiro.value) await calcularMargemPeriodo()

  ultimaAtualizacao.value = new Date()
  carregando.value = false
}

onMounted(carregar)
</script>

<template>
  <div class="dash">
    <div class="cabecalho">
      <div class="cabecalho-texto">
        <p class="saudacao">Olá, {{ primeiroNome }}</p>
        <h1 class="titulo-dash">Dashboard Executivo</h1>
        <p class="subtitulo-dash">Visão geral da oficina e indicadores de desempenho</p>
      </div>

      <div class="cabecalho-acoes">
        <div class="filtro-periodo">
          <div class="filtro-campo">
            <label>Início</label>
            <DatePicker v-model="periodoInicio" dateFormat="dd/mm/yy" showIcon @update:modelValue="calcularMargemPeriodo" />
          </div>
          <div class="filtro-campo">
            <label>Fim</label>
            <DatePicker v-model="periodoFim" dateFormat="dd/mm/yy" showIcon @update:modelValue="calcularMargemPeriodo" />
          </div>
          <Button label="Mês atual" size="small" text @click="resetarMesAtual(); calcularMargemPeriodo()" />
        </div>
        <div class="atualizacao">
          <span v-if="horaAtualizacao">Atualizado às {{ horaAtualizacao }}</span>
          <Button icon="pi pi-refresh" text rounded size="small" :loading="carregando" @click="carregar" aria-label="Atualizar" />
        </div>
      </div>
    </div>

    <Message v-if="erroCarregamento && !carregando" severity="error" :closable="false" class="banner-erro">
      Não foi possível carregar completamente os dados do dashboard. Alguns números abaixo podem estar incompletos —
      veja os detalhes nas notificações ou tente atualizar novamente.
    </Message>

    <template v-if="carregando">
      <div class="kpi-grid">
        <Skeleton v-for="n in 4" :key="n" height="96px" borderRadius="var(--card-radius)" />
      </div>
      <div class="skeleton-blocos">
        <Skeleton height="320px" borderRadius="var(--card-radius)" />
        <Skeleton height="320px" borderRadius="var(--card-radius)" />
      </div>
    </template>

    <template v-else>
      <!-- BLOCO A — KPIs -->
      <div class="kpi-grid" v-if="kpis.length">
        <div v-for="kpi in kpis" :key="kpi.titulo" class="kpi-card" :class="'kpi-' + kpi.tom">
          <div class="kpi-icone"><i :class="kpi.icone"></i></div>
          <div class="kpi-corpo">
            <span class="kpi-titulo">{{ kpi.titulo }}</span>
            <span class="kpi-valor">{{ kpi.valor }} <small v-if="kpi.unidade">{{ kpi.unidade }}</small></span>
          </div>
        </div>
      </div>

      <!-- BLOCO B — Ordens de Serviço -->
      <section v-if="podeVerServicos" class="bloco">
        <h2 class="bloco-titulo">Ordens de Serviço</h2>

        <div v-if="totalOS === 0" class="estado-vazio">
          <i class="pi pi-inbox"></i>
          <p>Nenhuma Ordem de Serviço encontrada.</p>
        </div>

        <div v-else class="grid-graficos">
          <div class="card card-grafico">
            <h3>OS por status</h3>
            <Chart type="bar" :data="osPorStatusChart" :options="chartOptionsBase" style="max-height: 260px" />
          </div>
          <div class="card card-grafico card-donut">
            <h3>OS por situação</h3>
            <div class="donut-area">
              <div class="donut-chart">
                <Chart type="doughnut" :data="osPorStatusDonut" :options="donutOptions" style="max-height: 200px" />
                <div class="donut-total">
                  <span class="donut-total-valor">{{ totalOS }}</span>
                  <span class="donut-total-label">TOTAL</span>
                </div>
              </div>
              <ul class="donut-legenda">
                <li v-for="item in legendaStatus" :key="item.status">
                  <span class="legenda-cor" :style="{ background: item.cor }"></span>
                  <span class="legenda-label">{{ item.label }}</span>
                  <span class="legenda-valor">{{ item.quantidade }} · {{ item.percentual }}%</span>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div class="card" v-if="osAntigasAbertas.length">
          <h3>OS abertas há mais de 7 dias</h3>
          <DataTable :value="osAntigasAbertas" dataKey="id" size="small" paginator :rows="8">
            <Column header="Veículo"><template #body="{ data }">{{ data.veiculo?.placa }}</template></Column>
            <Column header="Cliente"><template #body="{ data }">{{ data.cliente?.nome }}</template></Column>
            <Column header="Status"><template #body="{ data }"><Tag :severity="STATUS_OS[data.status]?.severidade" :value="STATUS_OS[data.status]?.label" /></template></Column>
            <Column field="diasAberta" header="Dias em aberto" />
            <Column header="">
              <template #body="{ data }"><Button label="Abrir" size="small" text @click="router.push('/os/' + data.id)" /></template>
            </Column>
          </DataTable>
        </div>
      </section>

      <!-- BLOCO C — Financeiro e Estoque -->
      <section v-if="podeVerFinanceiro" class="bloco">
        <h2 class="bloco-titulo">Financeiro</h2>
        <div class="mini-kpi-grid">
          <div class="mini-kpi mini-kpi-atencao">
            <span class="mini-kpi-valor">{{ formatarMoeda(totalVencido) }}</span>
            <span class="mini-kpi-label">Vencido</span>
          </div>
          <div class="mini-kpi" v-if="podeVerServicos">
            <span class="mini-kpi-valor">{{ formatarMoeda(margemPeriodo) }}</span>
            <span class="mini-kpi-label">Margem no período (OS externas)</span>
          </div>
          <div class="mini-kpi" v-if="podeVerServicos && ticketMedioExterno !== null">
            <span class="mini-kpi-valor">{{ formatarMoeda(ticketMedioExterno) }}</span>
            <span class="mini-kpi-label">Ticket médio (OS externas, no período)</span>
          </div>
        </div>
        <div class="card card-grafico">
          <h3>Recebido por mês (últimos 6 meses)</h3>
          <Chart type="line" :data="recebidoPorMesChart" :options="chartOptionsBase" style="max-height: 260px" />
        </div>
      </section>

      <section v-if="podeVerEstoque" class="bloco">
        <h2 class="bloco-titulo">Estoque</h2>
        <div class="mini-kpi-grid">
          <div class="mini-kpi">
            <span class="mini-kpi-valor">{{ pecasAbaixoMinimo.length }}</span>
            <span class="mini-kpi-label">Peças abaixo do mínimo</span>
          </div>
          <div class="mini-kpi">
            <span class="mini-kpi-valor">{{ pecasRuptura.length }}</span>
            <span class="mini-kpi-label">Peças em ruptura</span>
          </div>
        </div>
        <div class="card" v-if="pecasRuptura.length + pecasAbaixoMinimo.length > 0">
          <h3>Peças que precisam de atenção</h3>
          <DataTable :value="[...pecasRuptura, ...pecasAbaixoMinimo]" dataKey="id" size="small">
            <Column field="sku" header="SKU" />
            <Column field="descricao" header="Descrição" />
            <Column field="saldo_atual" header="Saldo" />
            <Column field="estoque_minimo" header="Mínimo" />
          </DataTable>
        </div>
      </section>

      <!-- BLOCO D — Alertas e pendências -->
      <section v-if="secaoAlertasVisivel" class="bloco">
        <h2 class="bloco-titulo">Alertas e pendências</h2>
        <div v-if="alertas.length === 0" class="alerta-ok">
          <i class="pi pi-check-circle"></i>
          <span>Tudo em dia — nenhuma pendência identificada no momento.</span>
        </div>
        <div v-else class="alertas-grid">
          <button
            v-for="alerta in alertas"
            :key="alerta.titulo"
            type="button"
            class="alerta-card"
            :class="'alerta-' + alerta.tom"
            @click="router.push(alerta.acaoRota)"
          >
            <i :class="alerta.icone"></i>
            <div class="alerta-corpo">
              <span class="alerta-titulo">{{ alerta.titulo }}</span>
              <span class="alerta-detalhe">{{ alerta.detalhe }}</span>
            </div>
            <span class="alerta-acao">{{ alerta.acaoLabel }} <i class="pi pi-arrow-right"></i></span>
          </button>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.dash {
  display: flex;
  flex-direction: column;
  gap: 26px;
  padding-top: 4px;
}

/* ---------- cabeçalho ---------- */
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  flex-wrap: wrap;
  gap: 16px;
}
.saudacao {
  margin: 0 0 2px;
  font-size: 13px;
  font-weight: 600;
  color: var(--accent-text);
}
.titulo-dash {
  margin: 0 0 4px;
  font-size: 24px;
  font-weight: 800;
  letter-spacing: -0.4px;
  color: var(--text-heading);
}
.subtitulo-dash {
  margin: 0;
  font-size: 13.5px;
  color: var(--text-secondary);
}
.cabecalho-acoes {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 8px;
}
.filtro-periodo {
  display: flex;
  align-items: flex-end;
  gap: 10px;
  flex-wrap: wrap;
}
.filtro-campo {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.filtro-campo label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--text-muted);
}
.filtro-periodo :deep(.p-datepicker-input) {
  width: 118px;
  background: var(--surface);
  border-color: var(--border-panel);
  color: var(--text-body);
}
.filtro-periodo :deep(.p-datepicker-input:enabled:focus) {
  border-color: var(--primary);
  box-shadow: 0 0 0 1px var(--primary);
}
.filtro-periodo :deep(.p-datepicker-dropdown) {
  background: var(--surface);
  border-color: var(--border-panel);
  color: var(--text-muted);
}
.atualizacao {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11.5px;
  color: var(--text-faint);
}

.banner-erro {
  margin: 0;
}

/* ---------- BLOCO A: KPIs ---------- */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 14px;
}
.kpi-card {
  display: flex;
  align-items: center;
  gap: 14px;
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 18px 20px;
}
.kpi-icone {
  width: 40px;
  height: 40px;
  border-radius: 11px;
  background: var(--accent-soft-bg);
  color: var(--accent-text);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  font-size: 16px;
}
.kpi-sucesso .kpi-icone {
  background: var(--success-bg);
  color: var(--success);
}
.kpi-corpo {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.kpi-titulo {
  font-size: 12px;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.kpi-valor {
  font-size: 21px;
  font-weight: 800;
  color: var(--text-heading);
  letter-spacing: -0.3px;
}
.kpi-valor small {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  margin-left: 2px;
}

/* ---------- blocos genéricos ---------- */
.bloco-titulo {
  margin: 0 0 14px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-heading);
}
.card {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 20px;
  margin-bottom: 14px;
}
.card h3 {
  margin: 0 0 14px;
  font-size: 13.5px;
  font-weight: 700;
  color: var(--text-heading);
}
.grid-graficos {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
  gap: 14px;
}
.card-grafico {
  margin-bottom: 14px;
}

/* donut */
.donut-area {
  display: flex;
  align-items: center;
  gap: 20px;
}
.donut-chart {
  position: relative;
  width: 180px;
  flex-shrink: 0;
}
.donut-total {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}
.donut-total-valor {
  font-size: 24px;
  font-weight: 800;
  color: var(--text-heading);
}
.donut-total-label {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.6px;
  color: var(--text-faint);
}
.donut-legenda {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
  flex: 1;
}
.donut-legenda li {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12.5px;
}
.legenda-cor {
  width: 9px;
  height: 9px;
  border-radius: 3px;
  flex-shrink: 0;
}
.legenda-label {
  color: var(--text-secondary);
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.legenda-valor {
  color: var(--text-muted);
  font-weight: 600;
  flex-shrink: 0;
}

/* mini KPIs (financeiro / estoque) */
.mini-kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 14px;
  margin-bottom: 14px;
}
.mini-kpi {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 16px 18px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mini-kpi-atencao {
  background: var(--danger-bg);
  border-color: transparent;
}
.mini-kpi-valor {
  font-size: 18px;
  font-weight: 700;
  color: var(--text-heading);
}
.mini-kpi-label {
  font-size: 11.5px;
  color: var(--text-muted);
}

/* estado vazio */
.estado-vazio {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 48px 20px;
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  color: var(--text-faint);
}
.estado-vazio i {
  font-size: 26px;
  color: var(--text-faint);
}
.estado-vazio p {
  margin: 0;
  font-size: 13.5px;
}

/* ---------- BLOCO D: alertas ---------- */
.alerta-ok {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 20px;
  background: var(--success-bg);
  border-radius: var(--card-radius);
  color: var(--success);
  font-size: 13.5px;
  font-weight: 600;
}
.alertas-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 12px;
}
.alerta-card {
  display: flex;
  align-items: center;
  gap: 12px;
  text-align: left;
  padding: 14px 16px;
  border-radius: var(--card-radius);
  border: 1px solid var(--border-panel);
  background: var(--surface);
  cursor: pointer;
  font-family: inherit;
  transition: background 0.15s ease;
}
.alerta-card:hover {
  background: var(--surface-hover);
}
.alerta-card > i {
  font-size: 18px;
  flex-shrink: 0;
}
.alerta-critico > i { color: var(--danger); }
.alerta-atencao > i { color: var(--warning); }
.alerta-info > i { color: var(--accent-text); }
.alerta-corpo {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  flex: 1;
}
.alerta-titulo {
  font-size: 13px;
  font-weight: 700;
  color: var(--text-heading);
}
.alerta-detalhe {
  font-size: 11.5px;
  color: var(--text-muted);
}
.alerta-acao {
  font-size: 11.5px;
  font-weight: 600;
  color: var(--accent-text);
  white-space: nowrap;
  flex-shrink: 0;
}

/* ---------- loading skeleton ---------- */
.skeleton-blocos {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
}

/* ---------- responsividade (item 14) ---------- */
@media (max-width: 1180px) {
  .grid-graficos {
    grid-template-columns: 1fr;
  }
  .skeleton-blocos {
    grid-template-columns: 1fr;
  }
}
@media (max-width: 720px) {
  .cabecalho {
    align-items: flex-start;
  }
  .cabecalho-acoes {
    align-items: flex-start;
    width: 100%;
  }
  .filtro-periodo {
    width: 100%;
  }
  .donut-area {
    flex-direction: column;
    align-items: stretch;
  }
  .donut-chart {
    align-self: center;
  }
}
</style>
