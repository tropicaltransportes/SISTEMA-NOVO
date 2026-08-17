<script setup>
// ETAPA 6 (P1-C) — item 1 (ORC-013/DOC-001/DOC-002): documento de
// orçamento. Dados vêm de rpc_dados_pdf_orcamento (backend) — versão
// específica (id da linha), sempre reproduzível mesmo depois de existir
// versão nova (rpc_criar_versao_orcamento nunca edita a versão anterior).
// "PDF" aqui é o navegador imprimindo esta página (Ctrl+P / botão) —
// mecanismo adequado à arquitetura atual (sem dependência nova no
// frontend), conforme permitido pela instrução do item 1.
//
// ETAPA UX-PDF-ORCAMENTO-01 — redesign comercial (layout apenas; nenhum
// cálculo, regra de negócio, aprovação, versionamento ou permissão foi
// alterado). Ver docs/testing/UX_PDF_ORCAMENTO_01_REPORT.md.
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import { STATUS_ORCAMENTO } from '../../constants/statusVisual'

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
// item 6 da instrução: "Emissão: 14/08/2026" — sem hora/segundos no PDF
// comercial (o timestamp completo continua preservado em orcamentos.criado_em
// no banco/auditoria; aqui só a apresentação é reduzida a data).
function formatarDataSomente(v) {
  return v ? new Date(v).toLocaleDateString('pt-BR') : '—'
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

// item 8/9/10/11 — PEÇAS x MÃO DE OBRA a partir do discriminador estrutural
// `natureza` (coluna gerada em orcamento_itens: 'peca' | 'servico_cadastrado'
// | 'servico_avulso' — FEATURE-SERVICOS-01), nunca por análise textual da
// descrição. Serviço avulso (sem vínculo ao catálogo) continua pertencendo
// à seção MÃO DE OBRA (item 11).
const itensPecas = computed(() => (d.value?.itens ?? []).filter((i) => i.natureza === 'peca'))
const itensMaoObra = computed(() => (d.value?.itens ?? []).filter((i) => i.natureza !== 'peca'))
const subtotalPecas = computed(() => itensPecas.value.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0))
const subtotalMaoObra = computed(() => itensMaoObra.value.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0))

// item 3/27 — status especial "cancelado" ganha faixa própria em vez do tag
// normal. item 2/40 — "Rascunho" nunca aparece no PDF comercial (documento
// não deveria circular externamente nesse estado; quando ocorre visualização
// interna, simplesmente omitimos o rótulo em vez de inventar um substituto).
const cancelado = computed(() => d.value?.orcamento?.status === 'cancelado')
const mostrarTagStatus = computed(() => d.value && !cancelado.value && d.value.orcamento.status !== 'rascunho')

// item 4/35 — mecanismo de logo: import.meta.glob estático não falha no
// build se o arquivo ainda não existir (retorna objeto vazio); assim que o
// dono do projeto adicionar o arquivo real neste caminho, ele passa a
// aparecer automaticamente, sem outra alteração de código.
// ARQUIVO ESPERADO   = src/assets/logo-tropical.(png|svg|webp)
// DIMENSÃO RECOMENDADA = altura ~96px (proporção livre, largura ajusta sozinha)
// FORMATO            = PNG transparente ou SVG (preferencial)
// LOCAL DE SUBSTITUIÇÃO = frontend/src/assets/ (ver este comentário)
const logoModules = import.meta.glob('../../assets/logo-tropical.*', { eager: true, import: 'default' })
const logoUrl = computed(() => Object.values(logoModules)[0] ?? null)

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
      <div v-if="cancelado" class="faixa-cancelado">ORÇAMENTO CANCELADO</div>

      <header class="doc-cabecalho">
        <div class="doc-marca">
          <img v-if="logoUrl" :src="logoUrl" alt="Tropical Transportes" class="doc-logo-img" />
          <div class="doc-marca-texto">
            <strong>{{ linhasEmpresa[0] }}</strong>
            <span v-if="linhasEmpresa[1]">{{ linhasEmpresa[1] }}</span>
          </div>
        </div>
        <div class="doc-numero">
          <span class="doc-titulo-tipo">Orçamento</span>
          <span class="doc-numero-valor">{{ d.orcamento.numero_legivel }}</span>
          <span class="doc-versao">Versão {{ d.orcamento.versao }}</span>
        </div>
      </header>

      <div class="doc-status-linha">
        <Tag v-if="mostrarTagStatus" :severity="STATUS_ORCAMENTO[d.orcamento.status]?.severidade" :value="STATUS_ORCAMENTO[d.orcamento.status]?.label ?? d.orcamento.status" />
        <span class="doc-emitido">Emissão: {{ formatarDataSomente(d.orcamento.criado_em) }}</span>
      </div>

      <div class="doc-blocos">
        <div class="doc-bloco">
          <span class="doc-bloco-titulo">Cliente</span>
          <p class="doc-bloco-linha-principal">{{ d.cliente.nome }}</p>
          <p v-if="d.cliente.documento" class="doc-bloco-linha">Documento: {{ d.cliente.documento }}</p>
          <p v-if="d.cliente.telefone" class="doc-bloco-linha">Telefone: {{ d.cliente.telefone }}</p>
          <p v-if="d.cliente.email" class="doc-bloco-linha">E-mail: {{ d.cliente.email }}</p>
        </div>
        <div class="doc-bloco">
          <span class="doc-bloco-titulo">Veículo</span>
          <p class="doc-bloco-linha-principal">
            {{ d.veiculo.placa }} <span v-if="d.veiculo.prefixo">({{ d.veiculo.prefixo }})</span>
          </p>
          <p v-if="d.veiculo.modelo" class="doc-bloco-linha">{{ d.veiculo.modelo }}<span v-if="d.veiculo.ano"> / {{ d.veiculo.ano }}</span></p>
        </div>
      </div>

      <div v-if="itensPecas.length" class="doc-secao-itens">
        <span class="doc-bloco-titulo">Peças</span>
        <table class="tabela-relatorio">
          <thead>
            <tr><th>Item</th><th>Qtde</th><th>Valor Unit.</th><th>Subtotal</th></tr>
          </thead>
          <tbody>
            <tr v-for="i in itensPecas" :key="i.id">
              <td>{{ i.descricao }}</td>
              <td>{{ i.quantidade }}</td>
              <td class="valor">{{ formatarMoeda(i.valor_unitario) }}</td>
              <td class="valor">{{ formatarMoeda(i.valor_total_original) }}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="linha-subtotal">
              <td colspan="3">Subtotal Peças</td>
              <td class="valor">{{ formatarMoeda(subtotalPecas) }}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      <div v-if="itensMaoObra.length" class="doc-secao-itens">
        <span class="doc-bloco-titulo">Mão de Obra</span>
        <table class="tabela-relatorio">
          <thead>
            <tr><th>Serviço</th><th>Qtde</th><th>Valor Unit.</th><th>Subtotal</th></tr>
          </thead>
          <tbody>
            <tr v-for="i in itensMaoObra" :key="i.id">
              <td>{{ i.descricao }}</td>
              <td>{{ i.quantidade }}</td>
              <td class="valor">{{ formatarMoeda(i.valor_unitario) }}</td>
              <td class="valor">{{ formatarMoeda(i.valor_total_original) }}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="linha-subtotal">
              <td colspan="3">Subtotal Mão de Obra</td>
              <td class="valor">{{ formatarMoeda(subtotalMaoObra) }}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      <div class="doc-resumo">
        <span class="doc-bloco-titulo">Resumo financeiro</span>
        <div v-if="itensPecas.length" class="doc-resumo-linha">
          <span>Subtotal Peças</span>
          <span>{{ formatarMoeda(subtotalPecas) }}</span>
        </div>
        <div v-if="itensMaoObra.length" class="doc-resumo-linha">
          <span>Subtotal Mão de Obra</span>
          <span>{{ formatarMoeda(subtotalMaoObra) }}</span>
        </div>
        <div class="doc-resumo-linha doc-resumo-separador">
          <span>Valor bruto</span>
          <span>{{ formatarMoeda(d.orcamento.valor_bruto) }}</span>
        </div>
        <div class="doc-resumo-linha" v-if="d.orcamento.desconto_valor > 0">
          <span>Desconto ({{ d.orcamento.desconto_percentual }}%)<span v-if="d.orcamento.desconto_motivo" class="hint"> — {{ d.orcamento.desconto_motivo }}</span></span>
          <span>-{{ formatarMoeda(d.orcamento.desconto_valor) }}</span>
        </div>
        <div class="doc-resumo-linha doc-resumo-total">
          <span>Valor total</span>
          <span>{{ formatarMoeda(d.orcamento.valor_liquido) }}</span>
        </div>
      </div>

      <div class="doc-condicoes">
        <span class="doc-bloco-titulo">Condições comerciais</span>
        <p class="doc-condicoes-linha">Garantia de 90 dias para peças e serviços, conforme regra vigente da oficina.</p>
        <p class="doc-condicoes-linha">Serviços adicionais identificados após o início da execução serão registrados e submetidos à aprovação antes de serem realizados.</p>
      </div>

      <footer class="doc-rodape">
        <p class="doc-rodape-marca">{{ linhasEmpresa[0] }}<span v-if="linhasEmpresa[1]"> — {{ linhasEmpresa[1] }}</span></p>
        <p class="doc-rodape-frase">Estamos à disposição para esclarecimentos.</p>
        <p class="doc-rodape-identificacao">Documento emitido eletronicamente • {{ d.orcamento.numero_legivel }} • Versão {{ d.orcamento.versao }}</p>
      </footer>
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
  position: relative;
  background: #ffffff;
  color: #1f2430;
  border-radius: 14px;
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35);
  padding: 40px 48px;
  overflow: hidden;
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

/* item 3/27 — faixa discreta de cancelamento, não some o conteúdo nem
   recalcula nada, só sinaliza. */
.faixa-cancelado {
  position: absolute;
  top: 22px;
  right: -46px;
  width: 200px;
  transform: rotate(40deg);
  text-align: center;
  background: #dc2626;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.6px;
  text-transform: uppercase;
  padding: 5px 0;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  z-index: 1;
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
.doc-logo-img {
  height: 44px;
  width: auto;
  max-width: 160px;
  object-fit: contain;
  flex-shrink: 0;
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
.doc-titulo-tipo {
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 1px;
  text-transform: uppercase;
  color: #1f2430;
}
.doc-numero-valor {
  font-family: var(--font-mono);
  font-weight: 700;
  font-size: 16px;
  color: #6d28d9;
  letter-spacing: 0.2px;
  margin-top: 2px;
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
  margin-bottom: 26px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.doc-bloco-titulo {
  display: block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  color: #7c3aed;
  margin-bottom: 8px;
  break-after: avoid;
  page-break-after: avoid;
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

.doc-secao-itens {
  margin-bottom: 22px;
  break-inside: avoid;
  page-break-inside: avoid;
}

.tabela-relatorio {
  width: 100%;
  border-collapse: collapse;
  margin: 0;
}
.tabela-relatorio th,
.tabela-relatorio td {
  text-align: left;
  padding: 0.55rem 0.6rem;
  border-bottom: 1px solid #e5e7eb;
  font-size: 0.85rem;
}
.tabela-relatorio th {
  background: #f5f3ff;
  color: #6d28d9;
  font-weight: 600;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.3px;
}
.tabela-relatorio tbody tr {
  break-inside: avoid;
  page-break-inside: avoid;
}
.tabela-relatorio td.valor,
.tabela-relatorio th:nth-child(2),
.tabela-relatorio th:nth-child(3),
.tabela-relatorio th:nth-child(4) {
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.tabela-relatorio tbody td:nth-child(2) {
  text-align: right;
}
.linha-subtotal td {
  border-bottom: none;
  border-top: 1.5px solid #ddd6fe;
  font-weight: 700;
  color: #1f2430;
  padding-top: 0.6rem;
}
.linha-subtotal td:first-child {
  text-align: right;
  color: #6b7280;
  font-weight: 600;
  text-transform: uppercase;
  font-size: 0.72rem;
  letter-spacing: 0.3px;
}

.doc-resumo {
  margin-left: auto;
  max-width: 360px;
  margin-bottom: 22px;
  break-inside: avoid;
  page-break-inside: avoid;
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
.doc-resumo-separador {
  border-top: 1px solid #e5e7eb;
  margin-top: 4px;
  padding-top: 8px;
}
.doc-resumo-total {
  border-top: 1px solid #e5e7eb;
  margin-top: 4px;
  padding-top: 10px;
  font-weight: 700;
  font-size: 17px;
  color: #1f2430;
}
.doc-resumo-total span:last-child {
  color: #6d28d9;
}

.hint {
  color: #6b7280;
  font-size: 0.85rem;
}

.doc-condicoes {
  break-inside: avoid;
  page-break-inside: avoid;
  margin-bottom: 22px;
}
.doc-condicoes-linha {
  margin: 0 0 4px;
  font-size: 12px;
  color: #4b5563;
  line-height: 1.5;
}

.doc-rodape {
  border-top: 1px solid #ede9fe;
  padding-top: 16px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.doc-rodape-marca {
  margin: 0;
  font-weight: 600;
  font-size: 13px;
  color: #1f2430;
}
.doc-rodape-frase {
  margin: 2px 0 10px;
  font-size: 12px;
  color: #6b7280;
}
.doc-rodape-identificacao {
  margin: 0;
  font-size: 10.5px;
  color: #9ca3af;
}

@media print {
  @page {
    size: A4;
    margin: 14mm 12mm;
  }
  .no-print {
    display: none !important;
  }
  .pagina-relatorio {
    max-width: none;
  }
  .documento-papel {
    box-shadow: none;
    padding: 0;
    border-radius: 0;
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
