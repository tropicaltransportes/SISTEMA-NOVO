// BUG-PDF-EXPORT-02 — geração direta (vetorial, sem passar pelo diálogo de
// impressão do navegador) do PDF comercial do orçamento. Recebe o mesmo
// objeto `d` que a tela já carregou de rpc_dados_pdf_orcamento (nenhuma
// chamada nova ao backend, nenhum cálculo novo — só formatação/desenho).
import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'
import { STATUS_ORCAMENTO } from '../constants/statusVisual.js'
import logoUrl from '../assets/brand/tropical-logo-horizontal-light.png'

// Hex espelhando os tokens --brand-verde-escuro/--brand-branco-gelo de
// style.css — jsPDF desenha em RGB puro, não lê CSS var() (mesmo padrão já
// usado em constants/statusVisual.js pro mesmo motivo).
const VERDE_ESCURO = [6, 119, 43]
const BRANCO_GELO = [237, 255, 242]
const TEXTO_PRINCIPAL = [31, 36, 48]
const TEXTO_MUTED = [107, 114, 128]
const BORDA = [229, 231, 235]
const VERMELHO = [220, 38, 38]

const MARGEM = 15
const LARGURA_PAGINA = 210
const ALTURA_PAGINA = 297
const LARGURA_UTIL = LARGURA_PAGINA - MARGEM * 2

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

function formatarDataSomente(v) {
  return v ? new Date(v).toLocaleDateString('pt-BR') : '—'
}

// O PNG fonte (tropical-logo-horizontal-light.png) é 5338×1034px — pensado
// pra usos em alta resolução na tela, não pro PDF (aqui o logo ocupa só
// ~10mm de altura). Passado direto pro jsPDF, o `addImage` não conseguiu
// reaproveitar a compressão original do PNG e caiu no fallback de embutir
// bitmap cru (RGB + canal alfa como SMask separado, nenhum dos dois
// comprimido) — um único PDF de teste chegou a 22MB por causa disso
// (achado real, não hipotético, durante a verificação desta tarefa).
// Redesenhar num canvas menor antes de gerar o data URL evita o problema
// pela raiz: a imagem que chega no jsPDF já nasce do tamanho que vai ser
// exibida, então mesmo sem compressão o bitmap cru é pequeno. 300px de
// altura dá margem de sobra de nitidez pra qualquer impressora razoável
// num elemento de ~10mm.
const LOGO_ALTURA_PX = 300

async function carregarLogoBase64() {
  const resp = await fetch(logoUrl)
  const blob = await resp.blob()
  const bitmap = await createImageBitmap(blob)
  const largura = Math.round(bitmap.width * (LOGO_ALTURA_PX / bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = largura
  canvas.height = LOGO_ALTURA_PX
  canvas.getContext('2d').drawImage(bitmap, 0, 0, largura, LOGO_ALTURA_PX)
  return canvas.toDataURL('image/png')
}

function garantirEspaco(doc, y, alturaNecessaria) {
  if (y + alturaNecessaria > ALTURA_PAGINA - MARGEM) {
    doc.addPage()
    return MARGEM
  }
  return y
}

function desenharCabecalho(doc, d, logoBase64) {
  let y = MARGEM
  if (logoBase64) {
    const props = doc.getImageProperties(logoBase64)
    const alturaLogo = 10
    const larguraLogo = alturaLogo * (props.width / props.height)
    // 'MEDIUM' força o jsPDF a comprimir o bitmap embutido — defesa extra
    // além do redimensionamento em carregarLogoBase64 (ver comentário lá).
    doc.addImage(logoBase64, 'PNG', MARGEM, y, larguraLogo, alturaLogo, undefined, 'MEDIUM')
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8)
    doc.setTextColor(...TEXTO_MUTED)
    doc.text('OFICINA MECÂNICA', MARGEM, y + alturaLogo + 4)
  }

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(...TEXTO_PRINCIPAL)
  doc.text('ORÇAMENTO', LARGURA_PAGINA - MARGEM, y + 3, { align: 'right' })
  doc.setFont('courier', 'bold')
  doc.setFontSize(13)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text(d.orcamento.numero_legivel, LARGURA_PAGINA - MARGEM, y + 9, { align: 'right' })
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(...TEXTO_MUTED)
  doc.text(`Versão ${d.orcamento.versao}`, LARGURA_PAGINA - MARGEM, y + 14, { align: 'right' })

  y += 20
  doc.setDrawColor(...BRANCO_GELO)
  doc.setLineWidth(0.6)
  doc.line(MARGEM, y, LARGURA_PAGINA - MARGEM, y)
  y += 6

  const cancelado = d.orcamento.status === 'cancelado'
  if (cancelado) {
    doc.saveGraphicsState()
    doc.setGState(new doc.GState({ opacity: 0.9 }))
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(13)
    doc.setTextColor(...VERMELHO)
    doc.text('ORÇAMENTO CANCELADO', LARGURA_PAGINA - MARGEM - 8, MARGEM + 14, { align: 'right', angle: -20 })
    doc.restoreGraphicsState()
  } else if (d.orcamento.status !== 'rascunho') {
    const info = STATUS_ORCAMENTO[d.orcamento.status]
    if (info) {
      doc.setFillColor(info.cor)
      const larguraChip = doc.getTextWidth(info.label) + 6
      doc.roundedRect(MARGEM, y - 4, larguraChip, 6, 1.5, 1.5, 'F')
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(8)
      doc.setTextColor(255, 255, 255)
      doc.text(info.label, MARGEM + 3, y)
    }
  }
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(...TEXTO_MUTED)
  doc.text(`Emissão: ${formatarDataSomente(d.orcamento.criado_em)}`, LARGURA_PAGINA - MARGEM, y, { align: 'right' })

  return y + 10
}

function desenharBlocoClienteVeiculo(doc, d, y) {
  const colLargura = LARGURA_UTIL / 2 - 5

  function bloco(x, titulo, linhas) {
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8)
    doc.setTextColor(...VERDE_ESCURO)
    doc.text(titulo.toUpperCase(), x, y)
    let ly = y + 5
    linhas.forEach((linha, i) => {
      doc.setFont('helvetica', i === 0 ? 'bold' : 'normal')
      doc.setFontSize(i === 0 ? 10 : 8.5)
      doc.setTextColor(...(i === 0 ? TEXTO_PRINCIPAL : TEXTO_MUTED))
      doc.text(linha, x, ly)
      ly += i === 0 ? 5 : 4.2
    })
    return ly
  }

  const linhasCliente = [d.cliente.nome]
  if (d.cliente.documento) linhasCliente.push(`Documento: ${d.cliente.documento}`)
  if (d.cliente.telefone) linhasCliente.push(`Telefone: ${d.cliente.telefone}`)
  if (d.cliente.email) linhasCliente.push(`E-mail: ${d.cliente.email}`)

  const placaVeiculo = d.veiculo.prefixo ? `${d.veiculo.placa} (${d.veiculo.prefixo})` : d.veiculo.placa
  const linhasVeiculo = [placaVeiculo]
  if (d.veiculo.modelo) {
    linhasVeiculo.push(d.veiculo.ano ? `${d.veiculo.modelo} / ${d.veiculo.ano}` : d.veiculo.modelo)
  }

  const fimCliente = bloco(MARGEM, 'Cliente', linhasCliente)
  const fimVeiculo = bloco(MARGEM + colLargura + 10, 'Veículo', linhasVeiculo)
  return Math.max(fimCliente, fimVeiculo) + 6
}

function desenharTabelaItens(doc, titulo, itens, subtotal, y) {
  if (!itens.length) return y

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text(titulo.toUpperCase(), MARGEM, y)

  autoTable(doc, {
    startY: y + 3,
    margin: { left: MARGEM, right: MARGEM, bottom: 20 },
    head: [[titulo === 'Peças' ? 'Item' : 'Serviço', 'Qtde', 'Valor Unit.', 'Subtotal']],
    body: itens.map((i) => [
      i.descricao,
      String(i.quantidade),
      formatarMoeda(i.valor_unitario),
      formatarMoeda(i.valor_total_original),
    ]),
    foot: [['', '', 'Subtotal', formatarMoeda(subtotal)]],
    showFoot: 'lastPage',
    showHead: 'everyPage',
    theme: 'plain',
    styles: { font: 'helvetica', fontSize: 8.5, textColor: TEXTO_PRINCIPAL, lineColor: BORDA, lineWidth: { bottom: 0.15 } },
    headStyles: { fillColor: BRANCO_GELO, textColor: VERDE_ESCURO, fontStyle: 'bold', fontSize: 7.2 },
    footStyles: { textColor: TEXTO_PRINCIPAL, fontStyle: 'bold', lineWidth: { top: 0.4 }, fillColor: false },
    columnStyles: {
      1: { halign: 'right', cellWidth: 18 },
      2: { halign: 'right', cellWidth: 32 },
      3: { halign: 'right', cellWidth: 32 },
    },
  })

  return doc.lastAutoTable.finalY + 8
}

function desenharResumoFinanceiro(doc, d, subtotalPecas, subtotalMaoObra, temPecas, temMaoObra, y) {
  const larguraResumo = 80
  const x = LARGURA_PAGINA - MARGEM - larguraResumo

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text('RESUMO FINANCEIRO', x, y)
  y += 6

  function linha(label, valor, opts = {}) {
    doc.setFont('helvetica', opts.negrito ? 'bold' : 'normal')
    doc.setFontSize(opts.tamanho ?? 8.5)
    doc.setTextColor(...(opts.cor ?? TEXTO_PRINCIPAL))
    doc.text(label, x, y)
    doc.text(valor, LARGURA_PAGINA - MARGEM, y, { align: 'right' })
    y += opts.espaco ?? 5
  }

  if (temPecas) linha('Subtotal Peças', formatarMoeda(subtotalPecas))
  if (temMaoObra) linha('Subtotal Mão de Obra', formatarMoeda(subtotalMaoObra))

  doc.setDrawColor(...BORDA)
  doc.setLineWidth(0.2)
  doc.line(x, y - 1.5, LARGURA_PAGINA - MARGEM, y - 1.5)
  y += 1
  linha('Valor bruto', formatarMoeda(d.orcamento.valor_bruto))

  if (d.orcamento.desconto_valor > 0) {
    // Achado real durante a verificação (2026-08-18): motivo concatenado
    // direto no mesmo texto do rótulo colidia com o valor à direita quando
    // era longo o bastante (ex. "Desconto (10%) — QA_PDF_004 desconto de
    // fidelidade" sobrepunha "-R$ 100,00"). O motivo agora vai numa linha
    // própria, menor e cinza, com quebra automática — mesmo espírito do
    // `.hint { display: block }` já usado na versão em tela/impressão.
    linha(`Desconto (${d.orcamento.desconto_percentual}%)`, `-${formatarMoeda(d.orcamento.desconto_valor)}`)
    if (d.orcamento.desconto_motivo) {
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7.5)
      doc.setTextColor(...TEXTO_MUTED)
      const linhasMotivo = doc.splitTextToSize(`— ${d.orcamento.desconto_motivo}`, larguraResumo)
      doc.text(linhasMotivo, x, y - 3)
      y += linhasMotivo.length * 3.2
    }
  }

  doc.setDrawColor(...BORDA)
  doc.line(x, y - 1, LARGURA_PAGINA - MARGEM, y - 1)
  y += 4
  linha('VALOR TOTAL', formatarMoeda(d.orcamento.valor_liquido), {
    negrito: true,
    tamanho: 13,
    cor: VERDE_ESCURO,
    espaco: 6,
  })

  return y + 4
}

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

function desenharRodape(doc, d, y) {
  // Nomes vêm de d.empresa.nome (dado real da RPC), mesma quebra em 2 linhas
  // já usada por `linhasEmpresa` em OrcamentoPdf.vue — nunca hardcoded aqui,
  // pra tela/impressão/PDF baixado ficarem consistentes entre si.
  const partesEmpresa = (d.empresa?.nome ?? '').split(' — ')
  const [linha1, linha2] = partesEmpresa.length === 2 ? partesEmpresa : [partesEmpresa[0], null]

  doc.setDrawColor(...BRANCO_GELO)
  doc.setLineWidth(0.4)
  doc.line(MARGEM, y, LARGURA_PAGINA - MARGEM, y)
  y += 6

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(...TEXTO_PRINCIPAL)
  doc.text(linha1, MARGEM, y)
  y += 4.5
  if (linha2) {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(...TEXTO_MUTED)
    doc.text(linha2, MARGEM, y)
    y += 6
  }
  doc.setFontSize(7.5)
  doc.setTextColor(150, 150, 150)
  doc.text('Documento emitido eletronicamente', MARGEM, y)
  y += 4
  doc.text(`${d.orcamento.numero_legivel} • Versão ${d.orcamento.versao}`, MARGEM, y)
}

// Estimativa de altura (mm) de resumo+condições+rodapé pra decidir se cabe
// na página atual ou se precisa quebrar antes de começar a desenhar
// (evita "resumo financeiro quebrado"/"seção começando no fim da página" —
// item 9 do pedido). Valores calibrados pelas mesmas constantes de
// espaçamento usadas nas funções de desenho acima.
function estimarAlturaBlocoFinal(d, temPecas, temMaoObra) {
  let altura = 6 + (temPecas ? 5 : 0) + (temMaoObra ? 5 : 0) + 1 + 5 + 4 + 10
  // +5 da própria linha "Desconto (X%)" e mais até 13 de folga pro motivo
  // (até 2 linhas quebradas) — ver desenharResumoFinanceiro.
  if (d.orcamento.desconto_valor > 0) altura += d.orcamento.desconto_motivo ? 18 : 5
  altura += 5 + 4 + 2 + 2 * 8
  altura += 6 + 4.5 + 6 + 4 + 4
  return altura
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

  let y = desenharCabecalho(doc, d, logoBase64)
  y = desenharBlocoClienteVeiculo(doc, d, y)
  y = desenharTabelaItens(doc, 'Peças', itensPecas, subtotalPecas, y)
  y = desenharTabelaItens(doc, 'Mão de Obra', itensMaoObra, subtotalMaoObra, y)

  const alturaFinal = estimarAlturaBlocoFinal(d, itensPecas.length > 0, itensMaoObra.length > 0)
  y = garantirEspaco(doc, y, alturaFinal)

  y = desenharResumoFinanceiro(doc, d, subtotalPecas, subtotalMaoObra, itensPecas.length > 0, itensMaoObra.length > 0, y)
  y = desenharCondicoesComerciais(doc, y)
  desenharRodape(doc, d, y)

  return doc
}

export function nomeArquivoOrcamento(d) {
  const codigo = `ORC-${String(d.orcamento.id).slice(0, 8)}`
  const bruto = `Orcamento_${codigo}_V${d.orcamento.versao}.pdf`
  return bruto.replace(/[^A-Za-z0-9._-]/g, '_')
}
