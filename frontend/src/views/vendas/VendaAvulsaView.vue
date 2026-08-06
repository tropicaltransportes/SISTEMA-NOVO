<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputNumber from 'primevue/inputnumber'
import Tag from 'primevue/tag'

const router = useRouter()
const auth = useAuthStore()
const toast = useToast()

const podeGerarCobranca = () => ['suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const vendas = ref([])
const clientes = ref([])
const pecas = ref([])
const vendasCobradas = ref(new Set())
const carregando = ref(true)
const salvando = ref(false)

const clienteId = ref(null)
const itens = ref([{ peca_id: null, quantidade: 1, valor_unitario: 0 }])

const totalVenda = computed(() => itens.value.reduce((s, i) => s + (i.quantidade || 0) * (i.valor_unitario || 0), 0))

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

async function carregar() {
  carregando.value = true
  const [respVendas, respClientes, respPecas] = await Promise.all([
    supabase
      .from('vendas_avulsas')
      .select('id, criado_em, cliente:clientes(id, nome), venda_avulsa_itens(id, quantidade, valor_unitario, peca:pecas(descricao))')
      .order('criado_em', { ascending: false })
      .limit(30),
    supabase.from('clientes').select('id, nome').is('deleted_at', null).order('nome'),
    supabase.from('pecas').select('id, sku, descricao, saldo_atual, custo_medio').is('deleted_at', null).order('descricao'),
  ])
  if (respVendas.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar vendas', detail: respVendas.error.message, life: 5000 })
  } else {
    vendas.value = respVendas.data
  }
  clientes.value = respClientes.data ?? []
  pecas.value = respPecas.data ?? []

  const vendaIds = (vendas.value ?? []).map((v) => v.id)
  if (vendaIds.length && podeGerarCobranca()) {
    const { data: origens } = await supabase
      .from('cobranca_origens')
      .select('venda_avulsa_id, cobranca:cobrancas(status)')
      .in('venda_avulsa_id', vendaIds)
    vendasCobradas.value = new Set((origens ?? []).filter((o) => o.cobranca?.status !== 'cancelada').map((o) => o.venda_avulsa_id))
  }
  carregando.value = false
}

function adicionarItem() {
  itens.value.push({ peca_id: null, quantidade: 1, valor_unitario: 0 })
}
function removerItem(index) {
  itens.value.splice(index, 1)
}
function selecionouPeca(item) {
  const p = pecas.value.find((x) => x.id === item.peca_id)
  if (p) item.valor_unitario = p.custo_medio
}

async function registrarVenda() {
  if (!clienteId.value) {
    toast.add({ severity: 'warn', summary: 'Selecione o cliente', life: 4000 })
    return
  }
  if (itens.value.length === 0 || itens.value.some((i) => !i.peca_id || i.quantidade <= 0)) {
    toast.add({ severity: 'warn', summary: 'Revise os itens', detail: 'Cada item precisa de peça e quantidade maior que zero.', life: 4000 })
    return
  }
  salvando.value = true
  const { error } = await supabase.rpc('rpc_criar_venda_avulsa', {
    p_cliente_id: clienteId.value,
    p_itens: itens.value.map((i) => ({ peca_id: i.peca_id, quantidade: i.quantidade, valor_unitario: i.valor_unitario })),
  })
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar venda', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Venda registrada, estoque baixado', life: 3000 })
  clienteId.value = null
  itens.value = [{ peca_id: null, quantidade: 1, valor_unitario: 0 }]
  await carregar()
}

onMounted(carregar)
</script>

<template>
  <div>
    <h2>Venda Avulsa de Peças</h2>

    <div class="painel">
      <div class="form-campo">
        <label>Cliente</label>
        <Select v-model="clienteId" :options="clientes" optionLabel="nome" optionValue="id" filter placeholder="Selecione o cliente" />
      </div>

      <h4>Itens</h4>
      <div v-for="(item, index) in itens" :key="index" class="linha-item">
        <Select
          v-model="item.peca_id"
          :options="pecas"
          optionLabel="descricao"
          optionValue="id"
          filter
          placeholder="Peça"
          class="item-peca"
          @update:modelValue="selecionouPeca(item)"
        />
        <InputNumber v-model="item.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" class="item-qtd" />
        <InputNumber v-model="item.valor_unitario" placeholder="Valor Unit." mode="currency" currency="BRL" locale="pt-BR" class="item-valor" />
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerItem(index)" />
      </div>
      <Button label="Adicionar item" icon="pi pi-plus" text size="small" @click="adicionarItem" />

      <div class="rodape-painel">
        <strong>Total: {{ formatarMoeda(totalVenda) }}</strong>
        <Button label="Registrar Venda" :loading="salvando" @click="registrarVenda" />
      </div>
    </div>

    <h3>Últimas Vendas</h3>
    <DataTable :value="vendas" :loading="carregando" dataKey="id" stripedRows>
      <Column header="Cliente"><template #body="{ data }">{{ data.cliente?.nome }}</template></Column>
      <Column header="Itens">
        <template #body="{ data }">{{ data.venda_avulsa_itens.map((i) => `${i.peca?.descricao} x${i.quantidade}`).join(', ') }}</template>
      </Column>
      <Column header="Total">
        <template #body="{ data }">{{ formatarMoeda(data.venda_avulsa_itens.reduce((s, i) => s + i.quantidade * i.valor_unitario, 0)) }}</template>
      </Column>
      <Column header="Data"><template #body="{ data }">{{ new Date(data.criado_em).toLocaleString('pt-BR') }}</template></Column>
      <Column header="Cobrança" v-if="podeGerarCobranca()">
        <template #body="{ data }">
          <Tag v-if="vendasCobradas.has(data.id)" severity="success" value="Cobrança gerada" />
          <Button
            v-else
            label="Gerar Cobrança"
            size="small"
            text
            @click="router.push({ path: '/financeiro/cobrancas', query: { cliente_id: data.cliente.id, venda_id: data.id } })"
          />
        </template>
      </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.painel {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 1.25rem;
  margin-bottom: 1.5rem;
  max-width: 720px;
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
.item-peca {
  flex: 2;
}
.item-qtd,
.item-valor {
  flex: 1;
}
.rodape-painel {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 1rem;
  padding-top: 1rem;
  border-top: 1px solid #e5e7eb;
}
</style>
