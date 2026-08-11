<script setup>
// ETAPA 6 (P1-C) — item 1 (ORC-013/DOC-001/DOC-002): documento de
// orçamento. Dados vêm de rpc_dados_pdf_orcamento (backend) — versão
// específica (id da linha), sempre reproduzível mesmo depois de existir
// versão nova (rpc_criar_versao_orcamento nunca edita a versão anterior).
// "PDF" aqui é o navegador imprimindo esta página (Ctrl+P / botão) —
// mecanismo adequado à arquitetura atual (sem dependência nova no
// frontend), conforme permitido pela instrução do item 1.
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const orcamentoId = computed(() => route.params.id)
const d = ref(null)
const carregando = ref(true)

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(v) { return v ? new Date(v).toLocaleString('pt-BR') : '—' }

async function carregar() {
  carregando.value = true
  const { data, error } = await supabase.rpc('rpc_dados_pdf_orcamento', { p_orcamento_id: orcamentoId.value })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar orçamento', detail: error.message, life: 6000 })
    carregando.value = false
    return
  }
  d.value = data
  carregando.value = false
}
carregar()

const tagSeveridade = { pendente: 'warn', aprovado: 'success', rejeitado: 'danger' }
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/orcamentos')" />
      <Button label="Imprimir / PDF" icon="pi pi-print" size="small" @click="window.print()" />
    </div>
    <div v-if="carregando">Carregando...</div>
    <div v-else-if="d">
      <h2>{{ d.empresa.nome }}</h2>
      <h3>Orçamento {{ d.orcamento.numero_legivel }} — Versão {{ d.orcamento.versao }}</h3>
      <p>Situação: <Tag :value="d.orcamento.status" /> — Emitido em {{ formatarData(d.orcamento.criado_em) }}</p>
      <p><strong>Cliente:</strong> {{ d.cliente.nome }} ({{ d.cliente.documento || 'sem documento' }})</p>
      <p><strong>Veículo:</strong> {{ d.veiculo.placa }} <span v-if="d.veiculo.prefixo">({{ d.veiculo.prefixo }})</span> — {{ d.veiculo.modelo }} <span v-if="d.veiculo.ano">/{{ d.veiculo.ano }}</span></p>

      <table class="tabela-relatorio">
        <thead>
          <tr>
            <th>Item</th><th>Qtde</th><th>Valor Unit.</th><th>Subtotal</th><th>Desconto</th><th>Valor Líquido</th><th>Situação</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in d.itens" :key="i.id">
            <td>{{ i.descricao }}</td>
            <td>{{ i.quantidade }}</td>
            <td>{{ formatarMoeda(i.valor_unitario) }}</td>
            <td>{{ formatarMoeda(i.valor_total_original) }}</td>
            <td>{{ formatarMoeda(i.desconto_rateado) }}</td>
            <td>{{ formatarMoeda(i.valor_liquido) }}</td>
            <td><Tag :severity="tagSeveridade[i.status_aprovacao]" :value="i.status_aprovacao" /></td>
          </tr>
        </tbody>
      </table>

      <div class="totais">
        <p>Valor Bruto: {{ formatarMoeda(d.orcamento.valor_bruto) }}</p>
        <p v-if="d.orcamento.desconto_valor > 0">
          Desconto ({{ d.orcamento.desconto_percentual }}%): -{{ formatarMoeda(d.orcamento.desconto_valor) }}
          <span class="hint" v-if="d.orcamento.desconto_motivo">— {{ d.orcamento.desconto_motivo }}</span>
        </p>
        <p><strong>Valor Total: {{ formatarMoeda(d.orcamento.valor_liquido) }}</strong></p>
      </div>

      <p v-if="d.orcamento.autorizado_por_nome" class="hint">Autorizado por: {{ d.orcamento.autorizado_por_nome }} em {{ formatarData(d.orcamento.autorizado_em) }}</p>

      <p class="hint" style="margin-top:1.5rem">
        Este documento representa a VERSÃO {{ d.orcamento.versao }} do orçamento. Versões posteriores (quando existirem) não alteram nem substituem
        este registro — cada versão permanece reproduzível individualmente.
      </p>
    </div>
  </div>
</template>

<style scoped>
.pagina-relatorio { max-width: 900px; }
.acoes-topo { display: flex; justify-content: space-between; margin-bottom: 1rem; }
.tabela-relatorio { width: 100%; border-collapse: collapse; margin: 0.75rem 0 1rem; }
.tabela-relatorio th, .tabela-relatorio td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #e5e7eb; font-size: 0.85rem; }
.totais { margin-top: 1rem; text-align: right; }
.hint { color: #6b7280; font-size: 0.85rem; }
@media print { .no-print { display: none !important; } }
</style>
