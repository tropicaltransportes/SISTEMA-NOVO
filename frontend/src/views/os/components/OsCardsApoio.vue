<script setup>
// OS-UX-02 — faixa de "Informações de apoio" (itens 17-23 do pedido):
// resumo + porta de entrada para Checklist/Peças/Fotos/Adicionais, que
// deixam de ser abas fixas e viram dialogs sob demanda. Só exibição de
// contagens já calculadas no pai (resumoOS/checklistProgresso) — nenhum
// fetch novo aqui.
defineProps({
  checklistProgresso: { type: Object, default: () => ({ concluidos: 0, total: 0 }) },
  checklistObrigatoriosPendentes: { type: Number, default: 0 },
  pecasCount: { type: Number, default: 0 },
  pecasValor: { type: String, default: '' },
  pecasAguardandoUtilizacao: { type: Number, default: 0 },
  fotosCount: { type: Number, default: 0 },
  adicionaisIdentificados: { type: Number, default: 0 },
  adicionaisAprovados: { type: Number, default: 0 },
  adicionaisExecutados: { type: Number, default: 0 },
  adicionaisAguardandoDecisao: { type: Number, default: 0 },
})

defineEmits(['abrir-checklist', 'abrir-pecas', 'abrir-fotos', 'abrir-adicionais'])
</script>

<template>
  <div class="cards-apoio">
    <button type="button" class="card-apoio" @click="$emit('abrir-checklist')">
      <span class="card-apoio-titulo">Checklist</span>
      <span class="card-apoio-valor">{{ checklistProgresso.total ? `${checklistProgresso.concluidos} / ${checklistProgresso.total}` : '—' }}</span>
      <span v-if="checklistObrigatoriosPendentes > 0" class="card-apoio-alerta">{{ checklistObrigatoriosPendentes }} obrigatório(s) pendente(s)</span>
      <span class="card-apoio-link">Ver</span>
    </button>
    <button type="button" class="card-apoio" @click="$emit('abrir-pecas')">
      <span class="card-apoio-titulo">Peças</span>
      <span class="card-apoio-valor">{{ pecasCount }} utilizada(s)</span>
      <span v-if="pecasAguardandoUtilizacao > 0" class="card-apoio-alerta">{{ pecasAguardandoUtilizacao }} aguardando utilização</span>
      <span v-else-if="pecasValor" class="hint-secundario">{{ pecasValor }}</span>
      <span class="card-apoio-link">Ver</span>
    </button>
    <button type="button" class="card-apoio" @click="$emit('abrir-fotos')">
      <span class="card-apoio-titulo">Fotos</span>
      <span class="card-apoio-valor">{{ fotosCount }} anexada(s)</span>
      <span class="card-apoio-link">Ver</span>
    </button>
    <button type="button" class="card-apoio" @click="$emit('abrir-adicionais')">
      <span class="card-apoio-titulo">Adicionais</span>
      <span class="card-apoio-valor">{{ adicionaisIdentificados ? `${adicionaisIdentificados} identificado(s)` : 'Nenhum identificado' }}</span>
      <span v-if="adicionaisIdentificados" class="hint-secundario">{{ adicionaisAprovados }} aprovado(s) · {{ adicionaisExecutados }} executado(s)</span>
      <span v-if="adicionaisAguardandoDecisao > 0" class="card-apoio-alerta">{{ adicionaisAguardandoDecisao }} aguardando decisão</span>
      <span class="card-apoio-link">Ver</span>
    </button>
  </div>
</template>

<style scoped>
.cards-apoio {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 14px;
}
.card-apoio {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 3px;
  align-items: flex-start;
  cursor: pointer;
  font-family: inherit;
  text-align: left;
}
.card-apoio:hover {
  background: var(--surface-hover);
}
.card-apoio-titulo {
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  color: var(--text-muted);
}
.card-apoio-valor {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-heading);
}
.card-apoio-alerta {
  font-size: 11px;
  color: var(--warning);
}
.hint-secundario {
  font-size: 11px;
  color: var(--text-faint);
}
.card-apoio-link {
  font-size: 11px;
  color: var(--accent-text, var(--info));
  margin-top: 2px;
}
</style>
