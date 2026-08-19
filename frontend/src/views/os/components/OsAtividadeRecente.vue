<script setup>
import { computed, ref } from 'vue'
import Dialog from 'primevue/dialog'

// OS-UX-02 — substitui a aba "Histórico" por um bloco compacto (3-5 eventos
// mais recentes, item 25 do pedido) + "Ver histórico completo" abrindo a
// mesma timeline de antes num dialog. Mesmo computed `eventosHistorico`
// calculado no pai (auditoria_eventos + arrays já carregados) — nenhum
// fetch novo.
const props = defineProps({
  eventos: { type: Array, default: () => [] },
  podeVerHistorico: Boolean,
})

const recentes = computed(() => props.eventos.slice(0, 5))
const dialogoAberto = ref(false)
</script>

<template>
  <div v-if="podeVerHistorico" class="card">
    <h3>Atividade Recente</h3>
    <div v-if="recentes.length === 0" class="estado-vazio-card">
      <i class="pi pi-history"></i>
      <div>
        <strong>Sem eventos registrados</strong>
        <p>Assim que houver movimentação nesta OS, ela aparecerá aqui.</p>
      </div>
    </div>
    <ul v-else class="timeline">
      <li v-for="(ev, i) in recentes" :key="i" class="timeline-item">
        <div class="timeline-icone"><i :class="ev.icone"></i></div>
        <div class="timeline-corpo">
          <span class="timeline-titulo">{{ ev.titulo }}</span>
          <span v-if="ev.detalhe" class="hint">{{ ev.detalhe }}</span>
          <span class="timeline-data">{{ new Date(ev.data).toLocaleString('pt-BR') }}</span>
        </div>
      </li>
    </ul>
    <button v-if="eventos.length > 5" type="button" class="link-ver-todos" @click="dialogoAberto = true">
      Ver histórico completo ({{ eventos.length }})
    </button>

    <Dialog v-model:visible="dialogoAberto" modal header="Histórico completo" style="width: 560px">
      <ul v-if="eventos.length" class="timeline">
        <li v-for="(ev, i) in eventos" :key="i" class="timeline-item">
          <div class="timeline-icone"><i :class="ev.icone"></i></div>
          <div class="timeline-corpo">
            <span class="timeline-titulo">{{ ev.titulo }}</span>
            <span v-if="ev.detalhe" class="hint">{{ ev.detalhe }}</span>
            <span class="timeline-data">{{ new Date(ev.data).toLocaleString('pt-BR') }}</span>
          </div>
        </li>
      </ul>
    </Dialog>
  </div>
</template>

<style scoped>
.card {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 20px;
  margin-bottom: 14px;
}
.card h3 {
  margin: 0 0 14px;
  font-size: 13.5px;
  font-weight: 700;
  color: var(--text-heading);
}
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
}
.estado-vazio-card {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 16px 4px;
  color: var(--text-faint);
}
.estado-vazio-card i {
  font-size: 22px;
  margin-top: 2px;
}
.estado-vazio-card strong {
  display: block;
  color: var(--text-secondary);
  font-size: 13px;
  margin-bottom: 2px;
}
.estado-vazio-card p {
  margin: 0;
  font-size: 12.5px;
  line-height: 1.4;
}
.timeline {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
}
.timeline-item {
  display: flex;
  gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid var(--border-row);
}
.timeline-item:last-child {
  border-bottom: none;
}
.timeline-icone {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--surface-hover);
  color: var(--accent-text);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  font-size: 12px;
}
.timeline-corpo {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.timeline-titulo {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-body);
}
.timeline-data {
  font-size: 11px;
  color: var(--text-faint);
}
.link-ver-todos {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 12px;
  cursor: pointer;
  padding: 10px 0 0;
}
.link-ver-todos:hover {
  color: var(--text-body);
}
</style>
