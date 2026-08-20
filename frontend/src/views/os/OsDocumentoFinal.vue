<script setup>
// ETAPA DOC-OS-FINAL-01 — documento comercial de conclusão da OS: o que foi
// efetivamente executado (peças utilizadas, mão de obra executada), valores
// snapshot, cliente/veículo/executores/garantia, visualizar/imprimir/baixar
// PDF. Não confundir com OsRelatorioEncerramento.vue (relatório INTERNO de
// auditoria — checklist, fotos, IDs técnicos, movimentos de estoque; BR-025)
// — este documento é o equivalente comercial ao PDF de orçamento
// (OrcamentoPdf.vue), reaproveitando os mesmos componentes/lib (item 37).
//
// Dados vêm de rpc_documento_final_os (backend, só leitura/consolidação —
// ver supabase/migrations/20260820190000_p3_doc_os_final01.sql). Mesma
// arquitetura "Imprimir" (window.print() via função no script, nunca
// @click inline — ver BUG-PDF-PRINT-01) / "Baixar PDF" (jsPDF vetorial via
// gerarPdfDocumentoFinalOs) do orçamento.
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import Button from 'primevue/button'
import { STATUS_OS } from '../../constants/statusVisual'
import { gerarPdfDocumentoFinalOs, nomeArquivoDocumentoFinalOs, montarLinhasResumo } from '../../lib/pdfDocumentoFinalOs.js'
import DocCabecalho from '../../components/documentos/DocCabecalho.vue'
import DocBlocoClienteVeiculo from '../../components/documentos/DocBlocoClienteVeiculo.vue'
import DocTabelaItens from '../../components/documentos/DocTabelaItens.vue'
import DocResumoFinanceiro from '../../components/documentos/DocResumoFinanceiro.vue'
import DocRodape from '../../components/documentos/DocRodape.vue'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const osId = computed(() => route.params.id)
const d = ref(null)
const carregando = ref(true)
const erro = ref(false)

function formatarDataSomente(v) {
  return v ? new Date(v).toLocaleDateString('pt-BR') : '—'
}

async function carregar() {
  carregando.value = true
  erro.value = false
  d.value = null
  const { data, error } = await supabase.rpc('rpc_documento_final_os', { p_os_id: osId.value })
  if (error) {
    erro.value = true
    // BUG-OS-DOC-02 item 15: detalhe técnico (ex. erro de schema/RPC do
    // PostgREST) fica só no console — o usuário final nunca vê texto de
    // erro de banco/API, só a mensagem genérica já exibida no corpo da
    // página (documento-erro).
    console.error('Falha ao carregar rpc_documento_final_os:', error)
    toast.add({ severity: 'error', summary: 'Não foi possível carregar o documento desta OS.', life: 6000 })
    carregando.value = false
    return
  }
  d.value = data
  carregando.value = false
}
// Mesmo achado de BUG-PDF-EXPORT-02 no orçamento: watch reativo ao :id evita
// mostrar o documento de uma OS anterior quando se navega de uma
// /os/:id/documento pra outra (Vue Router reusa a instância do componente).
watch(osId, carregar, { immediate: true })

// BUG-PDF-PRINT-01: função nomeada no script, nunca `@click="window.print()"`
// inline no template (não passa pelo compilador de template em produção).
function imprimir() {
  if (!d.value) return
  try {
    window.print()
  } catch (e) {
    console.error('Falha ao abrir a impressão do documento da OS:', e)
    toast.add({ severity: 'error', summary: 'Não foi possível abrir a impressão. Tente novamente.', life: 6000 })
  }
}

const baixandoPdf = ref(false)
async function baixarPdf() {
  if (!d.value) return
  baixandoPdf.value = true
  try {
    const doc = await gerarPdfDocumentoFinalOs(d.value)
    doc.save(nomeArquivoDocumentoFinalOs(d.value))
  } catch (e) {
    console.error('Falha ao gerar o PDF do documento da OS:', e)
    toast.add({ severity: 'error', summary: 'Não foi possível gerar o PDF. Tente novamente.', life: 6000 })
  } finally {
    baixandoPdf.value = false
  }
}

const ehInterna = computed(() => d.value?.os?.tipo === 'interna')
const linhasResumo = computed(() => (d.value ? montarLinhasResumo(d.value) : []))
const statusInfo = computed(() => (d.value ? STATUS_OS[d.value.os.status] : null))

// item 27/28 — texto de dados operacionais compacto (abertura/liberação/
// executores), sem apontamento detalhado (isso fica só no relatório interno).
const linhasOperacionais = computed(() => {
  if (!d.value) return []
  const linhas = [`Abertura: ${formatarDataSomente(d.value.os.data_abertura)}`]
  if (d.value.os.data_liberacao) linhas.push(`Liberação: ${formatarDataSomente(d.value.os.data_liberacao)}`)
  if (d.value.executores?.length) linhas.push(`Executores: ${d.value.executores.join(', ')}`)
  return linhas
})
</script>

<template>
  <div class="pagina-relatorio">
    <div class="acoes-topo no-print">
      <Button icon="pi pi-arrow-left" text @click="router.push('/os/' + osId)" />
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
      <p>Não foi possível carregar o documento desta OS.</p>
      <Button label="Tentar novamente" icon="pi pi-refresh" size="small" outlined @click="carregar" />
    </div>

    <div v-else-if="d" class="documento-papel">
      <DocCabecalho
        tipo-documento="Ordem de Serviço"
        :numero="d.os.numero_legivel"
        :mostrar-status="!!statusInfo"
        :status-label="statusInfo?.label"
        :status-severidade="statusInfo?.severidade"
        :emitido-label="`Conclusão: ${formatarDataSomente(d.os.data_liberacao ?? d.os.data_abertura)}`"
      />

      <DocBlocoClienteVeiculo :cliente="d.cliente" :veiculo="d.veiculo" />

      <div v-if="linhasOperacionais.length" class="doc-operacional">
        <span class="doc-bloco-titulo">Dados do serviço</span>
        <p v-for="(l, idx) in linhasOperacionais" :key="idx" class="doc-operacional-linha">{{ l }}</p>
      </div>

      <DocTabelaItens
        v-if="d.pecas.length"
        titulo="Peças"
        rotulo-coluna="Item"
        :itens="d.pecas"
        :subtotal="d.resumo_financeiro.subtotal_pecas"
      />
      <DocTabelaItens
        v-if="d.mao_de_obra.length"
        titulo="Mão de Obra"
        rotulo-coluna="Serviço"
        :itens="d.mao_de_obra"
        :subtotal="d.resumo_financeiro.subtotal_mao_obra"
      />

      <DocResumoFinanceiro :titulo="ehInterna ? 'Custo interno' : 'Resumo financeiro'" :linhas="linhasResumo" />
      <p v-if="ehInterna" class="doc-aviso-interno">Custo interno consolidado — não representa cobrança (OS de frota própria).</p>

      <div v-if="d.garantia" class="doc-garantia">
        <span class="doc-bloco-titulo">Garantia</span>
        <p class="doc-garantia-linha">
          {{ d.garantia.prazo_dias }} dias a partir da liberação da OS — válida até {{ formatarDataSomente(d.garantia.expira_em) }}.
        </p>
      </div>

      <DocRodape :nome-empresa="d.empresa?.nome ?? ''" :identificador="d.os.numero_legivel" />
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

.documento-papel {
  position: relative;
  background: #ffffff;
  color: #1f2430;
  border-radius: 14px;
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35);
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
.documento-erro p {
  margin: 0 0 14px;
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

.doc-operacional {
  margin-bottom: 18px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.doc-operacional-linha {
  margin: 0 0 3px;
  font-size: 12.5px;
  color: #4b5563;
}

.doc-aviso-interno {
  margin: -10px 0 18px;
  text-align: right;
  font-size: 11px;
  color: #6b7280;
  font-style: italic;
}

.doc-garantia {
  break-inside: avoid;
  page-break-inside: avoid;
  margin-bottom: 18px;
}
.doc-garantia-linha {
  margin: 0;
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
