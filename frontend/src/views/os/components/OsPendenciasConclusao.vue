<script setup>
import { computed } from 'vue'
import Button from 'primevue/button'

// OS-UX-02 — "Pendências para Conclusão" (itens 27-28 do pedido): só
// aparece com status='aguardando_teste'. Puramente informativo, derivado de
// dados já carregados no pai — quem decide de verdade se pode concluir
// continua sendo a RPC rpc_concluir_os (chamada via prop `concluir`, que a
// partir da ETAPA OS-ESCOPO-04 é `solicitarConclusao` no pai — mostra um
// resumo antes de concluir quando há item não utilizado, mas nunca esconde
// o botão por causa disso); esta lista nunca bloqueia o botão sozinha, só
// orienta visualmente.
//
// ETAPA OS-ESCOPO-04 (seção 21/22 do pedido): "peça aprovada não utilizada"
// e "serviço aprovado não executado" DEIXARAM de ser bloqueio — a RPC não
// barra mais por isso. Por isso essas duas viraram pendências INFORMATIVAS
// (nunca entram no cálculo de `tudoOk`/exibição do botão) — só as pendências
// REAIS (checklist, fotos, adicional aguardando decisão do cliente,
// apontamento aberto) continuam controlando se o botão aparece.
const props = defineProps({
  checklistItens: { type: Array, default: () => [] },
  respostas: { type: Array, default: () => [] },
  itensMaoDeObra: { type: Array, default: () => [] },
  osAdicionais: { type: Array, default: () => [] },
  osFotos: { type: Array, default: () => [] },
  checklistTemplateAtual: { type: Object, default: null },
  executores: { type: Array, default: () => [] },
  itensParaBaixa: { type: Array, default: () => [] },
  podeTransicionar: Boolean,
  concluir: { type: Function, required: true },
})

const checklistFaltando = computed(() =>
  props.checklistItens.filter((i) => i.obrigatorio && !props.respostas.find((r) => r.template_item_id === i.id)?.ok).length
)
const checklistOk = computed(() => checklistFaltando.value === 0)

const servicosPendentes = computed(() => {
  const doOrcamento = props.itensMaoDeObra.filter((i) => !['executado', 'cancelado'].includes(i.execucao_status)).length
  const doAdicional = props.osAdicionais
    .flatMap((a) => a.os_adicional_itens ?? [])
    .filter((i) => !i.peca_id && i.status_aprovacao === 'aprovado' && !['executado', 'cancelado'].includes(i.execucao_status)).length
  return doOrcamento + doAdicional
})

const fotosFaltando = computed(() => {
  if (!props.checklistTemplateAtual) return []
  const temAntes = props.osFotos.some((f) => f.tipo === 'antes')
  const temDepois = props.osFotos.some((f) => f.tipo === 'depois')
  const faltando = []
  if (props.checklistTemplateAtual.foto_antes_obrigatoria && !temAntes) faltando.push('antes')
  if (props.checklistTemplateAtual.foto_depois_obrigatoria && !temDepois) faltando.push('depois')
  return faltando
})
const fotosOk = computed(() => fotosFaltando.value.length === 0)

const adicionaisPendentes = computed(() => props.osAdicionais.filter((a) => a.status === 'aguardando_aprovacao').length)
const apontamentosAbertos = computed(() => props.executores.filter((e) => e.ativo !== false && !e.fim).length)

// ETAPA OS-FLOW-03 (item 24 do pedido) — distinguir "adicional aguardando
// DECISÃO" (linha acima) de "peça já aprovada mas ainda não utilizada".
// itensParaBaixa já vem só com itens aprovados (orçamento/garantia/
// adicional) + `restante` calculado do ledger de estoque — reflete
// exatamente o que rpc_concluir_os já bloqueia hoje (status_aprovacao
// aprovado + execucao_status pendente/parcial), só não aparecia na lista.
const pecasAprovadasPendentes = computed(() => props.itensParaBaixa.filter((i) => i.restante > 0).length)

// Pendências que REALMENTE bloqueiam a conclusão na RPC (rpc_concluir_os).
const pendencias = computed(() => [
  { label: checklistFaltando.value > 0 ? `${checklistFaltando.value} item(ns) obrigatório(s) do checklist pendente(s)` : 'Checklist obrigatório concluído', ok: checklistOk.value },
  { label: fotosFaltando.value.length > 0 ? `Foto obrigatória faltando: ${fotosFaltando.value.join('/')}` : 'Fotos obrigatórias anexadas', ok: fotosOk.value },
  { label: adicionaisPendentes.value > 0 ? `${adicionaisPendentes.value} adicional(is) aguardando aprovação` : 'Sem adicionais aguardando aprovação', ok: adicionaisPendentes.value === 0 },
  { label: apontamentosAbertos.value > 0 ? `${apontamentosAbertos.value} apontamento(s) em aberto` : 'Nenhum apontamento aberto', ok: apontamentosAbertos.value === 0 },
])

// Informativas — nunca bloqueiam o botão (ETAPA OS-ESCOPO-04): aprovado não
// é obrigatoriamente utilizado/executado. Aparecem só para orientar.
const pendenciasInformativas = computed(() => [
  { label: servicosPendentes.value > 0 ? `${servicosPendentes.value} serviço(s) aprovado(s) ainda não executado(s)` : 'Serviços executados', ok: servicosPendentes.value === 0 },
  { label: pecasAprovadasPendentes.value > 0 ? `${pecasAprovadasPendentes.value} peça(s) aprovada(s) ainda não utilizada(s)` : 'Peças aprovadas utilizadas', ok: pecasAprovadasPendentes.value === 0 },
])

const tudoOk = computed(() => pendencias.value.every((p) => p.ok))
</script>

<template>
  <div class="card" :class="{ 'card-pronta': tudoOk }">
    <h3>{{ tudoOk ? 'Pronta para Conclusão' : 'Pendências para Conclusão' }}</h3>
    <ul class="lista-pendencias">
      <li v-for="(p, i) in pendencias" :key="i" :class="{ 'pendencia-ok': p.ok, 'pendencia-falta': !p.ok }">
        <i :class="p.ok ? 'pi pi-check' : 'pi pi-times'"></i>
        <span>{{ p.label }}</span>
      </li>
      <li v-for="(p, i) in pendenciasInformativas" :key="'info-' + i" class="pendencia-informativa">
        <i class="pi pi-info-circle"></i>
        <span>{{ p.label }}</span>
      </li>
    </ul>
    <p v-if="tudoOk && pendenciasInformativas.some((p) => !p.ok)" class="hint-informativo">
      Isso não impede a conclusão — só entra no documento final/cobrança o que foi efetivamente utilizado/executado.
    </p>
    <Button v-if="tudoOk && podeTransicionar" label="Concluir serviço" class="btn-gradiente" @click="concluir" />
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
.card-pronta {
  border-color: var(--success);
}
.lista-pendencias {
  list-style: none;
  padding: 0;
  margin: 0 0 14px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.lista-pendencias li {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
}
.pendencia-ok {
  color: var(--text-body);
}
.pendencia-ok i {
  color: var(--success);
}
.pendencia-falta {
  color: var(--text-heading);
}
.pendencia-falta i {
  color: var(--danger);
}
.pendencia-informativa {
  color: var(--text-muted);
}
.pendencia-informativa i {
  color: var(--text-muted);
}
.hint-informativo {
  color: var(--text-muted);
  font-size: 12px;
  margin: -6px 0 14px;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}
</style>
