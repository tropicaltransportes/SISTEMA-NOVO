// ETAPA DOC-OS-FINAL-01 — funções de desenho jsPDF compartilhadas entre o
// PDF de orçamento (pdfOrcamento.js) e o novo PDF de documento final da OS
// (pdfDocumentoFinalOs.js) — item 37 do pedido ("criar linguagem documental
// comum... não copiar 500 linhas de CSS/lógica de desenho pra OS"). Nenhuma
// lógica nova aqui: código extraído linha a linha de pdfOrcamento.js
// (ETAPA UX-PDF-ORCAMENTO-01 / BUG-PDF-EXPORT-02), só generalizado com
// parâmetros (título do documento, rótulos do resumo) em vez de valores
// fixos do orçamento.
import { STATUS_ORCAMENTO } from '../constants/statusVisual.js'
import logoUrl from '../assets/brand/tropical-logo-horizontal-light.png'

// Hex espelhando os tokens --brand-verde-escuro/--brand-branco-gelo de
// style.css — jsPDF desenha em RGB puro, não lê CSS var() (mesmo padrão já
// usado em constants/statusVisual.js pro mesmo motivo).
export const VERDE_ESCURO = [6, 119, 43]
export const BRANCO_GELO = [237, 255, 242]
export const TEXTO_PRINCIPAL = [31, 36, 48]
export const TEXTO_MUTED = [107, 114, 128]
export const BORDA = [229, 231, 235]
export const VERMELHO = [220, 38, 38]

export const MARGEM = 15
export const LARGURA_PAGINA = 210
export const ALTURA_PAGINA = 297
export const LARGURA_UTIL = LARGURA_PAGINA - MARGEM * 2

export function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

export function formatarDataSomente(v) {
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

export async function carregarLogoBase64() {
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

export function garantirEspaco(doc, y, alturaNecessaria) {
  if (y + alturaNecessaria > ALTURA_PAGINA - MARGEM) {
    doc.addPage()
    return MARGEM
  }
  return y
}

// opts: { tituloTipo, numero, linhaSecundaria, statusChip: {label, cor}|null,
//         faixaEspecial: string|null, emitidoLabel }
export function desenharCabecalho(doc, opts, logoBase64) {
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
  doc.text(opts.tituloTipo, LARGURA_PAGINA - MARGEM, y + 3, { align: 'right' })
  doc.setFont('courier', 'bold')
  doc.setFontSize(13)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text(opts.numero, LARGURA_PAGINA - MARGEM, y + 9, { align: 'right' })
  if (opts.linhaSecundaria) {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    doc.setTextColor(...TEXTO_MUTED)
    doc.text(opts.linhaSecundaria, LARGURA_PAGINA - MARGEM, y + 14, { align: 'right' })
  }

  y += 20
  doc.setDrawColor(...BRANCO_GELO)
  doc.setLineWidth(0.6)
  doc.line(MARGEM, y, LARGURA_PAGINA - MARGEM, y)
  y += 6

  if (opts.faixaEspecial) {
    doc.saveGraphicsState()
    doc.setGState(new doc.GState({ opacity: 0.9 }))
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(13)
    doc.setTextColor(...VERMELHO)
    doc.text(opts.faixaEspecial, LARGURA_PAGINA - MARGEM - 8, MARGEM + 14, { align: 'right', angle: -20 })
    doc.restoreGraphicsState()
  } else if (opts.statusChip) {
    doc.setFillColor(opts.statusChip.cor)
    const larguraChip = doc.getTextWidth(opts.statusChip.label) + 6
    doc.roundedRect(MARGEM, y - 4, larguraChip, 6, 1.5, 1.5, 'F')
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8)
    doc.setTextColor(255, 255, 255)
    doc.text(opts.statusChip.label, MARGEM + 3, y)
  }
  if (opts.emitidoLabel) {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    doc.setTextColor(...TEXTO_MUTED)
    doc.text(opts.emitidoLabel, LARGURA_PAGINA - MARGEM, y, { align: 'right' })
  }

  return y + 10
}

export function desenharBlocoClienteVeiculo(doc, cliente, veiculo, y) {
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

  const linhasCliente = [cliente.nome]
  if (cliente.documento) linhasCliente.push(`Documento: ${cliente.documento}`)
  if (cliente.telefone) linhasCliente.push(`Telefone: ${cliente.telefone}`)
  if (cliente.email) linhasCliente.push(`E-mail: ${cliente.email}`)

  const placaVeiculo = veiculo.prefixo ? `${veiculo.placa} (${veiculo.prefixo})` : veiculo.placa
  const linhasVeiculo = [placaVeiculo]
  if (veiculo.modelo) {
    linhasVeiculo.push(veiculo.ano ? `${veiculo.modelo} / ${veiculo.ano}` : veiculo.modelo)
  }

  const fimCliente = bloco(MARGEM, 'Cliente', linhasCliente)
  const fimVeiculo = bloco(MARGEM + colLargura + 10, 'Veículo', linhasVeiculo)
  return Math.max(fimCliente, fimVeiculo) + 6
}

// itens: [{ descricao, quantidade, valor_unitario, valor_total }]
export function desenharTabelaItens(doc, autoTable, titulo, rotuloColuna, itens, subtotal, y) {
  if (!itens.length) return y

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text(titulo.toUpperCase(), MARGEM, y)

  autoTable(doc, {
    startY: y + 3,
    margin: { left: MARGEM, right: MARGEM, bottom: 20 },
    head: [[rotuloColuna, 'Qtde', 'Valor Unit.', 'Subtotal']],
    body: itens.map((i) => [
      i.descricao,
      String(i.quantidade),
      formatarMoeda(i.valor_unitario),
      formatarMoeda(i.valor_total),
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

// linhas: [{ label, valor, separador?, destaque?, hint? }]
export function desenharResumoFinanceiro(doc, titulo, linhas, y) {
  const larguraResumo = 80
  const x = LARGURA_PAGINA - MARGEM - larguraResumo

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...VERDE_ESCURO)
  doc.text(titulo.toUpperCase(), x, y)
  y += 6

  linhas.forEach((l) => {
    if (l.separador) {
      doc.setDrawColor(...BORDA)
      doc.setLineWidth(0.2)
      doc.line(x, y - 1.5, LARGURA_PAGINA - MARGEM, y - 1.5)
      y += 1
    }

    doc.setFont('helvetica', l.destaque ? 'bold' : 'normal')
    doc.setFontSize(l.destaque ? 13 : 8.5)
    doc.setTextColor(...(l.destaque ? VERDE_ESCURO : TEXTO_PRINCIPAL))
    doc.text(l.label, x, y)
    doc.text(formatarMoeda(l.valor), LARGURA_PAGINA - MARGEM, y, { align: 'right' })
    y += l.destaque ? 6 : 5

    if (l.hint) {
      // Achado real durante a verificação (2026-08-18): motivo concatenado
      // direto no mesmo texto do rótulo colidia com o valor à direita
      // quando era longo o bastante. O motivo vai numa linha própria, menor
      // e cinza, com quebra automática — mesmo espírito do `.hint { display:
      // block }` já usado na versão em tela/impressão.
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7.5)
      doc.setTextColor(...TEXTO_MUTED)
      const linhasHint = doc.splitTextToSize(`— ${l.hint}`, larguraResumo)
      doc.text(linhasHint, x, y - 3)
      y += linhasHint.length * 3.2
    }
  })

  return y + 4
}

export function desenharRodape(doc, nomeEmpresa, identificador, y) {
  // Nomes vêm do dado real (d.empresa.nome), mesma quebra em 2 linhas já
  // usada por `linhasEmpresa` em Doc*.vue — nunca hardcoded aqui, pra
  // tela/impressão/PDF baixado ficarem consistentes entre si.
  const partesEmpresa = (nomeEmpresa ?? '').split(' — ')
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
  doc.text(identificador, MARGEM, y)
}

// Estimativas de altura (mm), usadas por quem chama pra decidir se precisa
// quebrar página ANTES de começar a desenhar o bloco final (evita "resumo
// financeiro quebrado"/"seção começando no fim da página"). Calibradas pelas
// mesmas constantes de espaçamento usadas nas funções de desenho acima —
// não são um cálculo exato, são uma margem de segurança.
export function estimarAlturaResumo(linhas) {
  let altura = 6
  linhas.forEach((l) => {
    altura += l.destaque ? 10 : 5
    if (l.separador) altura += 1
    if (l.hint) altura += 13 // até ~2 linhas quebradas do hint
  })
  return altura
}

// Bloco de texto secundário curto (Condições Comerciais do orçamento /
// Garantia da OS) — 1-2 parágrafos.
export const ALTURA_BLOCO_TEXTO_SECUNDARIO = 25
export const ALTURA_RODAPE = 24.5
