<script setup>
import { computed, ref } from 'vue'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputText from 'primevue/inputtext'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'

// OS-UX-02 — bloco "Trabalho Atual" (itens 8-11 do pedido): mostra o
// apontamento ativo do usuário logado com destaque, ou um mini-form pra
// iniciar um novo. A tabela completa de apontamentos (todas as pessoas,
// histórico) continua existindo — só fica atrás de "Ver todos os
// apontamentos" (item 37: accordion em vez de aba fixa). Mesmas duas
// escritas diretas em tabela do arquivo original (insert/update em
// os_executores) — só muda de onde o formulário é preenchido.
const props = defineProps({
  os: { type: Object, required: true },
  executores: { type: Array, required: true },
  meuId: { type: [String, Number], default: null },
  podeApontar: Boolean,
  podeRemoverExecutor: Boolean,
  osEncerrada: Boolean,
  iniciarApontamento: { type: Function, required: true },
  encerrarApontamento: { type: Function, required: true },
  abrirRemoverExecutor: { type: Function, required: true },
})

const ETAPAS = [
  { value: 'diagnostico', label: 'Diagnóstico' },
  { value: 'execucao', label: 'Execução do serviço' },
  { value: 'teste', label: 'Teste / Validação' },
  { value: 'revisao', label: 'Revisão final' },
]

const meuApontamentoAtivo = computed(() =>
  props.executores.find((e) => e.usuario_id === props.meuId && e.ativo !== false && !e.fim) ?? null
)

function etapaLabel(v) {
  return ETAPAS.find((e) => e.value === v)?.label ?? v
}

function tempoDecorrido(inicio) {
  const ms = Date.now() - new Date(inicio).getTime()
  const min = Math.floor(ms / 60000)
  const h = Math.floor(min / 60)
  const m = min % 60
  return h > 0 ? `${h}h${String(m).padStart(2, '0')}` : `${m}min`
}

// Sugestão inteligente de etapa (item 11 do pedido): diagnóstico sugere
// "Diagnóstico"; execução sugere "Execução do serviço" (só troca quando o
// usuário estiver realmente fazendo teste/revisão).
const etapaSugerida = computed(() => {
  if (props.os.status === 'em_diagnostico') return 'diagnostico'
  if (props.os.status === 'em_execucao') return 'execucao'
  return null
})

const formApontamento = ref({ etapa: etapaSugerida.value, observacao: '' })

async function confirmarIniciar() {
  if (!formApontamento.value.etapa) return
  await props.iniciarApontamento({ etapa: formApontamento.value.etapa, observacao: formApontamento.value.observacao })
  formApontamento.value = { etapa: etapaSugerida.value, observacao: '' }
}

const mostrarTodos = ref(false)
const execucoesAtivas = computed(() => props.executores.filter((e) => e.ativo !== false && !e.fim).length)
</script>

<template>
  <div class="card card-destaque">
    <h3>Trabalho Atual</h3>

    <div v-if="meuApontamentoAtivo" class="apontamento-ativo">
      <span class="pulso"></span>
      <div class="apontamento-corpo">
        <strong>{{ etapaLabel(meuApontamentoAtivo.etapa) }}</strong>
        <span class="hint">Iniciado às {{ new Date(meuApontamentoAtivo.inicio).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) }} · {{ tempoDecorrido(meuApontamentoAtivo.inicio) }} decorridos</span>
        <span v-if="meuApontamentoAtivo.observacao" class="hint">{{ meuApontamentoAtivo.observacao }}</span>
      </div>
      <Button label="Finalizar trabalho" class="btn-gradiente" @click="encerrarApontamento(meuApontamentoAtivo)" />
    </div>

    <div v-else-if="podeApontar && !osEncerrada" class="apontamento-form">
      <p class="hint">Nenhuma atividade em andamento.</p>
      <div class="form-linha">
        <Select v-model="formApontamento.etapa" :options="ETAPAS" optionLabel="label" optionValue="value" placeholder="Atividade" />
        <InputText v-model="formApontamento.observacao" placeholder="Observação (opcional)" />
        <Button label="Iniciar trabalho" class="btn-gradiente" @click="confirmarIniciar" :disabled="!formApontamento.etapa" />
      </div>
    </div>
    <p v-else class="hint">Nenhuma atividade em andamento.</p>

    <button type="button" class="link-ver-todos" @click="mostrarTodos = !mostrarTodos">
      {{ mostrarTodos ? 'Ocultar' : 'Ver' }} todos os apontamentos ({{ executores.length }}<template v-if="execucoesAtivas > 0">, {{ execucoesAtivas }} em andamento</template>)
      <i :class="mostrarTodos ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"></i>
    </button>

    <DataTable v-if="mostrarTodos" :value="executores" dataKey="id" size="small" class="tabela-apontamentos">
      <Column header="Executor">
        <template #body="{ data }">
          {{ data.usuario?.nome }}
          <Tag v-if="data.ativo === false" severity="danger" value="removido" style="margin-left:0.3rem;font-size:0.65rem" />
        </template>
      </Column>
      <Column header="Atividade"><template #body="{ data }">{{ etapaLabel(data.etapa) }}</template></Column>
      <Column header="Início"><template #body="{ data }">{{ new Date(data.inicio).toLocaleString('pt-BR') }}</template></Column>
      <Column header="Fim">
        <template #body="{ data }">
          <span v-if="data.fim">{{ new Date(data.fim).toLocaleString('pt-BR') }}</span>
          <Button v-else-if="data.usuario_id === meuId && !osEncerrada" label="Encerrar" size="small" text @click="encerrarApontamento(data)" />
        </template>
      </Column>
      <Column field="observacao" header="Observação" />
      <Column header="">
        <template #body="{ data }">
          <Button v-if="podeRemoverExecutor && data.ativo !== false && !osEncerrada" label="Remover" size="small" text severity="danger" @click="abrirRemoverExecutor(data)" />
        </template>
      </Column>
    </DataTable>
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
.card-destaque {
  border-color: var(--accent-1, var(--border-panel));
}
.apontamento-ativo {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 4px 0;
}
.pulso {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--success);
  flex-shrink: 0;
  box-shadow: 0 0 0 4px var(--success-bg);
}
.apontamento-corpo {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex: 1;
  min-width: 0;
}
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  flex-wrap: wrap;
}
.link-ver-todos {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 12px;
  cursor: pointer;
  padding: 10px 0 0;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.link-ver-todos:hover {
  color: var(--text-body);
}
.tabela-apontamentos {
  margin-top: 10px;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}
@media (max-width: 760px) {
  .form-linha {
    flex-direction: column;
    align-items: stretch;
  }
  .form-linha > * {
    width: 100%;
  }
  .apontamento-ativo {
    flex-direction: column;
    align-items: flex-start;
  }
}
</style>
