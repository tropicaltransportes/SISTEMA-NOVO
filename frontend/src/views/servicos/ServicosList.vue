<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Textarea from 'primevue/textarea'
import Select from 'primevue/select'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import Menu from 'primevue/menu'

const toast = useToast()
const confirm = useConfirm()

const servicos = ref([])
const categorias = ref([])
const checklists = ref([])
const carregando = ref(true)
const erro = ref(false)
const filtro = ref('')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)
const temFiltroAtivo = computed(() => filtro.value.trim() !== '')

const formVazio = () => ({
  id: null,
  codigo: '',
  nome: '',
  categoria_id: null,
  descricao: '',
  preco_referencia: null,
  tempo_estimado_minutos: null,
  garantia_dias: 90,
  checklist_template_id: null,
})
const form = ref(formVazio())

async function carregar() {
  carregando.value = true
  erro.value = false
  const [respServicos, respCategorias, respChecklists] = await Promise.all([
    supabase
      .from('servicos')
      .select('id, codigo, nome, descricao, preco_referencia, tempo_estimado_minutos, garantia_dias, ativo, checklist_template_id, categoria:servico_categorias(id, nome)')
      .order('nome'),
    supabase.from('servico_categorias').select('id, nome').eq('ativo', true).order('nome'),
    supabase.from('checklist_templates').select('id, nome').eq('ativo', true).order('nome'),
  ])

  if (respServicos.error) {
    erro.value = true
    toast.add({ severity: 'error', summary: 'Erro ao carregar serviços', detail: respServicos.error.message, life: 5000 })
  } else {
    servicos.value = respServicos.data
  }
  categorias.value = respCategorias.data ?? []
  checklists.value = respChecklists.data ?? []
  carregando.value = false
}

function formatarMinutos(min) {
  if (!min) return '—'
  const horas = Math.floor(min / 60)
  const resto = min % 60
  if (horas === 0) return `${resto}min`
  if (resto === 0) return `${horas}h`
  return `${horas}h${resto}min`
}

function abrirNovo() {
  editando.value = null
  form.value = formVazio()
  dialogoAberto.value = true
}

function abrirEdicao(servico) {
  editando.value = servico
  form.value = {
    id: servico.id,
    codigo: servico.codigo,
    nome: servico.nome,
    categoria_id: servico.categoria?.id ?? null,
    descricao: servico.descricao,
    preco_referencia: servico.preco_referencia,
    tempo_estimado_minutos: servico.tempo_estimado_minutos,
    garantia_dias: servico.garantia_dias,
    checklist_template_id: servico.checklist_template_id,
  }
  dialogoAberto.value = true
}

async function salvar() {
  if (!form.value.nome?.trim()) {
    toast.add({ severity: 'warn', summary: 'Informe o nome do serviço', life: 4000 })
    return
  }
  if (form.value.preco_referencia === null || form.value.preco_referencia < 0) {
    toast.add({ severity: 'warn', summary: 'Informe um preço de referência válido', life: 4000 })
    return
  }

  salvando.value = true
  const params = {
    p_nome: form.value.nome,
    p_preco_referencia: form.value.preco_referencia,
    p_codigo: form.value.codigo || null,
    p_categoria_id: form.value.categoria_id,
    p_descricao: form.value.descricao || null,
    p_tempo_estimado_minutos: form.value.tempo_estimado_minutos,
    p_garantia_dias: form.value.garantia_dias ?? 90,
    p_checklist_template_id: form.value.checklist_template_id,
  }

  const { error } = editando.value
    ? await supabase.rpc('rpc_atualizar_servico', { p_servico_id: editando.value.id, ...params })
    : await supabase.rpc('rpc_criar_servico', params)

  salvando.value = false

  if (error) {
    const detalhe = error.code === '23505'
      ? 'Já existe um serviço com este código.'
      : error.message
    toast.add({ severity: 'error', summary: 'Erro ao salvar', detail: detalhe, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Serviço salvo', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function confirmarInativacao(servico) {
  confirm.require({
    message: `Inativar o serviço "${servico.nome}"? Ele deixa de aparecer para novos orçamentos, mas o histórico é preservado.`,
    header: 'Confirmar inativação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Inativar',
    rejectLabel: 'Cancelar',
    accept: () => alternarAtivo(servico, 'rpc_inativar_servico', 'Serviço inativado'),
  })
}

function confirmarAtivacao(servico) {
  confirm.require({
    message: `Reativar o serviço "${servico.nome}"? Ele volta a aparecer como opção para novos orçamentos.`,
    header: 'Confirmar ativação',
    icon: 'pi pi-check-circle',
    acceptLabel: 'Ativar',
    rejectLabel: 'Cancelar',
    accept: () => alternarAtivo(servico, 'rpc_ativar_servico', 'Serviço ativado'),
  })
}

async function alternarAtivo(servico, rpc, mensagemSucesso) {
  const { error } = await supabase.rpc(rpc, { p_servico_id: servico.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao alterar status', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: mensagemSucesso, life: 3000 })
  await carregar()
}

// Menu de 3 pontos, mesmo padrão de ClientesList.vue/VeiculosList.vue —
// alterna entre "Inativar"/"Ativar" conforme o status atual do serviço.
const menuAcoes = ref()
const servicoMenuAtual = ref(null)
const itensMenuAcoes = computed(() => {
  if (!servicoMenuAtual.value) return []
  return servicoMenuAtual.value.ativo
    ? [{ label: 'Inativar', icon: 'pi pi-ban', command: () => confirmarInativacao(servicoMenuAtual.value) }]
    : [{ label: 'Ativar', icon: 'pi pi-check-circle', command: () => confirmarAtivacao(servicoMenuAtual.value) }]
})
function abrirMenuAcoes(event, servico) {
  servicoMenuAtual.value = servico
  menuAcoes.value.toggle(event)
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="pagina-cabecalho-linha">
      <div class="pagina-cabecalho">
        <h1 class="pagina-titulo">Serviços</h1>
        <p class="pagina-subtitulo">Gerencie os serviços e valores de referência da oficina.</p>
      </div>
      <Button label="Novo Serviço" icon="pi pi-plus" class="btn-gradiente" @click="abrirNovo" />
    </div>

    <div class="cabecalho">
      <IconField class="busca">
        <InputIcon class="pi pi-search" />
        <InputText v-model="filtro" placeholder="Buscar por código, nome ou categoria" />
      </IconField>
    </div>

    <div class="panel">
      <DataTable
        :value="servicos"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['codigo', 'nome', 'categoria.nome']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        paginatorTemplate="CurrentPageReport FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink"
        currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} serviços"
      >
        <Column field="codigo" header="Código" sortable style="width: 110px">
          <template #body="{ data }"><span class="codigo-destaque">{{ data.codigo }}</span></template>
        </Column>
        <Column field="nome" header="Serviço" sortable />
        <Column header="Categoria">
          <template #body="{ data }">{{ data.categoria?.nome || '—' }}</template>
        </Column>
        <Column field="preco_referencia" header="Preço de referência" sortable>
          <template #body="{ data }">{{ data.preco_referencia?.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</template>
        </Column>
        <Column header="Tempo estimado">
          <template #body="{ data }">{{ formatarMinutos(data.tempo_estimado_minutos) }}</template>
        </Column>
        <Column header="Garantia">
          <template #body="{ data }">{{ data.garantia_dias }} dias</template>
        </Column>
        <Column header="Status">
          <template #body="{ data }">
            <span class="badge-status" :class="data.ativo ? 'badge-ativo' : 'badge-inativo'">
              {{ data.ativo ? 'Ativo' : 'Inativo' }}
            </span>
          </template>
        </Column>
        <Column header="Ações" style="width: 100px">
          <template #body="{ data }">
            <div class="acoes-linha">
              <Button icon="pi pi-pencil" text rounded size="small" aria-label="Editar" @click="abrirEdicao(data)" />
              <Button icon="pi pi-ellipsis-v" text rounded size="small" aria-label="Mais ações" @click="abrirMenuAcoes($event, data)" />
            </div>
          </template>
        </Column>

        <template #empty>
          <div class="estado-vazio-tabela">
            <i class="pi" :class="erro ? 'pi-exclamation-triangle' : 'pi-cog'"></i>
            <p v-if="erro">Não foi possível carregar os serviços.</p>
            <p v-else-if="temFiltroAtivo">Nenhum serviço encontrado para esta busca.</p>
            <p v-else>Nenhum serviço cadastrado.</p>
            <Button v-if="!erro" label="Novo Serviço" icon="pi pi-plus" size="small" @click="abrirNovo" />
          </div>
        </template>
      </DataTable>
    </div>

    <Menu ref="menuAcoes" :model="itensMenuAcoes" :popup="true" />

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Serviço' : 'Novo Serviço'" style="width: 480px">
      <div class="bloco-form">
        <span class="bloco-form-titulo">Identificação</span>
        <div class="form-campo">
          <label>Código (deixe em branco para gerar automaticamente)</label>
          <InputText v-model="form.codigo" placeholder="SV-001" />
        </div>
        <div class="form-campo">
          <label>Nome</label>
          <InputText v-model="form.nome" />
        </div>
        <div class="form-campo">
          <label>Categoria</label>
          <Select
            v-model="form.categoria_id"
            :options="categorias"
            optionLabel="nome"
            optionValue="id"
            filter
            showClear
            placeholder="Selecione a categoria"
          />
        </div>
        <div class="form-campo">
          <label>Descrição</label>
          <Textarea v-model="form.descricao" rows="2" autoResize />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Comercial</span>
        <div class="form-campo">
          <label>Preço de referência</label>
          <InputNumber v-model="form.preco_referencia" mode="currency" currency="BRL" locale="pt-BR" />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Operação</span>
        <div class="form-campo">
          <label>Tempo estimado (minutos)</label>
          <InputNumber v-model="form.tempo_estimado_minutos" :useGrouping="false" placeholder="Ex.: 90" />
        </div>
        <div class="form-campo">
          <label>Checklist associado</label>
          <Select
            v-model="form.checklist_template_id"
            :options="checklists"
            optionLabel="nome"
            optionValue="id"
            filter
            showClear
            placeholder="Sem checklist associado"
          />
        </div>
      </div>

      <div class="bloco-form">
        <span class="bloco-form-titulo">Garantia</span>
        <div class="form-campo">
          <label>Garantia (dias)</label>
          <InputNumber v-model="form.garantia_dias" :useGrouping="false" suffix=" dias" />
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
/* Mesma linguagem visual de ClientesList.vue/VeiculosList.vue (design
   system dark premium da etapa de redesign) — duplicado aqui em vez de
   extraído para folha compartilhada pelo mesmo motivo já registrado em
   VeiculosList.vue (não tocar num arquivo de etapa já entregue). */
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

.codigo-destaque {
  font-family: var(--font-mono);
  font-weight: 600;
  color: var(--text-heading);
  letter-spacing: 0.3px;
}

.badge-status {
  display: inline-flex;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.3px;
}
.badge-ativo {
  background: rgba(74, 222, 128, 0.16);
  color: var(--status-aprovado);
}
.badge-inativo {
  background: rgba(156, 163, 175, 0.16);
  color: var(--status-rascunho);
}

.acoes-linha {
  display: flex;
  align-items: center;
  gap: 2px;
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
