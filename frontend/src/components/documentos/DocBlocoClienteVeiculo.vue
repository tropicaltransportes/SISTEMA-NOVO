<script setup>
// ETAPA DOC-OS-FINAL-01 — extraído de OrcamentoPdf.vue. Puramente
// apresentacional: recebe cliente/veiculo já no formato usado pelas RPCs de
// documento (rpc_dados_pdf_orcamento / rpc_documento_final_os).
defineProps({
  cliente: { type: Object, required: true },
  veiculo: { type: Object, required: true },
})
</script>

<template>
  <div class="doc-blocos">
    <div class="doc-bloco">
      <span class="doc-bloco-titulo">Cliente</span>
      <p class="doc-bloco-linha-principal">{{ cliente.nome }}</p>
      <p v-if="cliente.documento" class="doc-bloco-linha">Documento: {{ cliente.documento }}</p>
      <p v-if="cliente.telefone" class="doc-bloco-linha">Telefone: {{ cliente.telefone }}</p>
      <p v-if="cliente.email" class="doc-bloco-linha">E-mail: {{ cliente.email }}</p>
    </div>
    <div class="doc-bloco">
      <span class="doc-bloco-titulo">Veículo</span>
      <p class="doc-bloco-linha-principal">
        {{ veiculo.placa }} <span v-if="veiculo.prefixo">({{ veiculo.prefixo }})</span>
      </p>
      <p v-if="veiculo.modelo" class="doc-bloco-linha">{{ veiculo.modelo }}<span v-if="veiculo.ano"> / {{ veiculo.ano }}</span></p>
    </div>
  </div>
</template>

<style scoped>
.doc-blocos {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  margin-bottom: 20px;
  break-inside: avoid;
  page-break-inside: avoid;
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

@media (max-width: 640px) {
  .doc-blocos {
    grid-template-columns: 1fr;
  }
}
</style>
