<script setup>
// ETAPA DOC-OS-FINAL-01 — extraído de OrcamentoPdf.vue. Rodapé institucional
// genérico — nomes vêm sempre de d.empresa.nome (dado real da RPC), nunca
// hardcoded aqui, para tela/impressão/PDF ficarem consistentes entre si.
const props = defineProps({
  nomeEmpresa: { type: String, required: true }, // ex.: 'Tropical Transportes — Oficina Mecânica'
  identificador: { type: String, required: true }, // ex.: 'ORC-XXXXXXXX-V1' ou 'OS-XXXXXXXX'
})

// Quebra "Tropical Transportes — Oficina Mecânica" em 2 linhas só para
// hierarquia visual do letterhead — não altera nem inventa o texto.
import { computed } from 'vue'
const linhasEmpresa = computed(() => {
  const partes = props.nomeEmpresa.split(' — ')
  return partes.length === 2 ? partes : [props.nomeEmpresa]
})
</script>

<template>
  <footer class="doc-rodape">
    <p class="doc-rodape-marca">{{ linhasEmpresa[0] }}</p>
    <p class="doc-rodape-frase" v-if="linhasEmpresa[1]">{{ linhasEmpresa[1] }}</p>
    <p class="doc-rodape-identificacao">Documento emitido eletronicamente</p>
    <p class="doc-rodape-identificacao">{{ identificador }}</p>
  </footer>
</template>

<style scoped>
.doc-rodape {
  border-top: 1px solid var(--brand-branco-gelo);
  padding-top: 14px;
  break-inside: avoid;
  page-break-inside: avoid;
}
.doc-rodape-marca {
  margin: 0;
  font-weight: 600;
  font-size: 13px;
  color: #1f2430;
}
.doc-rodape-frase {
  margin: 2px 0 8px;
  font-size: 12px;
  color: #6b7280;
}
.doc-rodape-identificacao {
  margin: 0 0 2px;
  font-size: 10.5px;
  color: #9ca3af;
}
.doc-rodape-identificacao:last-child {
  margin-bottom: 0;
}
</style>
