<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import DatePicker from 'primevue/datepicker'
import Select from 'primevue/select'
import Checkbox from 'primevue/checkbox'
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)
const podeTermo = () => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const cobrancas = ref([])
const clientes = ref([])
const carregando = ref(true)

const severidadeStatus = {
  aberta: 'info',
  parcial: 'warn',
  quitada: 'success',
  vencida: 'danger',
  cancelada: 'contrast',
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(data) {
  return data ? new Date(data + 'T00:00:00').toLocaleDateString('pt-BR') : '—'
}
function hojeISO() {
  return new Date().toISOString().slice(0, 10)
}

function valorRecebido(cobranca) {
  return cobranca.parcelas.reduce((s, p) => s + p.recebimentos.reduce((s2, r) => s2 + r.valor_recebido, 0), 0)
}
function temParcelaVencida(cobranca) {
  const hoje = hojeISO()
  return cobranca.parcelas.some((p) => p.status === 'pendente' && p.vencimento < hoje)
}
function statusExibicao(cobranca) {
  if (['aberta', 'parcial'].includes(cobranca.status) && temParcelaVencida(cobranca)) return 'vencida'
  return cobranca.status
}
function origensLabel(cobranca) {
  return cobranca.cobranca_origens
    .map((o) => (o.os ? `OS ${o.os.veiculo?.placa ?? ''}` : 'Venda Avulsa'))
    .join(', ')
}

async function carregar() {
  carregando.value = true
  const [respCobrancas, respClientes] = await Promise.all([
    supabase
      .from('cobrancas')
      .select(
        'id, valor_total, status, criado_em, cliente:clientes(id, nome, tipo), cobranca_origens(id, os:ordens_servico(id, veiculo:veiculos(placa, prefixo)), venda_avulsa_id), parcelas(id, numero_parcela, valor, vencimento, status, recebimentos(id, valor_recebido, forma_pagamento, data_recebimento)), termos_ciencia_debito(id, arquivo_path, assinado_em)'
      )
      .order('criado_em', { ascending: false }),
    supabase.from('clientes').select('id, nome, tipo').is('deleted_at', null).order('nome'),
  ])
  if (respCobrancas.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar cobranças', detail: respCobrancas.error.message, life: 5000 })
  } else {
    cobrancas.value = respCobrancas.data
  }
  clientes.value = respClientes.data ?? []
  carregando.value = false
}

// ---------- Nova cobrança ----------
const dialogoNovoAberto = ref(false)
const salvandoNovo = ref(false)
const clienteSelecionado = ref(null)
const osPendentes = ref([])
const vendasPendentes = ref([])
const osSelecionadas = ref([])
const vendasSelecionadas = ref([])
const buscandoPendencias = ref(false)

function valorOsPendente(os) {
  const base = os.orcamento?.valor_total ?? 0
  const acrescimos = (os.orcamento?.orcamento_acrescimos ?? []).reduce((s, a) => s + a.valor_acrescimo, 0)
  return base + acrescimos
}
function valorVendaPendente(venda) {
  return venda.venda_avulsa_itens.reduce((s, i) => s + i.quantidade * i.valor_unitario, 0)
}

const totalSelecionado = computed(() => {
  const totalOs = osPendentes.value.filter((o) => osSelecionadas.value.includes(o.id)).reduce((s, o) => s + valorOsPendente(o), 0)
  const totalVendas = vendasPendentes.value.filter((v) => vendasSelecionadas.value.includes(v.id)).reduce((s, v) => s + valorVendaPendente(v), 0)
  return totalOs + totalVendas
})

async function buscarPendencias(clienteId, preselecOsId, preselecVendaId) {
  if (!clienteId) {
    osPendentes.value = []
    vendasPendentes.value = []
    return
  }
  buscandoPendencias.value = true
  const [respOs, respVendas] = await Promise.all([
    supabase
      .from('ordens_servico')
      .select('id, data_abertura, veiculo:veiculos(placa, prefixo), orcamento:orcamentos(valor_total, orcamento_acrescimos(valor_acrescimo))')
      .eq('cliente_id', clienteId)
      .eq('tipo', 'externa')
      .eq('status', 'concluida'),
    supabase
      .from('vendas_avulsas')
      .select('id, criado_em, venda_avulsa_itens(quantidade, valor_unitario)')
      .eq('cliente_id', clienteId),
  ])
  const osIds = (respOs.data ?? []).map((o) => o.id)
  const vendaIds = (respVendas.data ?? []).map((v) => v.id)

  const [respOrigensOs, respOrigensVenda] = await Promise.all([
    osIds.length
      ? supabase.from('cobranca_origens').select('os_id, cobranca:cobrancas(status)').in('os_id', osIds)
      : Promise.resolve({ data: [] }),
    vendaIds.length
      ? supabase.from('cobranca_origens').select('venda_avulsa_id, cobranca:cobrancas(status)').in('venda_avulsa_id', vendaIds)
      : Promise.resolve({ data: [] }),
  ])
  const osJaCobradas = new Set((respOrigensOs.data ?? []).filter((o) => o.cobranca?.status !== 'cancelada').map((o) => o.os_id))
  const vendasJaCobradas = new Set((respOrigensVenda.data ?? []).filter((o) => o.cobranca?.status !== 'cancelada').map((o) => o.venda_avulsa_id))

  osPendentes.value = (respOs.data ?? []).filter((o) => !osJaCobradas.has(o.id))
  vendasPendentes.value = (respVendas.data ?? []).filter((v) => !vendasJaCobradas.has(v.id))
  buscandoPendencias.value = false

  osSelecionadas.value = preselecOsId && osPendentes.value.some((o) => o.id === preselecOsId) ? [preselecOsId] : []
  vendasSelecionadas.value = preselecVendaId && vendasPendentes.value.some((v) => v.id === preselecVendaId) ? [preselecVendaId] : []
}

function abrirNovo() {
  clienteSelecionado.value = route.query.cliente_id || null
  osPendentes.value = []
  vendasPendentes.value = []
  osSelecionadas.value = []
  vendasSelecionadas.value = []
  dialogoNovoAberto.value = true
  if (clienteSelecionado.value) {
    buscarPendencias(clienteSelecionado.value, route.query.os_id, route.query.venda_id)
  }
}

async function criarCobranca() {
  if (!clienteSelecionado.value) {
    toast.add({ severity: 'warn', summary: 'Selecione o cliente', life: 4000 })
    return
  }
  if (osSelecionadas.value.length === 0 && vendasSelecionadas.value.length === 0) {
    toast.add({ severity: 'warn', summary: 'Selecione ao menos uma OS ou venda avulsa', life: 4000 })
    return
  }
  salvandoNovo.value = true
  const { error } = await supabase.rpc('rpc_criar_cobranca', {
    p_cliente_id: clienteSelecionado.value,
    p_os_ids: osSelecionadas.value,
    p_venda_ids: vendasSelecionadas.value,
  })
  salvandoNovo.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao gerar cobrança', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Cobrança gerada', life: 3000 })
  dialogoNovoAberto.value = false
  if (route.query.cliente_id) router.replace({ path: '/financeiro/cobrancas' })
  await carregar()
}

// ---------- Parcelar ----------
const dialogoParcelarAberto = ref(false)
const salvandoParcelamento = ref(false)
const cobrancaAtual = ref(null)
const linhasParcelas = ref([])

function abrirParcelar(cobranca) {
  cobrancaAtual.value = cobranca
  linhasParcelas.value = [{ numero_parcela: 1, valor: cobranca.valor_total, vencimento: new Date() }]
  dialogoParcelarAberto.value = true
}
function adicionarParcela() {
  linhasParcelas.value.push({ numero_parcela: linhasParcelas.value.length + 1, valor: 0, vencimento: new Date() })
}
function removerParcela(index) {
  linhasParcelas.value.splice(index, 1)
  linhasParcelas.value.forEach((l, i) => (l.numero_parcela = i + 1))
}
function dividirIgualmente() {
  const n = linhasParcelas.value.length
  if (n === 0) return
  const total = cobrancaAtual.value.valor_total
  const base = Math.floor((total / n) * 100) / 100
  linhasParcelas.value.forEach((l, i) => {
    l.valor = i === n - 1 ? Math.round((total - base * (n - 1)) * 100) / 100 : base
  })
}
const somaParcelas = computed(() => linhasParcelas.value.reduce((s, l) => s + (l.valor || 0), 0))

async function salvarParcelamento() {
  if (Math.abs(somaParcelas.value - cobrancaAtual.value.valor_total) > 0.01) {
    toast.add({ severity: 'warn', summary: 'Soma das parcelas precisa ser igual ao valor da cobrança', life: 5000 })
    return
  }
  salvandoParcelamento.value = true
  const payload = linhasParcelas.value.map((l) => ({
    numero_parcela: l.numero_parcela,
    valor: l.valor,
    vencimento: (l.vencimento instanceof Date ? l.vencimento : new Date(l.vencimento)).toISOString().slice(0, 10),
  }))
  const { error } = await supabase.rpc('rpc_parcelar_cobranca', { p_cobranca_id: cobrancaAtual.value.id, p_parcelas: payload })
  salvandoParcelamento.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao parcelar', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Parcelamento formalizado', life: 3000 })
  dialogoParcelarAberto.value = false
  await carregar()
}

// ---------- Recebimento ----------
const dialogoRecebimentoAberto = ref(false)
const salvandoRecebimento = ref(false)
const parcelaSelecionadaId = ref(null)
const formRecebimento = ref({ valor_recebido: 0, forma_pagamento: '', data_recebimento: new Date() })

function saldoParcela(parcela) {
  const recebido = parcela.recebimentos.reduce((s, r) => s + r.valor_recebido, 0)
  return Math.round((parcela.valor - recebido) * 100) / 100
}
function parcelasPendentes(cobranca) {
  return cobranca.parcelas.filter((p) => p.status === 'pendente')
}

function abrirRecebimento(cobranca) {
  cobrancaAtual.value = cobranca
  const pendentes = parcelasPendentes(cobranca)
  parcelaSelecionadaId.value = pendentes[0]?.id || null
  formRecebimento.value = {
    valor_recebido: pendentes[0] ? saldoParcela(pendentes[0]) : 0,
    forma_pagamento: '',
    data_recebimento: new Date(),
  }
  dialogoRecebimentoAberto.value = true
}
function selecionouParcela() {
  const parcela = cobrancaAtual.value.parcelas.find((p) => p.id === parcelaSelecionadaId.value)
  if (parcela) formRecebimento.value.valor_recebido = saldoParcela(parcela)
}

async function salvarRecebimento() {
  if (!parcelaSelecionadaId.value) {
    toast.add({ severity: 'warn', summary: 'Selecione a parcela', life: 4000 })
    return
  }
  if (!formRecebimento.value.valor_recebido || !formRecebimento.value.forma_pagamento) {
    toast.add({ severity: 'warn', summary: 'Informe valor e forma de pagamento', life: 4000 })
    return
  }
  salvandoRecebimento.value = true
  const { error } = await supabase.rpc('rpc_registrar_recebimento', {
    p_parcela_id: parcelaSelecionadaId.value,
    p_valor_recebido: formRecebimento.value.valor_recebido,
    p_forma_pagamento: formRecebimento.value.forma_pagamento,
    p_data_recebimento: (formRecebimento.value.data_recebimento instanceof Date
      ? formRecebimento.value.data_recebimento
      : new Date(formRecebimento.value.data_recebimento)
    )
      .toISOString()
      .slice(0, 10),
  })
  salvandoRecebimento.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar recebimento', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Recebimento registrado', life: 3000 })
  dialogoRecebimentoAberto.value = false
  await carregar()
}

// ---------- Termo de ciência ----------
const dialogoTermoAberto = ref(false)
const salvandoTermo = ref(false)
const arquivoTermo = ref(null)

function abrirTermo(cobranca) {
  cobrancaAtual.value = cobranca
  arquivoTermo.value = null
  dialogoTermoAberto.value = true
}
function onArquivoTermoSelecionado(event) {
  arquivoTermo.value = event.target.files[0] || null
}
async function salvarTermo() {
  if (!arquivoTermo.value) {
    toast.add({ severity: 'warn', summary: 'Selecione o arquivo do termo', life: 4000 })
    return
  }
  salvandoTermo.value = true
  const caminhoDestino = `termo-${cobrancaAtual.value.id}/${Date.now()}-${arquivoTermo.value.name}`
  const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, arquivoTermo.value)
  if (erroUpload) {
    salvandoTermo.value = false
    toast.add({ severity: 'error', summary: 'Erro ao enviar arquivo', detail: erroUpload.message, life: 6000 })
    return
  }
  const { error } = await supabase.rpc('rpc_registrar_termo_ciencia', { p_cobranca_id: cobrancaAtual.value.id, p_arquivo_path: caminhoDestino })
  salvandoTermo.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar termo', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Termo de ciência registrado', life: 3000 })
  dialogoTermoAberto.value = false
  await carregar()
}

// ---------- Cancelar ----------
function confirmarCancelamento(cobranca) {
  confirm.require({
    message: `Cancelar a cobrança de ${formatarMoeda(cobranca.valor_total)} de ${cobranca.cliente?.nome}?`,
    header: 'Confirmar cancelamento',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Cancelar cobrança',
    rejectLabel: 'Voltar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_cancelar_cobranca', { p_cobranca_id: cobranca.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao cancelar', detail: error.message, life: 6000 })
        return
      }
      toast.add({ severity: 'success', summary: 'Cobrança cancelada', life: 3000 })
      await carregar()
    },
  })
}

onMounted(() => {
  carregar().then(() => {
    if (route.query.cliente_id) abrirNovo()
  })
})
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Financeiro — Cobranças</h2>
      <Button v-if="podeGerir()" label="Nova Cobrança" icon="pi pi-plus" @click="abrirNovo" />
    </div>

    <DataTable :value="cobrancas" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column header="Cliente"><template #body="{ data }">{{ data.cliente?.nome }}</template></Column>
      <Column header="Origem"><template #body="{ data }">{{ origensLabel(data) }}</template></Column>
      <Column header="Valor Total"><template #body="{ data }">{{ formatarMoeda(data.valor_total) }}</template></Column>
      <Column header="Recebido"><template #body="{ data }">{{ formatarMoeda(valorRecebido(data)) }}</template></Column>
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[statusExibicao(data)]" :value="statusExibicao(data)" />
        </template>
      </Column>
      <Column header="Parcelas">
        <template #body="{ data }">
          <span v-if="data.parcelas.length === 0" class="hint">sem parcelamento</span>
          <span v-else>
            <Tag
              v-for="p in data.parcelas"
              :key="p.id"
              :severity="p.status === 'paga' ? 'success' : p.vencimento < hojeISO() ? 'danger' : 'secondary'"
              :value="`${p.numero_parcela}: ${formatarMoeda(p.valor)}`"
              style="margin-right: 0.25rem; margin-bottom: 0.25rem"
            />
          </span>
        </template>
      </Column>
      <Column header="Termo">
        <template #body="{ data }">
          <i v-if="data.termos_ciencia_debito.length > 0" class="pi pi-check-circle" style="color: #16a34a" title="Termo registrado"></i>
        </template>
      </Column>
      <Column header="Ações" style="width: 320px">
        <template #body="{ data }">
          <template v-if="data.status === 'aberta' && podeGerir()">
            <Button v-if="data.parcelas.length === 0" label="Parcelar" size="small" text @click="abrirParcelar(data)" />
            <Button label="Cancelar" size="small" text severity="danger" @click="confirmarCancelamento(data)" />
          </template>
          <Button
            v-if="['aberta', 'parcial'].includes(data.status) && parcelasPendentes(data).length > 0 && podeGerir()"
            label="Receber"
            size="small"
            severity="success"
            @click="abrirRecebimento(data)"
          />
          <Button
            v-if="data.status !== 'cancelada' && podeTermo()"
            label="Termo"
            size="small"
            text
            @click="abrirTermo(data)"
          />
        </template>
      </Column>
    </DataTable>

    <!-- Nova cobrança -->
    <Dialog v-model:visible="dialogoNovoAberto" modal header="Nova Cobrança" style="width: 620px">
      <div class="form-campo">
        <label>Cliente</label>
        <Select
          v-model="clienteSelecionado"
          :options="clientes"
          optionLabel="nome"
          optionValue="id"
          filter
          placeholder="Selecione o cliente"
          @update:modelValue="buscarPendencias($event)"
        />
      </div>

      <div v-if="clienteSelecionado">
        <h4>OS concluídas pendentes de cobrança</h4>
        <p v-if="!buscandoPendencias && osPendentes.length === 0" class="hint">Nenhuma OS pendente para este cliente.</p>
        <div v-for="os in osPendentes" :key="os.id" class="linha-pendencia">
          <Checkbox v-model="osSelecionadas" :value="os.id" />
          <span>OS {{ os.veiculo?.placa }} <span v-if="os.veiculo?.prefixo">({{ os.veiculo.prefixo }})</span> — {{ formatarMoeda(valorOsPendente(os)) }}</span>
        </div>

        <h4>Vendas avulsas pendentes de cobrança</h4>
        <p v-if="!buscandoPendencias && vendasPendentes.length === 0" class="hint">Nenhuma venda avulsa pendente para este cliente.</p>
        <div v-for="venda in vendasPendentes" :key="venda.id" class="linha-pendencia">
          <Checkbox v-model="vendasSelecionadas" :value="venda.id" />
          <span>Venda Avulsa de {{ new Date(venda.criado_em).toLocaleDateString('pt-BR') }} — {{ formatarMoeda(valorVendaPendente(venda)) }}</span>
        </div>

        <p class="total-selecionado"><strong>Total selecionado: {{ formatarMoeda(totalSelecionado) }}</strong></p>
      </div>

      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovoAberto = false" />
        <Button label="Gerar Cobrança" :loading="salvandoNovo" @click="criarCobranca" />
      </template>
    </Dialog>

    <!-- Parcelar -->
    <Dialog v-model:visible="dialogoParcelarAberto" modal header="Parcelar Cobrança" style="width: 560px">
      <p v-if="cobrancaAtual">Valor total: <strong>{{ formatarMoeda(cobrancaAtual.valor_total) }}</strong></p>
      <div v-for="(linha, index) in linhasParcelas" :key="index" class="linha-item">
        <span class="numero-parcela">{{ linha.numero_parcela }}</span>
        <InputNumber v-model="linha.valor" mode="currency" currency="BRL" locale="pt-BR" class="item-valor" />
        <DatePicker v-model="linha.vencimento" dateFormat="dd/mm/yy" showIcon class="item-data" />
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerParcela(index)" />
      </div>
      <div class="botoes-item">
        <Button label="Adicionar parcela" icon="pi pi-plus" text size="small" @click="adicionarParcela" />
        <Button label="Dividir igualmente" icon="pi pi-percentage" text size="small" @click="dividirIgualmente" />
      </div>
      <p class="hint">Soma das parcelas: {{ formatarMoeda(somaParcelas) }}</p>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoParcelarAberto = false" />
        <Button label="Formalizar Parcelamento" :loading="salvandoParcelamento" @click="salvarParcelamento" />
      </template>
    </Dialog>

    <!-- Recebimento -->
    <Dialog v-model:visible="dialogoRecebimentoAberto" modal header="Registrar Recebimento" style="width: 420px">
      <div class="form-campo" v-if="cobrancaAtual">
        <label>Parcela</label>
        <Select
          v-model="parcelaSelecionadaId"
          :options="parcelasPendentes(cobrancaAtual)"
          optionValue="id"
          placeholder="Selecione a parcela"
          @update:modelValue="selecionouParcela"
        >
          <template #option="{ option }">Parcela {{ option.numero_parcela }} — saldo {{ formatarMoeda(saldoParcela(option)) }}</template>
          <template #value="{ value }">
            <span v-if="value">
              Parcela {{ cobrancaAtual.parcelas.find((p) => p.id === value)?.numero_parcela }}
            </span>
          </template>
        </Select>
      </div>
      <div class="form-campo">
        <label>Valor Recebido</label>
        <InputNumber v-model="formRecebimento.valor_recebido" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Forma de Pagamento</label>
        <InputText v-model="formRecebimento.forma_pagamento" placeholder="Dinheiro, PIX, cartão, boleto..." />
      </div>
      <div class="form-campo">
        <label>Data do Recebimento</label>
        <DatePicker v-model="formRecebimento.data_recebimento" dateFormat="dd/mm/yy" showIcon />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoRecebimentoAberto = false" />
        <Button label="Registrar" :loading="salvandoRecebimento" @click="salvarRecebimento" />
      </template>
    </Dialog>

    <!-- Termo de ciência -->
    <Dialog v-model:visible="dialogoTermoAberto" modal header="Termo de Ciência de Débito" style="width: 420px">
      <div class="form-campo">
        <label>Arquivo assinado (foto/PDF)</label>
        <input type="file" @change="onArquivoTermoSelecionado" accept="image/*,application/pdf" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoTermoAberto = false" />
        <Button label="Salvar" :loading="salvandoTermo" @click="salvarTermo" />
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
.numero-parcela {
  width: 1.5rem;
  font-weight: 600;
  text-align: center;
}
.item-valor,
.item-data {
  flex: 1;
}
.botoes-item {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.25rem;
}
.linha-pendencia {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}
.total-selecionado {
  margin-top: 0.75rem;
  padding-top: 0.75rem;
  border-top: 1px solid #e5e7eb;
}
.hint {
  color: #6b7280;
  font-size: 0.85rem;
}
</style>
