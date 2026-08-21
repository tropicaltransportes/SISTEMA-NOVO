<script setup>
import { computed, ref } from 'vue'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import Dialog from 'primevue/dialog'

// OS-UX-02 — "Serviços" (itens 13-15 do pedido): renomeia "Itens de Mão de
// Obra do Orçamento" e junta também os itens de mão de obra aprovados de
// adicionais (mesma fonte de dados, só combinada aqui para exibição — nenhum
// fetch novo). Ações (marcar executado / dispensar) continuam chamando as
// duas RPCs originais, sem alterar parâmetros.
const props = defineProps({
  itensMaoDeObra: { type: Array, default: () => [] },
  osAdicionais: { type: Array, default: () => [] },
  podeMarcarExecucao: Boolean,
  osEncerrada: Boolean,
  formatarMoeda: { type: Function, required: true },
  marcarItemExecutado: { type: Function, required: true },
  marcarItemAdicionalExecutado: { type: Function, required: true },
  abrirCancelarItem: { type: Function, required: true },
})

const servicos = computed(() => {
  const doOrcamento = props.itensMaoDeObra.map((i) => ({ ...i, origem: 'orcamento' }))
  const doAdicional = props.osAdicionais.flatMap((a) =>
    (a.os_adicional_itens ?? [])
      .filter((i) => !i.peca_id && i.status_aprovacao === 'aprovado')
      .map((i) => ({ ...i, origem: 'adicional', numeroAdicional: a.numero }))
  )
  return [...doOrcamento, ...doAdicional]
})

function icone(status) {
  if (status === 'executado') return 'pi pi-check-circle servico-icone-ok'
  if (status === 'cancelado') return 'pi pi-times-circle servico-icone-cancelado'
  return 'pi pi-circle servico-icone-pendente'
}

function podeAgir(item) {
  return props.podeMarcarExecucao && !osEncerradaOuFeito(item)
}
function osEncerradaOuFeito(item) {
  return props.osEncerrada || ['executado', 'cancelado'].includes(item.execucao_status)
}

const servicoSelecionado = ref(null)
function abrirDetalhe(item) {
  servicoSelecionado.value = item
}

function executar(item) {
  if (item.origem === 'adicional') props.marcarItemAdicionalExecutado(item)
  else props.marcarItemExecutado(item)
}
function dispensar(item) {
  props.abrirCancelarItem(item, item.origem)
}
</script>

<template>
  <div class="card">
    <h3>Serviços</h3>
    <p v-if="servicos.length === 0" class="hint">Nenhum serviço vinculado a esta OS.</p>
    <ul v-else class="lista-servicos">
      <li v-for="item in servicos" :key="item.origem + '-' + item.id" class="servico-linha" @click="abrirDetalhe(item)">
        <i :class="icone(item.execucao_status)"></i>
        <span class="servico-descricao">
          {{ item.descricao }}
          <Tag v-if="item.origem === 'adicional'" severity="warn" :value="'AD-' + String(item.numeroAdicional).padStart(3, '0')" style="margin-left:0.3rem;font-size:0.6rem" />
        </span>
        <span class="servico-status hint">{{ item.execucao_status === 'executado' ? 'Concluído' : item.execucao_status === 'cancelado' ? 'Removido' : 'Pendente' }}</span>
        <span class="servico-acoes" @click.stop>
          <template v-if="podeAgir(item)">
            <Button icon="pi pi-check" size="small" text aria-label="Marcar executado" @click="executar(item)" />
            <Button icon="pi pi-times" size="small" text severity="danger" aria-label="Remover da OS" @click="dispensar(item)" />
          </template>
        </span>
      </li>
    </ul>

    <Dialog :visible="!!servicoSelecionado" @update:visible="servicoSelecionado = null" modal :header="servicoSelecionado?.descricao" style="width: 440px">
      <div v-if="servicoSelecionado" class="detalhe-servico">
        <p><strong>Quantidade:</strong> {{ servicoSelecionado.quantidade }}</p>
        <p v-if="servicoSelecionado.origem === 'adicional'"><strong>Origem:</strong> Adicional AD-{{ String(servicoSelecionado.numeroAdicional).padStart(3, '0') }}</p>
        <p v-if="servicoSelecionado.valor_total != null"><strong>Valor:</strong> {{ formatarMoeda(servicoSelecionado.valor_total) }}</p>
        <p><strong>Status:</strong> {{ servicoSelecionado.execucao_status ?? 'pendente' }}</p>
        <p v-if="servicoSelecionado.justificativa"><strong>Justificativa:</strong> {{ servicoSelecionado.justificativa }}</p>
        <div v-if="podeAgir(servicoSelecionado)" class="detalhe-acoes">
          <Button label="Marcar executado" size="small" @click="executar(servicoSelecionado); servicoSelecionado = null" />
          <Button label="Remover da OS" size="small" severity="danger" text @click="dispensar(servicoSelecionado); servicoSelecionado = null" />
        </div>
      </div>
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
.lista-servicos {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
}
.servico-linha {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 4px;
  border-bottom: 1px solid var(--border-row, var(--border-panel));
  cursor: pointer;
}
.servico-linha:last-child {
  border-bottom: none;
}
.servico-linha:hover {
  background: var(--surface-hover);
}
.servico-icone-ok {
  color: var(--success);
}
.servico-icone-cancelado {
  color: var(--danger);
}
.servico-icone-pendente {
  color: var(--text-faint);
}
.servico-descricao {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  color: var(--text-body);
}
.servico-status {
  font-size: 11.5px;
}
.servico-acoes {
  display: flex;
  gap: 2px;
}
.detalhe-servico p {
  margin: 0 0 8px;
  font-size: 13px;
  color: var(--text-body);
}
.detalhe-acoes {
  display: flex;
  gap: 8px;
  margin-top: 12px;
}
</style>
