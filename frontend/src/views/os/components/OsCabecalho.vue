<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import Tag from 'primevue/tag'
import Menu from 'primevue/menu'
import { STATUS_OS } from '../../../constants/statusVisual.js'

// OS-UX-02 — cabeçalho compacto (item 3 do pedido): veículo/cliente/status/
// previsão em destaque, UMA zona de ação principal, tudo mais no menu "⋮"
// (item 6). Nenhuma RPC nova aqui — só reorganiza os mesmos gatilhos que já
// existiam no cabeçalho/aba Visão Geral do arquivo original.
const props = defineProps({
  os: { type: Object, required: true },
  osId: { type: [String, Number], required: true },
  podeDefinirPrazo: Boolean,
  osEncerrada: Boolean,
  podeGerarCobranca: Boolean,
  podeAbrirGarantia: Boolean,
  dentroDoPrazoGarantia: Boolean,
  transicoesNaoDanger: { type: Array, default: () => [] },
  itensMenuAcoes: { type: Array, default: () => [] },
  abrirPrazo: { type: Function, required: true },
  confirmarTransicao: { type: Function, required: true },
  concluir: { type: Function, required: true },
  liberar: { type: Function, required: true },
  confirmarAbrirGarantia: { type: Function, required: true },
})

const router = useRouter()

const itensMenuCompleto = computed(() => {
  const lista = []
  if (props.podeGerarCobranca && props.os.status === 'concluida' && props.os.tipo === 'externa') {
    lista.push({
      label: 'Gerar Cobrança',
      icon: 'pi pi-wallet',
      command: () => router.push({ path: '/financeiro/cobrancas', query: { cliente_id: props.os.cliente.id, os_id: props.os.id } }),
    })
  }
  if (props.dentroDoPrazoGarantia && props.podeAbrirGarantia) {
    lista.push({ label: 'Abrir Garantia', icon: 'pi pi-shield', command: () => props.confirmarAbrirGarantia() })
  }
  if (['concluida', 'liberada'].includes(props.os.status)) {
    lista.push({ label: 'Relatório de Encerramento', icon: 'pi pi-file', command: () => router.push('/os/' + props.osId + '/relatorio-encerramento') })
  }
  if (props.os.os_origem_id) {
    lista.push({ label: 'Relatório de Garantia', icon: 'pi pi-shield', command: () => router.push('/os/' + props.osId + '/relatorio-garantia') })
  }
  return [...lista, ...props.itensMenuAcoes]
})

const menuRef = ref()
function abrirMenu(event) {
  menuRef.value.toggle(event)
}
</script>

<template>
  <div class="cabecalho-os">
    <div class="cabecalho-esquerda">
      <div class="cabecalho-titulo-linha">
        <Button icon="pi pi-arrow-left" text @click="router.push('/os')" />
        <h2>OS — {{ os.veiculo?.placa }} <span v-if="os.veiculo?.prefixo">({{ os.veiculo.prefixo }})</span></h2>
        <Tag :severity="STATUS_OS[os.status]?.severidade" :value="STATUS_OS[os.status]?.label ?? os.status" class="status-tag" />
      </div>
      <div class="cabecalho-info-linha">
        <span class="info-item"><span class="info-label">Cliente</span> {{ os.cliente?.nome }}</span>
        <span class="info-item"><span class="info-label">Veículo</span> {{ os.veiculo?.modelo || '—' }}</span>
        <span class="info-item"><span class="info-label">Tipo</span> {{ os.tipo === 'interna' ? 'Interna' : 'Externa' }}</span>
        <span class="info-item"><span class="info-label">Aberta em</span> {{ new Date(os.data_abertura).toLocaleDateString('pt-BR') }}</span>
        <span class="info-item">
          <span class="info-label">Previsão</span>
          {{ os.previsao_conclusao ? new Date(os.previsao_conclusao).toLocaleString('pt-BR') : 'Não definida' }}
          <Button v-if="podeDefinirPrazo && !osEncerrada" icon="pi pi-pencil" size="small" text @click="abrirPrazo" aria-label="Definir/Alterar previsão" class="botao-icone-inline" />
        </span>
      </div>
    </div>

    <div class="cabecalho-direita">
      <div class="acao-principal">
        <Button
          v-for="t in transicoesNaoDanger"
          :key="t.next"
          :label="t.label"
          size="small"
          :class="{ 'btn-gradiente': transicoesNaoDanger.length === 1 }"
          :outlined="transicoesNaoDanger.length > 1"
          @click="confirmarTransicao(t)"
        />
        <Button v-if="os.status === 'aguardando_teste'" label="Concluir serviço" size="small" class="btn-gradiente" @click="concluir" />
        <Button v-if="os.status === 'concluida'" label="Liberar" size="small" class="btn-gradiente" @click="liberar" />
      </div>
      <Button v-if="itensMenuCompleto.length" icon="pi pi-ellipsis-v" text rounded aria-label="Mais ações" @click="abrirMenu($event)" />
      <Menu ref="menuRef" :model="itensMenuCompleto" :popup="true" />
    </div>
  </div>
</template>

<style scoped>
.cabecalho-os {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  flex-wrap: wrap;
  margin-bottom: 10px;
}
.cabecalho-titulo-linha {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
  flex-wrap: wrap;
}
.cabecalho-titulo-linha h2 {
  margin: 0;
  font-size: 1.2rem;
  color: var(--text-heading);
}
.status-tag {
  font-size: 0.72rem;
}
.cabecalho-info-linha {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 22px;
}
.info-item {
  font-size: 12.5px;
  color: var(--text-body);
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.info-label {
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.3px;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-right: 2px;
}
.botao-icone-inline {
  padding: 2px;
  width: 22px;
  height: 22px;
}
.cabecalho-direita {
  display: flex;
  align-items: center;
  gap: 6px;
}
.acao-principal {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  justify-content: flex-end;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}
:deep(.item-menu-destrutivo .p-menu-item-link),
:deep(.item-menu-destrutivo .p-menu-item-icon),
:deep(.item-menu-destrutivo .p-menu-item-label) {
  color: var(--danger);
}

@media (max-width: 760px) {
  .cabecalho-os {
    flex-direction: column;
  }
  .cabecalho-direita {
    width: 100%;
    justify-content: space-between;
  }
  .acao-principal {
    justify-content: flex-start;
  }
}
</style>
