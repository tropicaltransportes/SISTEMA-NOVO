<script setup>
// ETAPA DOC-OS-FINAL-01 — extraído de OrcamentoPdf.vue (ETAPA UX-PDF-ORCAMENTO-01
// / BRAND-01) para ser compartilhado entre o PDF de orçamento e o novo
// documento final da OS — mesma identidade visual, sem duplicar CSS (item 37
// do pedido). Puramente apresentacional: recebe já formatado, não calcula nada.
import Tag from 'primevue/tag'
import BrandLogo from '../brand/BrandLogo.vue'

defineProps({
  tipoDocumento: { type: String, required: true }, // 'Orçamento' | 'Ordem de Serviço'
  numero: { type: String, required: true },
  linhaSecundaria: { type: String, default: null }, // ex.: 'Versão 2'
  marcaSetor: { type: String, default: 'Oficina Mecânica' },
  mostrarStatus: { type: Boolean, default: false },
  statusLabel: { type: String, default: null },
  statusSeveridade: { type: String, default: null },
  emitidoLabel: { type: String, default: null },
  faixaEspecial: { type: String, default: null }, // ex.: 'ORÇAMENTO CANCELADO'
})
</script>

<template>
  <div v-if="faixaEspecial" class="faixa-especial">{{ faixaEspecial }}</div>

  <header class="doc-cabecalho">
    <div class="doc-marca">
      <BrandLogo variant="horizontal" surface="light" :size="40" />
      <span class="doc-marca-setor">{{ marcaSetor }}</span>
    </div>
    <div class="doc-numero">
      <span class="doc-titulo-tipo">{{ tipoDocumento }}</span>
      <span class="doc-numero-valor">{{ numero }}</span>
      <span v-if="linhaSecundaria" class="doc-versao">{{ linhaSecundaria }}</span>
    </div>
  </header>

  <div v-if="mostrarStatus || emitidoLabel" class="doc-status-linha">
    <Tag v-if="mostrarStatus && statusLabel" :severity="statusSeveridade" :value="statusLabel" />
    <span v-if="emitidoLabel" class="doc-emitido">{{ emitidoLabel }}</span>
  </div>
</template>

<style scoped>
.faixa-especial {
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
  padding-bottom: 14px;
  border-bottom: 2px solid var(--brand-branco-gelo);
  margin-bottom: 14px;
}
.doc-marca {
  display: flex;
  align-items: center;
  gap: 12px;
}
.doc-marca-setor {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.4px;
  text-transform: uppercase;
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
  color: var(--brand-verde-escuro);
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
  margin-bottom: 18px;
}
.doc-emitido {
  font-size: 12.5px;
  color: #6b7280;
}
</style>
