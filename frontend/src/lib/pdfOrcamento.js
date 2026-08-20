// BUG-PDF-EXPORT-02 — geração direta (vetorial, sem passar pelo diálogo de
// impressão do navegador) do PDF comercial do orçamento. Recebe o mesmo
// objeto `d` que a tela já carregou de rpc_dados_pdf_orcamento (nenhuma
// chamada nova ao backend, nenhum cálculo novo — só formatação/desenho).
//
// ETAPA DOC-OS-FINAL-01 — funções de desenho genéricas (cabeçalho, bloco
// cliente/veículo, tabela de itens, resumo financeiro, rodapé) foram
// extraídas para lib/pdfDocumento.js, compartilhadas com o novo
// pdfDocumentoFinalOs.js (item 37 do pedido). Este arquivo só monta os
// dados específicos do orçamento (peças x mão de obra, resumo com
// desconto, condições comerciais) e chama as funções compartilhadas.
import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'
import { STATUS_ORCAMENTO } from '../constants/statusVisual.js'
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
} from './pdfDocumento.js'

function desenharCondicoesComerciais(doc, y) {
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text('CONDIÇÕES COMERCIAIS', MARGEM, y)
  y += 5

  const linhas = [
    'Garantia de 90 dias para peças e serviços, conforme regra vigente da oficina.',
    'Serviços adicionais identificados após o início da execução serão registrados e submetidos à aprovação antes de serem realizados.',
  ]
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...TEXTO_MUTED)
  linhas.forEach((texto) => {
    const quebradas = doc.splitTextToSize(texto, LARGURA_UTIL)
    doc.text(quebradas, MARGEM, y)
    y += quebradas.length * 3.8 + 1
  })
  return y + 2
}

function montarLinhasResumo(d, subtotalPecas, subtotalMaoObra, temPecas, temMaoObra) {
  const linhas = []
  if (temPecas) linhas.push({ label: 'Subtotal Peças', valor: subtotalPecas })
  if (temMaoObra) linhas.push({ label: 'Subtotal Mão de Obra', valor: subtotalMaoObra })
  linhas.push({ label: 'Valor bruto', valor: d.orcamento.valor_bruto, separador: true })
  if (d.orcamento.desconto_valor > 0) {
    linhas.push({
      label: `Desconto (${d.orcamento.desconto_percentual}%)`,
      valor: -d.orcamento.desconto_valor,
      hint: d.orcamento.desconto_motivo || null,
    })
  }
  linhas.push({ label: 'VALOR TOTAL', valor: d.orcamento.valor_liquido, destaque: true })
  return linhas
}

export async function gerarPdfOrcamento(d) {
  const doc = new jsPDF({ unit: 'mm', format: 'a4' })

  let logoBase64 = null
  try {
    logoBase64 = await carregarLogoBase64()
  } catch (e) {
    console.error('Não foi possível carregar a logo pro PDF, seguindo sem logo:', e)
  }

  const itensPecas = (d.itens ?? []).filter((i) => i.natureza === 'peca')
  const itensMaoObra = (d.itens ?? []).filter((i) => i.natureza !== 'peca')
  const subtotalPecas = itensPecas.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0)
  const subtotalMaoObra = itensMaoObra.reduce((s, i) => s + Number(i.valor_total_original ?? 0), 0)
  const paraTabela = (itens) => itens.map((i) => ({ ...i, valor_total: i.valor_total_original }))

  const cancelado = d.orcamento.status === 'cancelado'
  const statusInfo = STATUS_ORCAMENTO[d.orcamento.status]

  let y = desenharCabecalho(doc, {
    tituloTipo: 'ORÇAMENTO',
    numero: d.orcamento.numero_legivel,
    linhaSecundaria: `Versão ${d.orcamento.versao}`,
    faixaEspecial: cancelado ? 'ORÇAMENTO CANCELADO' : null,
    statusChip: !cancelado && d.orcamento.status !== 'rascunho' && statusInfo ? { label: statusInfo.label, cor: statusInfo.cor } : null,
    emitidoLabel: `Emissão: ${d.orcamento.criado_em ? new Date(d.orcamento.criado_em).toLocaleDateString('pt-BR') : '—'}`,
  }, logoBase64)
  y = desenharBlocoClienteVeiculo(doc, d.cliente, d.veiculo, y)
  y = desenharTabelaItens(doc, autoTable, 'Peças', 'Item', paraTabela(itensPecas), subtotalPecas, y)
  y = desenharTabelaItens(doc, autoTable, 'Mão de Obra', 'Serviço', paraTabela(itensMaoObra), subtotalMaoObra, y)

  const linhasResumo = montarLinhasResumo(d, subtotalPecas, subtotalMaoObra, itensPecas.length > 0, itensMaoObra.length > 0)
  const alturaFinal = estimarAlturaResumo(linhasResumo) + ALTURA_BLOCO_TEXTO_SECUNDARIO + ALTURA_RODAPE
  y = garantirEspaco(doc, y, alturaFinal)

  y = desenharResumoFinanceiro(doc, 'Resumo financeiro', linhasResumo, y)
  y = desenharCondicoesComerciais(doc, y)
  desenharRodape(doc, d.empresa?.nome, `${d.orcamento.numero_legivel} • Versão ${d.orcamento.versao}`, y)

  return doc
}

export function nomeArquivoOrcamento(d) {
  const codigo = `ORC-${String(d.orcamento.id).slice(0, 8)}`
  const bruto = `Orcamento_${codigo}_V${d.orcamento.versao}.pdf`
  return bruto.replace(/[^A-Za-z0-9._-]/g, '_')
}
