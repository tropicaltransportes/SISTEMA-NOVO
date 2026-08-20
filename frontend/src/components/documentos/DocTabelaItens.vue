<script setup>
// ETAPA DOC-OS-FINAL-01 — extraído de OrcamentoPdf.vue. Tabela genérica de
// itens (Peças / Mão de Obra / Serviços) — rótulo da 1ª coluna e o rótulo do
// subtotal são as únicas coisas que variam entre os documentos.
defineProps({
  titulo: { type: String, required: true }, // 'Peças' | 'Mão de Obra'
  rotuloColuna: { type: String, required: true }, // 'Item' | 'Serviço'
  itens: { type: Array, required: true }, // [{ id?, descricao, quantidade, valor_unitario, valor_total }]
  subtotal: { type: Number, required: true },
})

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
</script>

<template>
  <div v-if="itens.length" class="doc-secao-itens">
    <span class="doc-bloco-titulo">{{ titulo }}</span>
    <table class="tabela-relatorio">
      <thead>
        <tr><th>{{ rotuloColuna }}</th><th>Qtde</th><th>Valor Unit.</th><th>Subtotal</th></tr>
      </thead>
      <tbody>
        <tr v-for="(i, idx) in itens" :key="i.id ?? idx">
          <td>{{ i.descricao }}</td>
          <td>{{ i.quantidade }}</td>
          <td class="valor">{{ formatarMoeda(i.valor_unitario) }}</td>
          <td class="valor">{{ formatarMoeda(i.valor_total) }}</td>
        </tr>
      </tbody>
      <tfoot>
        <tr class="linha-subtotal">
          <td colspan="3">Subtotal {{ titulo }}</td>
          <td class="valor">{{ formatarMoeda(subtotal) }}</td>
        </tr>
      </tfoot>
    </table>
  </div>
</template>

<style scoped>
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

.doc-secao-itens {
  margin-bottom: 18px;
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
  background: var(--brand-branco-gelo);
  color: var(--brand-verde-escuro);
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
  border-top: 1.5px solid rgba(6, 119, 43, 0.25);
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
</style>
