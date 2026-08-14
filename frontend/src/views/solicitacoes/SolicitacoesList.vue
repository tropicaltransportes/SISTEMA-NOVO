<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import InputText from 'primevue/inputtext'
import { STATUS_SOLICITACAO } from '../../constants/statusVisual'

const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const solicitacoes = ref([])
const veiculos = ref([])
const carregando = ref(true)
const erro = ref(false)
const filtro = ref('')
const dialogoAberto = ref(false)
const salvando = ref(false)
const temFiltroAtivo = computed(() => filtro.value.trim() !== '')

const formVazio = () => ({ veiculo_id: null, descricao: '' })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  erro.value = false
  const [respSolic, respVeiculos] = await Promise.all([
    supabase
      .from('solicitacoes_servico')
      .select('id, descricao, status, criado_em, veiculo:veiculos(id, placa, prefixo, cliente:clientes(id, nome, tipo))')
      .order('criado_em', { ascending: false }),
    supabase.from('veiculos').select('id, placa, prefixo').is('deleted_at', null).order('placa'),
  ])

  if (respSolic.error) {
    erro.value = true
    toast.add({ severity: 'error', summary: 'Erro ao carregar solicitações', detail: respSolic.error.message, life: 5000 })
  } else {
    solicitacoes.value = respSolic.data
  }
  veiculos.value = respVeiculos.data ?? []
  carregando.value = false
}

function formatarData(dataStr) {
  if (!dataStr) return '—'
  return new Date(dataStr).toLocaleDateString('pt-BR')
}

function abrirNova() {
  form.value = formVazio()
  dialogoAberto.value = true
}

async function salvar() {
  if (!form.value.veiculo_id || !form.value.descricao) {
    toast.add({ severity: 'warn', summary: 'Preencha veículo e descrição', life: 4000 })
    return
  }
  salvando.value = true
  const { error } = await supabase.from('solicitacoes_servico').insert({
    veiculo_id: form.value.veiculo_id,
    descricao: form.value.descricao,
    criado_por: auth.profile.id,
  })
  salvando.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao criar solicitação', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Solicitação criada', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

async function marcarEmAnalise(s) {
  const { error } = await supabase.from('solicitacoes_servico').update({ status: 'em_analise' }).eq('id', s.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao atualizar', detail: error.message, life: 5000 })
    return
  }
  await carregar()
}

function confirmarCancelamento(s) {
  confirm.require({
    message: 'Cancelar esta solicitação?',
    header: 'Confirmar cancelamento',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Cancelar solicitação',
    rejectLabel: 'Voltar',
    accept: async () => {
      const { error } = await supabase.from('solicitacoes_servico').update({ status: 'cancelada' }).eq('id', s.id)
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao cancelar', detail: error.message, life: 5000 })
        return
      }
      await carregar()
    },
  })
}

function converterEmOrcamento(s) {
  router.push({ path: '/orcamentos', query: { solicitacao_id: s.id, veiculo_id: s.veiculo.id, cliente_id: s.veiculo.cliente.id } })
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="pagina-cabecalho-linha">
      <div class="pagina-cabecalho">
        <h1 class="pagina-titulo">Solicitações</h1>
        <p class="pagina-subtitulo">Gerencie as solicitações de serviço registradas no sistema.</p>
      </div>
      <Button label="Nova Solicitação" icon="pi pi-plus" class="btn-gradiente" @click="abrirNova" />
    </div>

    <div class="cabecalho">
      <IconField class="busca">
        <InputIcon class="pi pi-search" />
        <InputText v-model="filtro" placeholder="Buscar por veículo, cliente ou descrição" />
      </IconField>
    </div>

    <div class="panel">
      <DataTable
        :value="solicitacoes"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['veiculo.placa', 'veiculo.prefixo', 'veiculo.cliente.nome', 'descricao']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        paginatorTemplate="CurrentPageReport FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink"
        currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} solicitações"
      >
        <Column header="Veículo">
          <template #body="{ data }">
            <span class="placa-destaque">{{ data.veiculo?.placa || '—' }}</span>
            <span v-if="data.veiculo?.prefixo" class="prefixo-inline">({{ data.veiculo.prefixo }})</span>
          </template>
        </Column>
        <Column header="Cliente">
          <template #body="{ data }">
            <div class="linha-cliente">
              <span>{{ data.veiculo?.cliente?.nome || '—' }}</span>
              <span
                v-if="data.veiculo?.cliente?.tipo"
                class="badge-tipo"
                :class="data.veiculo.cliente.tipo === 'interno' ? 'badge-interno' : 'badge-externo'"
              >
                {{ data.veiculo.cliente.tipo === 'interno' ? 'INTERNO' : 'EXTERNO' }}
              </span>
            </div>
          </template>
        </Column>
        <Column header="Descrição">
          <template #body="{ data }">
            <span class="descricao-truncada" :title="data.descricao">{{ data.descricao }}</span>
          </template>
        </Column>
        <Column header="Criado em" style="width: 110px">
          <template #body="{ data }">{{ formatarData(data.criado_em) }}</template>
        </Column>
        <Column header="Status">
          <template #body="{ data }">
            <Tag :severity="STATUS_SOLICITACAO[data.status]?.severidade" :value="STATUS_SOLICITACAO[data.status]?.label ?? data.status" />
          </template>
        </Column>
        <Column header="Ações" style="width: 320px">
          <template #body="{ data }">
            <div class="acoes-linha">
              <template v-if="podeGerir() && data.status === 'aberta'">
                <Button label="Em Análise" size="small" text @click="marcarEmAnalise(data)" />
              </template>
              <template v-if="podeGerir() && ['aberta', 'em_analise'].includes(data.status)">
                <Button label="Converter em Orçamento" size="small" severity="success" @click="converterEmOrcamento(data)" />
                <Button icon="pi pi-ban" text rounded size="small" severity="danger" aria-label="Cancelar" @click="confirmarCancelamento(data)" />
              </template>
            </div>
          </template>
        </Column>

        <template #empty>
          <div class="estado-vazio-tabela">
            <i class="pi" :class="erro ? 'pi-exclamation-triangle' : 'pi-inbox'"></i>
            <p v-if="erro">Não foi possível carregar as solicitações.</p>
            <p v-else-if="temFiltroAtivo">Nenhuma solicitação encontrada para os critérios informados.</p>
            <p v-else>Nenhuma solicitação registrada.</p>
            <Button v-if="!erro" label="Nova Solicitação" icon="pi pi-plus" size="small" @click="abrirNova" />
          </div>
        </template>
      </DataTable>
    </div>

    <Dialog v-model:visible="dialogoAberto" modal header="Nova Solicitação de Serviço" style="width: 480px">
      <p class="modal-subtitulo">Preencha os dados abaixo para registrar a solicitação.</p>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Veículo</span>
        <div class="form-campo">
          <Select
            v-model="form.veiculo_id"
            :options="veiculos"
            optionLabel="placa"
            optionValue="id"
            filter
            placeholder="Selecione o veículo"
          />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Descrição</span>
        <div class="form-campo">
          <Textarea v-model="form.descricao" rows="4" autoResize placeholder="Descreva o serviço solicitado" />
        </div>
      </div>

      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar" :loading="salvando" @click="salvar" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
/* ETAPA UX-SOLICITACOES-01 — mesma linguagem visual de ClientesList.vue /
   VeiculosList.vue (item 27: telas irmãs). Duplicado por não tocar em
   arquivos de etapas já entregues (ver MELHORIAS FUTURAS no relatório). */
.pagina-cabecalho-linha {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 14px;
  margin-bottom: 18px;
  flex-wrap: wrap;
}
.pagina-cabecalho {
  min-width: 0;
}
.pagina-titulo {
  margin: 0 0 4px;
  font-size: 24px;
  font-weight: 800;
  letter-spacing: -0.4px;
  color: var(--text-heading);
}
.pagina-subtitulo {
  margin: 0;
  font-size: 13.5px;
  color: var(--text-secondary);
}

.cabecalho {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.btn-gradiente :deep(.p-button) {
  background: var(--accent-gradient);
  border: none;
}

.busca {
  flex: 1;
  min-width: 220px;
  max-width: 420px;
}
.busca :deep(.p-inputtext) {
  width: 100%;
  height: 40px;
  background: var(--surface);
  border-color: var(--border-panel);
  color: var(--text-body);
}
.busca :deep(.p-inputtext::placeholder) {
  color: var(--text-faint);
}
.busca :deep(.p-inputtext:enabled:focus) {
  border-color: var(--primary);
  box-shadow: 0 0 0 1px var(--primary);
}
.busca :deep(.p-inputicon) {
  color: var(--text-faint);
}

.panel {
  background: var(--surface);
  border: 1px solid var(--border-panel);
  border-radius: var(--card-radius);
  padding: 6px 4px;
  overflow-x: auto;
}

.placa-destaque {
  font-family: var(--font-mono);
  font-weight: 600;
  color: var(--text-heading);
  letter-spacing: 0.3px;
}
.prefixo-inline {
  margin-left: 6px;
  color: var(--text-muted);
  font-size: 12px;
}

.linha-cliente {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.badge-tipo {
  display: inline-flex;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.3px;
}
.badge-interno {
  background: var(--info-bg);
  color: var(--info);
}
.badge-externo {
  background: var(--accent-soft-bg);
  color: var(--accent-text);
}

.descricao-truncada {
  display: inline-block;
  max-width: 320px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: bottom;
}

.acoes-linha {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.estado-vazio-tabela {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 48px 20px;
  color: var(--text-faint);
}
.estado-vazio-tabela i {
  font-size: 26px;
}
.estado-vazio-tabela p {
  margin: 0;
  font-size: 13.5px;
}

.modal-subtitulo {
  margin: -8px 0 18px;
  font-size: 13px;
  color: var(--text-secondary);
}
.bloco-form {
  margin-bottom: 16px;
}
.bloco-form-titulo {
  display: block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.4px;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-bottom: 8px;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  margin-bottom: 0.9rem;
}
.form-campo label {
  font-size: 0.8rem;
  color: var(--text-muted);
}

@media (max-width: 720px) {
  .pagina-cabecalho-linha {
    flex-direction: column;
    align-items: stretch;
  }
  .busca {
    max-width: none;
  }
}
</style>
