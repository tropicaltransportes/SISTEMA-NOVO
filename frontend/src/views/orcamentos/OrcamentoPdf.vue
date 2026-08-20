<script setup>
// ETAPA 6 (P1-C) — item 1 (ORC-013/DOC-001/DOC-002): documento de
// orçamento. Dados vêm de rpc_dados_pdf_orcamento (backend) — versão
// específica (id da linha), sempre reproduzível mesmo depois de existir
// versão nova (rpc_criar_versao_orcamento nunca edita a versão anterior).
// "PDF" aqui é o navegador imprimindo esta página (Ctrl+P / botão) —
// mecanismo adequado à arquitetura atual (sem dependência nova no
// frontend), conforme permitido pela instrução item 1.
//
// ETAPA UX-PDF-ORCAMENTO-01 — redesign comercial (layout apenas; nenhum
// cálculo, regra de negócio, aprovação, versionamento ou permissão foi
// alterado). Ver docs/testing/UX_PDF_ORCAMENTO_01_REPORT.md.
//
// BUG-PDF-EXPORT-02 — "Imprimir" (window.print(), abre o diálogo do
// navegador) e "Baixar PDF" (gerado direto em JS via gerarPdfOrcamento,
// vetorial, nunca passa pelo mecanismo de impressão do navegador) viraram
// duas ações distintas. O "Baixar PDF" nunca herda URL/data-hora/título de
// aba/numeração que o navegador injeta sozinho, porque não usa esse
// mecanismo — ver docs/testing/BUG_PDF_EXPORT_02_REPORT.md.
//
// ETAPA DOC-OS-FINAL-01 — cabeçalho/bloco cliente-veículo/tabela de
// itens/resumo financeiro/rodapé foram extraídos para
// components/documentos/Doc*.vue, compartilhados com o novo documento final
// da OS (OsDocumentoFinal.vue) — item 37 do pedido ("criar linguagem
// documental comum", não duplicar CSS. Nenhum dado/cálculo/regra mudou
// aqui, é refatoração puramente estrutural.
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import { STATUS_ORCAMENTO } from '../../constants/statusVisual'
import { gerarPdfOrcamento, nomeArquivoOrcamento } from '../../lib/pdfOrcamento.js'
import DocCabecalho from '../../components/documentos/DocCabecalho.vue'
import DocBlocoClienteVeiculo from '../../components/documentos/DocBlocoClienteVeiculo.vue'
import DocTabelaItens from '../../components/documentos/DocTabelaItens.vue'
import DocResumoFinanceiro from '../../components/documentos/DocResumoFinanceiro.vue'
import DocRodape from '../../components/documentos/DocRodape.vue'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const orcamentoId = computed(() => route.params.id)
const d = ref(null)
const carregando = ref(true)
const erro = ref(false)

// item 6 da instrução: "Emissão: 14/08/2026" — sem hora/segundos no PDF
// comercial (o timestamp completo continua preservado em orcamentos.criado_em
// no banco/auditoria; aqui só a apresentação é reduzida a data).
function formatarDataSomente(v) {
  return v ? new Date(v).toLocaleDateString('pt-BR') : '—'
}

async function carregar() {
  carregando.value = true
  erro.value = false
  d.value = null
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
// Achado real durante a verificação de BUG-PDF-EXPORT-02 (2026-08-18):
// bug pré-existente, mesma causa raiz já corrigida em OrdemServicoDetalhe.vue
// — `carregar()` sendo chamado só uma vez no setup nunca reagia a navegar
// de um /orcamentos/:id/pdf pra outro via router.push (Vue Router reusa a
// mesma instância do componente quando o :id muda mas a rota é igual), então
// a tela continuava mostrando os dados do orçamento anterior com a URL já
// apontando pro novo — risco real de baixar/imprimir o PDF errado sob o
// nome do orçamento certo. `watch` reativo ao :id corrige na raiz.
watch(orcamentoId, carregar, { immediate: true })

// BUG-PDF-PRINT-01 — CAUSA REAL: `@click="window.print()"` direto no
// template nunca funcionava no build de produção. O compilador do Vue
// (`<script setup>`, template inline — modo usado só em produção; em dev
// o template roda sem inline, por isso o bug não aparecia ali) só deixa
// passar identificadores de uma whitelist fixa de globais (Math, Date,
// JSON, console, Error, etc. — NÃO inclui `window`/`document`/`location`).
// Qualquer identificador fora dessa lista e fora dos bindings do
// <script setup> é reescrito para `_ctx.<identificador>` — então
// `window.print()` virava `_ctx.window.print()` em produção, e
// `_ctx.window` é `undefined` (o componente nunca expôs isso). Confirmado
// lendo o bundle minificado real (`dist/assets/OrcamentoPdf-*.js`):
// `onClick:d[1]||=e=>u.window.print()` — `u` é o proxy `_ctx`.
// Correção: chamar via função declarada aqui no script (closure JS normal,
// nunca passa pelo compilador de template) — sem await antes, para não
// perder o gesto do usuário (item 3 da instrução).
function imprimir() {
  if (!d.value) return
  try {
    window.print()
  } catch (e) {
    console.error('Falha ao abrir a impressão do orçamento:', e)
    toast.add({
      severity: 'error',
      summary: 'Não foi possível abrir a impressão. Tente novamente.',
      life: 6000,
    })
  }
}

// BUG-PDF-EXPORT-02 — geração vetorial direta (jsPDF), sem depender do
// diálogo de impressão do navegador. `gerarPdfOrcamento` só desenha a
// partir dos mesmos dados já carregados em `d` (nenhuma chamada nova à
// RPC, nenhum recálculo).
const baixandoPdf = ref(false)
async function baixarPdf() {
  if (!d.value) return
  baixandoPdf.value = true
  try {
    const doc = await gerarPdfOrcamento(d.value)
    doc.save(nomeArquivoOrcamento(d.value))
  } catch (e) {
    console.error('Falha ao gerar o PDF do orçamento:', e)
    toast.add({
      severity: 'error',
      summary: 'Não foi possível gerar o PDF. Tente novamente.',
      life: 6000,
    })
  } finally {
    baixandoPdf.value = false
  }
}

// item 8/9/10/11 — PEÇAS x MÃO DE OBRA a partir do discriminador estrutural
// `natureza` (coluna gerada em orcamento_itens: 'peca' | 'servico_cadastrado'
// | 'servico_avulso' — FEATURE-SERVICOS-01), nunca por análise textual da
// descrição. Serviço avulso (sem vínculo ao catálogo) continua pertencendo
// à seção MÃO DE OBRA (item 11).
const itensPecas = computed(() => (d.value?.itens ?? []).filter((i) => i.natureza === 'peca'))
const itensMaoObra = computed(() => (d.value?.itens ?? []).filter((i) => i.natureza !== 'peca'))
const subtotalPecas = computed(() => itensPecas.value.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0))
const subtotalMaoObra = computed(() => itensMaoObra.value.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0))

// DocTabelaItens espera `valor_total` — orcamento_itens expõe
// `valor_total_original` (nome histórico desta RPC); só remapeia o rótulo do
// campo, nenhum valor muda.
function paraTabela(itens) {
  return itens.map((i) => ({ id: i.id, descricao: i.descricao, quantidade: i.quantidade, valor_unitario: i.valor_unitario, valor_total: i.valor_total_original }))
}
const itensPecasTabela = computed(() => paraTabela(itensPecas.value))
const itensMaoObraTabela = computed(() => paraTabela(itensMaoObra.value))

const linhasResumo = computed(() => {
  if (!d.value) return []
  const o = d.value.orcamento
  const linhas = []
  if (itensPecas.value.length) linhas.push({ label: 'Subtotal Peças', valor: subtotalPecas.value })
  if (itensMaoObra.value.length) linhas.push({ label: 'Subtotal Mão de Obra', valor: subtotalMaoObra.value })
  linhas.push({ label: 'Valor bruto', valor: o.valor_bruto, separador: true })
  if (o.desconto_valor > 0) {
    linhas.push({
      label: `Desconto (${o.desconto_percentual}%)`,
      valor: -o.desconto_valor,
      hint: o.desconto_motivo || null,
    })
  }
  linhas.push({ label: 'Valor total', valor: o.valor_liquido, destaque: true })
  return linhas
})

// item 3/27 — status especial "cancelado" ganha faixa própria em vez do tag
// normal. item 2/40 — "Rascunho" nunca aparece no PDF comercial (documento
// não deveria circular externamente nesse estado; quando ocorre visualização
// interna, simplesmente omitimos o rótulo em vez de inventar um substituto).
const cancelado = computed(() => d.value?.orcamento?.status === 'cancelado')
const mostrarTagStatus = computed(() => d.value && !cancelado.value && d.value.orcamento.status !== 'rascunho')
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/orcamentos')" />
      <div class="acoes-topo-direita">
        <Button
          label="Imprimir"
          icon="pi pi-print"
          size="small"
          severity="secondary"
          outlined
          :disabled="carregando || erro || !d"
          @click="imprimir"
        />
        <Button
          label="Baixar PDF"
          icon="pi pi-download"
          size="small"
          class="btn-gradiente"
          :disabled="carregando || erro || !d"
          :loading="baixandoPdf"
          @click="baixarPdf"
        />
      </div>
    </div>

    <div v-if="carregando" class="documento-papel documento-estado">Carregando...</div>
    <div v-else-if="erro" class="documento-papel documento-estado documento-erro">
      Não foi possível carregar este orçamento.
    </div>

    <div v-else-if="d" class="documento-papel">
      <DocCabecalho
        tipo-documento="Orçamento"
        :numero="d.orcamento.numero_legivel"
        :linha-secundaria="`Versão ${d.orcamento.versao}`"
        :mostrar-status="mostrarTagStatus"
        :status-label="STATUS_ORCAMENTO[d.orcamento.status]?.label ?? d.orcamento.status"
        :status-severidade="STATUS_ORCAMENTO[d.orcamento.status]?.severidade"
        :emitido-label="`Emissão: ${formatarDataSomente(d.orcamento.criado_em)}`"
        :faixa-especial="cancelado ? 'ORÇAMENTO CANCELADO' : null"
      />

      <DocBlocoClienteVeiculo :cliente="d.cliente" :veiculo="d.veiculo" />

      <DocTabelaItens
        v-if="itensPecasTabela.length"
        titulo="Peças"
        rotulo-coluna="Item"
        :itens="itensPecasTabela"
        :subtotal="subtotalPecas"
      />
      <DocTabelaItens
        v-if="itensMaoObraTabela.length"
        titulo="Mão de Obra"
        rotulo-coluna="Serviço"
        :itens="itensMaoObraTabela"
        :subtotal="subtotalMaoObra"
      />

      <DocResumoFinanceiro :linhas="linhasResumo" />

      <div class="doc-condicoes">
        <span class="doc-bloco-titulo">Condições comerciais</span>
        <p class="doc-condicoes-linha">Garantia de 90 dias para peças e serviços, conforme regra vigente da oficina.</p>
        <p class="doc-condicoes-linha">Serviços adicionais identificados após o início da execução serão registrados e submetidos à aprovação antes de serem realizados.</p>
      </div>

      <DocRodape
        :nome-empresa="d.empresa?.nome ?? ''"
        :identificador="`${d.orcamento.numero_legivel} • Versão ${d.orcamento.versao}`"
      />
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
.acoes-topo-direita {
  display: flex;
  gap: 8px;
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
  /* BUG-PDF-EXPORT-02 item 4: era 40px 48px — reduzido pra encolher a
     margem em branco ao redor do conteúdo sem apertar a leitura. */
  padding: 32px 40px;
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

.doc-bloco-titulo {
  display: block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  color: var(--brand-verde-escuro);
  margin-bottom: 8px;
  break-after: avoid;
  page-break-after: avoid;
}

.doc-condicoes {
  break-inside: avoid;
  page-break-inside: avoid;
  margin-bottom: 18px;
}
.doc-condicoes-linha {
  margin: 0 0 4px;
  font-size: 12px;
  color: #4b5563;
  line-height: 1.5;
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
}
</style>
