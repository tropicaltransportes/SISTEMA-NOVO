<script setup>
import { computed } from 'vue'
import Tag from 'primevue/tag'

// OS-UX-02 — substitui a barra de etapas grande (nós grandes + linhas) por
// um indicador compacto de fase (item 7 do pedido). Mesmos status reais,
// mesmo indiceEtapaAtual/mostrarBarraEtapas já calculados no pai — aqui só
// muda a apresentação.
const props = defineProps({
  os: { type: Object, required: true },
  etapas: { type: Array, required: true },
  indiceEtapaAtual: { type: Number, required: true },
  mostrarBarraEtapas: { type: Boolean, required: true },
  emAguardandoAprovacao: { type: Boolean, required: true },
})

const faseAtualLabel = computed(() => props.etapas[props.indiceEtapaAtual]?.label ?? '—')
</script>

<template>
  <div v-if="mostrarBarraEtapas" class="fase-compacta">
    <span class="fase-trilha">
      <template v-for="(etapa, i) in etapas" :key="etapa.status">
        <span v-if="i > 0" class="fase-separador">→</span>
        <span class="fase-passo" :class="{ 'fase-passo-atual': i === indiceEtapaAtual, 'fase-passo-feita': i < indiceEtapaAtual }">{{ etapa.label }}</span>
      </template>
    </span>
    <Tag v-if="emAguardandoAprovacao" severity="warn" value="aguardando aprovação" class="fase-selo" />
  </div>
  <div v-else-if="os.status === 'cancelada'" class="badge-terminal badge-cancelada">
    <i class="pi pi-times-circle"></i>
    <span>
      OS cancelada
      <template v-if="os.cancelamento_motivo"> — Motivo: {{ os.cancelamento_motivo }}</template>
      <template v-if="os.cancelado_por_profile?.nome"> · Cancelada por {{ os.cancelado_por_profile.nome }}</template>
      <template v-if="os.cancelado_em"> · {{ new Date(os.cancelado_em).toLocaleString('pt-BR') }}</template>
    </span>
  </div>
  <div v-if="os.deleted_at" class="badge-terminal badge-cancelada">
    <i class="pi pi-trash"></i>
    <span>
      OS excluída
      <template v-if="os.deleted_reason"> — Motivo: {{ os.deleted_reason }}</template>
      <template v-if="os.deleted_by_profile?.nome"> · Excluída por {{ os.deleted_by_profile.nome }}</template>
      <template v-if="os.deleted_at"> · {{ new Date(os.deleted_at).toLocaleString('pt-BR') }}</template>
    </span>
  </div>
</template>

<style scoped>
.fase-compacta {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  padding: 8px 2px 14px;
  font-size: 12.5px;
}
.fase-trilha {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  color: var(--text-faint);
}
.fase-separador {
  color: var(--text-faint);
}
.fase-passo-feita {
  color: var(--text-muted);
}
.fase-passo-atual {
  color: var(--text-heading);
  font-weight: 700;
}
.fase-selo {
  font-size: 0.6rem;
}
.badge-terminal {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  border-radius: var(--card-radius);
  font-weight: 700;
  font-size: 13.5px;
  margin-bottom: 14px;
}
.badge-cancelada {
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger);
}
.badge-cancelada span {
  font-weight: 400;
}
</style>
