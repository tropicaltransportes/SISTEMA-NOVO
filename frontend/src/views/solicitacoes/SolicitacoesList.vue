<script setup>
import { ref, onMounted } from 'vue'
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

const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const solicitacoes = ref([])
const veiculos = ref([])
const carregando = ref(true)
const dialogoAberto = ref(false)
const salvando = ref(false)

const severidadeStatus = {
  aberta: 'info',
  em_analise: 'warn',
  convertida_orcamento: 'success',
  convertida_os: 'success',
  cancelada: 'danger',
}

const formVazio = () => ({ veiculo_id: null, descricao: '' })
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  const [respSolic, respVeiculos] = await Promise.all([
    supabase
      .from('solicitacoes_servico')
      .select('id, descricao, status, criado_em, veiculo:veiculos(id, placa, prefixo, cliente:clientes(id, nome, tipo))')
      .order('criado_em', { ascending: false }),
    supabase.from('veiculos').select('id, placa, prefixo').is('deleted_at', null).order('placa'),
  ])

  if (respSolic.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar solicitações', detail: respSolic.error.message, life: 5000 })
  } else {
    solicitacoes.value = respSolic.data
  }
  veiculos.value = respVeiculos.data ?? []
  carregando.value = false
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
    <div class="cabecalho">
      <h2>Solicitações de Serviço</h2>
      <Button label="Nova Solicitação" icon="pi pi-plus" @click="abrirNova" />
    </div>

    <DataTable :value="solicitacoes" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column header="Veículo">
        <template #body="{ data }">{{ data.veiculo?.placa }} <span v-if="data.veiculo?.prefixo">({{ data.veiculo.prefixo }})</span></template>
      </Column>
      <Column header="Cliente">
        <template #body="{ data }">{{ data.veiculo?.cliente?.nome }}</template>
      </Column>
      <Column field="descricao" header="Descrição" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Ações" style="width: 320px">
        <template #body="{ data }">
          <template v-if="podeGerir() && data.status === 'aberta'">
            <Button label="Em Análise" size="small" text @click="marcarEmAnalise(data)" />
          </template>
          <template v-if="podeGerir() && ['aberta', 'em_analise'].includes(data.status)">
            <Button label="Converter em Orçamento" size="small" severity="success" @click="converterEmOrcamento(data)" />
            <Button icon="pi pi-times" text rounded severity="danger" @click="confirmarCancelamento(data)" />
          </template>
        </template>
      </Column>
    </DataTable>

    <Dialog v-model:visible="dialogoAberto" modal header="Nova Solicitação de Serviço" style="width: 480px">
      <div class="form-campo">
        <label>Veículo</label>
        <Select
          v-model="form.veiculo_id"
          :options="veiculos"
          optionLabel="placa"
          optionValue="id"
          filter
          placeholder="Selecione o veículo"
        />
      </div>
      <div class="form-campo">
        <label>Descrição</label>
        <Textarea v-model="form.descricao" rows="4" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar" :loading="salvando" @click="salvar" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.cabecalho {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  margin-bottom: 0.9rem;
}
.form-campo label {
  font-size: 0.8rem;
  color: #4b5563;
}
</style>
