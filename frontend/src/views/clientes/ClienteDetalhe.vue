<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'

const route = useRoute()
const router = useRouter()
const toast = useToast()

const clienteId = computed(() => route.params.id)
const cliente = ref(null)
const veiculos = ref([])
const ordens = ref([])
const vendas = ref([])
const carregando = ref(true)

const severidadeStatus = {
  aberta: 'info',
  em_diagnostico: 'warn',
  aguardando_aprovacao: 'warn',
  em_execucao: 'warn',
  aguardando_teste: 'warn',
  concluida: 'success',
  liberada: 'success',
  reaberta_garantia: 'danger',
  cancelada: 'danger',
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

function totalVenda(venda) {
  return (venda.venda_avulsa_itens ?? []).reduce((s, i) => s + i.quantidade * i.valor_unitario, 0)
}

function itensVenda(venda) {
  return (venda.venda_avulsa_itens ?? []).map((i) => `${i.peca?.descricao} x${i.quantidade}`).join(', ')
}

async function carregar() {
  carregando.value = true
  const [respCliente, respVeiculos, respOrdens, respVendas] = await Promise.all([
    supabase.from('clientes').select('id, tipo, nome, documento, telefone, email').eq('id', clienteId.value).single(),
    supabase
      .from('veiculos')
      .select('id, placa, prefixo, modelo, ano')
      .eq('cliente_id', clienteId.value)
      .is('deleted_at', null)
      .order('placa'),
    supabase
      .from('ordens_servico')
      .select('id, tipo, status, data_abertura, data_liberacao, veiculo:veiculos(placa, prefixo)')
      .eq('cliente_id', clienteId.value)
      .order('data_abertura', { ascending: false })
      .limit(15),
    supabase
      .from('vendas_avulsas')
      .select('id, criado_em, venda_avulsa_itens(quantidade, valor_unitario, peca:pecas(descricao))')
      .eq('cliente_id', clienteId.value)
      .order('criado_em', { ascending: false })
      .limit(15),
  ])

  if (respCliente.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar cliente', detail: respCliente.error.message, life: 5000 })
    carregando.value = false
    return
  }
  cliente.value = respCliente.data
  veiculos.value = respVeiculos.data ?? []
  ordens.value = respOrdens.data ?? []
  vendas.value = respVendas.data ?? []
  carregando.value = false
}

watch(clienteId, carregar, { immediate: true })
</script>

<template>
  <div v-if="carregando">Carregando...</div>
  <div v-else-if="cliente">
    <div class="cabecalho">
      <div>
        <Button icon="pi pi-arrow-left" text @click="router.push('/clientes')" />
        <h2 style="display: inline">{{ cliente.nome }}</h2>
      </div>
      <Tag :severity="cliente.tipo === 'interno' ? 'info' : 'success'" :value="cliente.tipo" />
    </div>

    <p>
      <strong>Documento:</strong> {{ cliente.documento || '—' }} &nbsp;|&nbsp;
      <strong>Telefone:</strong> {{ cliente.telefone || '—' }} &nbsp;|&nbsp;
      <strong>E-mail:</strong> {{ cliente.email || '—' }}
    </p>

    <div class="secao">
      <h3>Veículos</h3>
      <p v-if="veiculos.length === 0" class="hint">Nenhum veículo cadastrado com este cliente como proprietário.</p>
      <DataTable v-else :value="veiculos" dataKey="id" size="small">
        <Column field="placa" header="Placa" />
        <Column field="prefixo" header="Prefixo" />
        <Column field="modelo" header="Modelo" />
        <Column field="ano" header="Ano" />
      </DataTable>
    </div>

    <div class="secao">
      <h3>Últimos Serviços (OS)</h3>
      <p v-if="ordens.length === 0" class="hint">Nenhuma ordem de serviço registrada para este cliente.</p>
      <DataTable v-else :value="ordens" dataKey="id" size="small" @row-click="(e) => router.push(`/os/${e.data.id}`)" style="cursor: pointer">
        <Column header="Veículo">
          <template #body="{ data }">{{ data.veiculo?.placa }} <span v-if="data.veiculo?.prefixo">({{ data.veiculo.prefixo }})</span></template>
        </Column>
        <Column field="tipo" header="Tipo" />
        <Column header="Status">
          <template #body="{ data }"><Tag :severity="severidadeStatus[data.status]" :value="data.status" /></template>
        </Column>
        <Column header="Abertura">
          <template #body="{ data }">{{ new Date(data.data_abertura).toLocaleString('pt-BR') }}</template>
        </Column>
        <Column header="Liberação">
          <template #body="{ data }">{{ data.data_liberacao ? new Date(data.data_liberacao).toLocaleString('pt-BR') : '—' }}</template>
        </Column>
      </DataTable>
    </div>

    <div class="secao">
      <h3>Últimas Vendas Avulsas</h3>
      <p v-if="vendas.length === 0" class="hint">Nenhuma venda avulsa registrada para este cliente.</p>
      <DataTable v-else :value="vendas" dataKey="id" size="small">
        <Column header="Itens">
          <template #body="{ data }">{{ itensVenda(data) }}</template>
        </Column>
        <Column header="Total">
          <template #body="{ data }">{{ formatarMoeda(totalVenda(data)) }}</template>
        </Column>
        <Column header="Data">
          <template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template>
        </Column>
      </DataTable>
    </div>
  </div>
</template>

<style scoped>
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}
.secao {
  margin-top: 1.5rem;
  padding-top: 1rem;
  border-top: 1px solid #e5e7eb;
}
.hint {
  color: #6b7280;
  font-size: 0.85rem;
}
</style>
