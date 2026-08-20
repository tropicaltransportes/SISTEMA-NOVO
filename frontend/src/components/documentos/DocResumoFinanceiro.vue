<script setup>
// ETAPA DOC-OS-FINAL-01 — extraído de OrcamentoPdf.vue e generalizado: cada
// documento define suas próprias linhas (rótulo + valor + tipo de destaque),
// em vez de rótulos fixos do orçamento (Valor bruto/Desconto/Valor total) —
// o documento final da OS precisa de mais linhas (peças/mão de
// obra/acréscimos/VALOR FINAL).
//
// linha: { label, valor: number, separador?: boolean, destaque?: boolean, hint?: string }
defineProps({
  titulo: { type: String, default: 'Resumo financeiro' },
  linhas: { type: Array, required: true },
})

function formatarMoeda(v) {
  if (v === null || v === undefined) return '—'
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}
</script>

<template>
  <div class="doc-resumo">
    <span class="doc-bloco-titulo">{{ titulo }}</span>
    <template v-for="(l, idx) in linhas" :key="idx">
      <div
        class="doc-resumo-linha"
        :class="{ 'doc-resumo-separador': l.separador, 'doc-resumo-total': l.destaque }"
      >
        <span>{{ l.label }}<span v-if="l.hint" class="hint"> — {{ l.hint }}</span></span>
        <span>{{ formatarMoeda(l.valor) }}</span>
      </div>
    </template>
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

.doc-resumo {
  margin-left: auto;
  max-width: 340px;
  margin-bottom: 18px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.doc-resumo-linha {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 3px 0;
  font-size: 12.5px;
  color: #374151;
}
.doc-resumo-linha .hint {
  display: block;
  font-size: 11px;
  color: #6b7280;
}
.doc-resumo-separador {
  border-top: 1px solid #e5e7eb;
  margin-top: 4px;
  padding-top: 6px;
}
.doc-resumo-total {
  margin-top: 8px;
  padding: 10px 14px;
  border-radius: 8px;
  background: var(--brand-branco-gelo);
  align-items: baseline;
  font-weight: 700;
  font-size: 20px;
  color: #1f2430;
}
.doc-resumo-total span:first-child {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  color: var(--brand-verde-escuro);
}
.doc-resumo-total span:last-child {
  color: var(--brand-verde-escuro);
}

@media (max-width: 640px) {
  .doc-resumo {
    max-width: none;
  }
}
</style>
