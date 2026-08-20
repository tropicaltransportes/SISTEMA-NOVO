// ETAPA DOC-OS-FINAL-01 — geração direta (vetorial, sem passar pelo diálogo
// de impressão do navegador) do documento comercial de conclusão da OS.
// Recebe o mesmo objeto `d` que a tela já carregou de
// rpc_documento_final_os (nenhuma chamada nova ao backend, nenhum cálculo
// novo — só formatação/desenho). Reaproveita as funções de desenho
// genéricas de lib/pdfDocumento.js, mesmas usadas por pdfOrcamento.js (item
// 37 do pedido — evitar duas arquiteturas diferentes para documentos
// equivalentes).
import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'
import { STATUS_OS } from '../constants/statusVisual.js'
import {
  MARGEM,
  LARGURA_UTIL,
  TEXTO_MUTED,
  VERDE_ESCURO,
  carregarLogoBase64,
  garantirEspaco,
  desenharCabecalho,
  desenharBlocoClienteVeiculo,
  desenharTabelaItens,
  desenharResumoFinanceiro,
  desenharRodape,
  estimarAlturaResumo,
  ALTURA_BLOCO_TEXTO_SECUNDARIO,
  ALTURA_RODAPE,
  formatarDataSomente,
} from './pdfDocumento.js'

// item 22/54 do pedido: cliente interno nunca vê "resumo financeiro"
// comercial (bruto/desconto/acréscimo/valor final) — só o custo consolidado
// já congelado na conclusão (calcular_e_snapshot_custo_interno_os),
// explicitamente rotulado como custo, nunca convertido em valor de venda.
export function montarLinhasResumo(d) {
  if (d.os.tipo === 'interna') {
    const c = d.custo_interno ?? {}
    return [
      { label: 'Custo Peças', valor: c.custo_pecas ?? 0 },
      { label: 'Custo Mão de Obra', valor: c.custo_mao_obra ?? 0 },
      { label: 'CUSTO TOTAL (interno)', valor: c.custo_total ?? 0, destaque: true },
    ]
  }
  const r = d.resumo_financeiro
  const linhas = []
  if (r.subtotal_pecas > 0) linhas.push({ label: 'Subtotal Peças', valor: r.subtotal_pecas })
  if (r.subtotal_mao_obra > 0) linhas.push({ label: 'Subtotal Mão de Obra', valor: r.subtotal_mao_obra })
  linhas.push({ label: 'Valor bruto', valor: r.valor_bruto, separador: true })
  if (r.desconto_valor > 0) linhas.push({ label: 'Desconto', valor: -r.desconto_valor })
  if (r.acrescimos_valor > 0) linhas.push({ label: 'Acréscimos', valor: r.acrescimos_valor })
  linhas.push({ label: 'VALOR FINAL', valor: r.valor_final, destaque: true })
  return linhas
}

function desenharDadosOperacionais(doc, d, y) {
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text('DADOS DO SERVIÇO', MARGEM, y)
  y += 5

  const linhas = [
    `Abertura: ${formatarDataSomente(d.os.data_abertura)}`,
    d.os.data_liberacao ? `Liberação: ${formatarDataSomente(d.os.data_liberacao)}` : null,
    d.executores?.length ? `Executores: ${d.executores.join(', ')}` : null,
  ].filter(Boolean)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...TEXTO_MUTED)
  linhas.forEach((texto) => {
    doc.text(texto, MARGEM, y)
    y += 4.2
  })
  return y + 4
}

// item 26 do pedido: só desenha quando existe base real (OS já liberada) —
// nunca declara prazo genérico sem data de referência real.
function desenharGarantia(doc, d, y) {
  if (!d.garantia) return y
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text('GARANTIA', MARGEM, y)
  y += 5

  const texto = `${d.garantia.prazo_dias} dias a partir da liberação da OS — válida até ${formatarDataSomente(d.garantia.expira_em)}.`
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...TEXTO_MUTED)
  const quebradas = doc.splitTextToSize(texto, LARGURA_UTIL)
  doc.text(quebradas, MARGEM, y)
  return y + quebradas.length * 3.8 + 6
}

export async function gerarPdfDocumentoFinalOs(d) {
  const doc = new jsPDF({ unit: 'mm', format: 'a4' })

  let logoBase64 = null
  try {
    logoBase64 = await carregarLogoBase64()
  } catch (e) {
    console.error('Não foi possível carregar a logo pro PDF, seguindo sem logo:', e)
  }

  const statusInfo = STATUS_OS[d.os.status]

  let y = desenharCabecalho(doc, {
    tituloTipo: 'ORDEM DE SERVIÇO',
    numero: d.os.numero_legivel,
    linhaSecundaria: null,
    faixaEspecial: null,
    statusChip: statusInfo ? { label: statusInfo.label, cor: statusInfo.cor } : null,
    emitidoLabel: `Conclusão: ${formatarDataSomente(d.os.data_liberacao ?? d.os.data_abertura)}`,
  }, logoBase64)
  y = desenharBlocoClienteVeiculo(doc, d.cliente, d.veiculo, y)
  y = desenharDadosOperacionais(doc, d, y)
  // resumo_financeiro.subtotal_pecas/subtotal_mao_obra são sempre calculados
  // pela RPC (interna ou externa) — o que muda por tipo é só o bloco de
  // resumo abaixo (custo interno vs valor final comercial), não a lista de
  // peças/mão de obra em si.
  y = desenharTabelaItens(doc, autoTable, 'Peças', 'Item', d.pecas ?? [], d.resumo_financeiro?.subtotal_pecas ?? 0, y)
  y = desenharTabelaItens(doc, autoTable, 'Mão de Obra', 'Serviço', d.mao_de_obra ?? [], d.resumo_financeiro?.subtotal_mao_obra ?? 0, y)

  const linhasResumo = montarLinhasResumo(d)
  const alturaFinal = estimarAlturaResumo(linhasResumo) + ALTURA_BLOCO_TEXTO_SECUNDARIO + ALTURA_RODAPE
  y = garantirEspaco(doc, y, alturaFinal)

  y = desenharResumoFinanceiro(doc, d.os.tipo === 'interna' ? 'Custo interno' : 'Resumo financeiro', linhasResumo, y)
  y = desenharGarantia(doc, d, y)
  desenharRodape(doc, d.empresa?.nome, d.os.numero_legivel, y)

  return doc
}

export function nomeArquivoDocumentoFinalOs(d) {
  const bruto = `OS_${d.os.numero_legivel}.pdf`
  return bruto.replace(/[^A-Za-z0-9._-]/g, '_')
}
