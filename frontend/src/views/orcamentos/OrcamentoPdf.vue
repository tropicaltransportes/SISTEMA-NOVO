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
import { STATUS_ORCAMENTO, STATUS_ITEM_ORCAMENTO } from '../../constants/statusVisual'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const orcamentoId = computed(() => route.params.id)
const d = ref(null)
const carregando = ref(true)
const erro = ref(false)

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
function formatarData(v) {
  return v ? new Date(v).toLocaleString('pt-BR') : '—'
}

async function carregar() {
  carregando.value = true
  erro.value = false
  const { data, error } = await supabase.rpc('rpc_dados_pdf_orcamento', { p_orcamento_id: orcamentoId.value })
  if (error) {
    erro.value = true
    toast.add({ severity: 'error', summary: 'Erro ao carregar orçamento', detail: error.message, life: 6000 })
    carregando.value = false
    return
  }
  d.value = data
  carregando.value = false
}
carregar()

// ETAPA UX-ORCAMENTOS-01 — item 23: "resumo financeiro" com valor
// aprovado/rejeitado, agregando os itens já retornados pela RPC (mesma
// técnica já usada em OrcamentosList.vue, só que aqui somando
// `valor_liquido` — o valor já líquido de desconto que a própria RPC
// calcula por item — em vez de quantidade×valor_unitário, porque este
// documento já mostra os valores líquidos por item). Não é um cálculo
// paralelo divergente: é a soma dos números que a RPC já devolveu.
const valorAprovado = computed(() =>
  (d.value?.itens ?? []).filter((i) => i.status_aprovacao === 'aprovado').reduce((s, i) => s + (i.valor_liquido ?? 0), 0)
)
const valorRejeitado = computed(() =>
  (d.value?.itens ?? []).filter((i) => i.status_aprovacao === 'rejeitado').reduce((s, i) => s + (i.valor_liquido ?? 0), 0)
)

// Quebra "Tropical Transportes — Oficina Mecânica" (string real, vinda de
// d.empresa.nome) em 2 linhas só para hierarquia visual do letterhead —
// não altera nem inventa o texto, só onde a linha quebra.
const linhasEmpresa = computed(() => {
  const nome = d.value?.empresa?.nome
  if (!nome) return []
  const partes = nome.split(' — ')
  return partes.length === 2 ? partes : [nome]
})
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/orcamentos')" />
      <Button label="Imprimir / PDF" icon="pi pi-print" size="small" class="btn-gradiente" @click="window.print()" />
    </div>

    <div v-if="carregando" class="documento-papel documento-estado">Carregando...</div>
    <div v-else-if="erro" class="documento-papel documento-estado documento-erro">
      Não foi possível carregar este orçamento.
    </div>

    <div v-else-if="d" class="documento-papel">
      <header class="doc-cabecalho">
        <div class="doc-marca">
          <div class="doc-logo"><span></span></div>
          <div class="doc-marca-texto">
            <strong>{{ linhasEmpresa[0] }}</strong>
            <span v-if="linhasEmpresa[1]">{{ linhasEmpresa[1] }}</span>
          </div>
        </div>
        <div class="doc-numero">
          <span class="doc-numero-valor">{{ d.orcamento.numero_legivel }}</span>
          <span class="doc-versao">Versão {{ d.orcamento.versao }}</span>
        </div>
      </header>

      <div class="doc-status-linha">
        <Tag :severity="STATUS_ORCAMENTO[d.orcamento.status]?.severidade" :value="STATUS_ORCAMENTO[d.orcamento.status]?.label ?? d.orcamento.status" />
        <span class="doc-emitido">Emitido em {{ formatarData(d.orcamento.criado_em) }}</span>
      </div>

      <div class="doc-blocos">
        <div class="doc-bloco">
          <span class="doc-bloco-titulo">Cliente</span>
          <p class="doc-bloco-linha-principal">{{ d.cliente.nome }}</p>
          <p class="doc-bloco-linha">{{ d.cliente.documento || 'Sem documento informado' }}</p>
        </div>
        <div class="doc-bloco">
          <span class="doc-bloco-titulo">Veículo</span>
          <p class="doc-bloco-linha-principal">
            {{ d.veiculo.placa }} <span v-if="d.veiculo.prefixo">({{ d.veiculo.prefixo }})</span>
          </p>
          <p class="doc-bloco-linha">{{ d.veiculo.modelo }}<span v-if="d.veiculo.ano"> / {{ d.veiculo.ano }}</span></p>
        </div>
      </div>

      <span class="doc-bloco-titulo doc-itens-titulo">Itens</span>
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
            <td><Tag :severity="STATUS_ITEM_ORCAMENTO[i.status_aprovacao]?.severidade" :value="STATUS_ITEM_ORCAMENTO[i.status_aprovacao]?.label ?? i.status_aprovacao" /></td>
          </tr>
        </tbody>
      </table>

      <div class="doc-resumo">
        <span class="doc-bloco-titulo">Resumo financeiro</span>
        <div class="doc-resumo-linha">
          <span>Valor bruto</span>
          <span>{{ formatarMoeda(d.orcamento.valor_bruto) }}</span>
        </div>
        <div class="doc-resumo-linha" v-if="d.orcamento.desconto_valor > 0">
          <span>Desconto ({{ d.orcamento.desconto_percentual }}%)<span v-if="d.orcamento.desconto_motivo" class="hint"> — {{ d.orcamento.desconto_motivo }}</span></span>
          <span>-{{ formatarMoeda(d.orcamento.desconto_valor) }}</span>
        </div>
        <div class="doc-resumo-linha">
          <span>Valor aprovado</span>
          <span class="valor-aprovado">{{ formatarMoeda(valorAprovado) }}</span>
        </div>
        <div class="doc-resumo-linha">
          <span>Valor rejeitado</span>
          <span class="valor-rejeitado">{{ formatarMoeda(valorRejeitado) }}</span>
        </div>
        <div class="doc-resumo-linha doc-resumo-total">
          <span>Valor total</span>
          <span>{{ formatarMoeda(d.orcamento.valor_liquido) }}</span>
        </div>
      </div>

      <p v-if="d.orcamento.autorizado_por_nome" class="hint">
        Autorizado por: {{ d.orcamento.autorizado_por_nome }} em {{ formatarData(d.orcamento.autorizado_em) }}
      </p>

      <div class="info-box">
        <i class="pi pi-info-circle"></i>
        <span>
          Este documento representa a <strong>versão {{ d.orcamento.versao }}</strong> do orçamento. Versões
          posteriores (quando existirem) não alteram nem substituem este registro — cada versão permanece
          reproduzível individualmente.
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.pagina-relatorio {
  max-width: 900px;
}
.acoes-topo {
  display: flex;
  justify-content: space-between;
  margin-bottom: 1rem;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}

/* ETAPA UX-ORCAMENTOS-01 — item 27: o documento em si (tela e impressão)
   usa fundo branco/institucional, mesmo com a interface do app em dark
   mode — é a mesma folha que sai na impressão (Ctrl+P), então já nasce
   correta para impressão sem precisar de regras de cor diferentes por
   modo. */
.documento-papel {
  background: #ffffff;
  color: #1f2430;
  border-radius: 14px;
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35);
  padding: 40px 48px;
}
.documento-estado {
  text-align: center;
  color: #6b7280;
  padding: 80px 20px;
}
.documento-erro {
  color: #b91c1c;
  font-weight: 600;
}

.doc-cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding-bottom: 18px;
  border-bottom: 2px solid #ede9fe;
  margin-bottom: 18px;
}
.doc-marca {
  display: flex;
  align-items: center;
  gap: 12px;
}
.doc-logo {
  width: 38px;
  height: 38px;
  border-radius: 11px;
  background: linear-gradient(135deg, #8b5cf6, #6d28d9);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.doc-logo span {
  width: 12px;
  height: 12px;
  border-radius: 4px;
  background: #fff;
  display: block;
}
.doc-marca-texto {
  display: flex;
  flex-direction: column;
  line-height: 1.3;
}
.doc-marca-texto strong {
  font-size: 16px;
  color: #1f2430;
}
.doc-marca-texto span {
  font-size: 12px;
  color: #6b7280;
}
.doc-numero {
  text-align: right;
  display: flex;
  flex-direction: column;
}
.doc-numero-valor {
  font-family: var(--font-mono);
  font-weight: 700;
  font-size: 16px;
  color: #6d28d9;
  letter-spacing: 0.2px;
}
.doc-versao {
  font-size: 12px;
  color: #6b7280;
  margin-top: 2px;
}

.doc-status-linha {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 22px;
}
.doc-emitido {
  font-size: 12.5px;
  color: #6b7280;
}

.doc-blocos {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  margin-bottom: 22px;
}
.doc-bloco-titulo {
  display: block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  color: #8b5cf6;
  margin-bottom: 6px;
}
.doc-itens-titulo {
  margin-bottom: 8px;
}
.doc-bloco-linha-principal {
  margin: 0 0 2px;
  font-weight: 600;
  font-size: 14px;
  color: #1f2430;
}
.doc-bloco-linha {
  margin: 0;
  font-size: 12.5px;
  color: #6b7280;
}

.tabela-relatorio {
  width: 100%;
  border-collapse: collapse;
  margin: 0 0 22px;
}
.tabela-relatorio th,
.tabela-relatorio td {
  text-align: left;
  padding: 0.5rem 0.6rem;
  border-bottom: 1px solid #e5e7eb;
  font-size: 0.85rem;
}
.tabela-relatorio th {
  color: #6b7280;
  font-weight: 600;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.3px;
}

.doc-resumo {
  margin-left: auto;
  max-width: 340px;
  margin-bottom: 18px;
}
.doc-resumo-linha {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 4px 0;
  font-size: 13px;
  color: #374151;
}
.doc-resumo-linha .hint {
  display: block;
  font-size: 11px;
}
.valor-aprovado {
  color: #15803d;
  font-weight: 600;
}
.valor-rejeitado {
  color: #b91c1c;
}
.doc-resumo-total {
  border-top: 1px solid #e5e7eb;
  margin-top: 4px;
  padding-top: 8px;
  font-weight: 700;
  font-size: 15px;
  color: #1f2430;
}

.hint {
  color: #6b7280;
  font-size: 0.85rem;
}

.info-box {
  display: flex;
  gap: 10px;
  background: #f5f3ff;
  border-radius: 10px;
  padding: 12px 14px;
  margin-top: 18px;
  font-size: 12px;
  color: #4b5563;
  line-height: 1.5;
}
.info-box i {
  color: #8b5cf6;
  font-size: 14px;
  margin-top: 1px;
}

@media print {
  .no-print {
    display: none !important;
  }
  .documento-papel {
    box-shadow: none;
    padding: 0;
  }
}

@media (max-width: 640px) {
  .documento-papel {
    padding: 24px 20px;
  }
  .doc-blocos {
    grid-template-columns: 1fr;
  }
  .doc-resumo {
    max-width: none;
  }
}
</style>
