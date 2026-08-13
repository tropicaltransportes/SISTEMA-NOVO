<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import { useConfirm } from 'primevue/useconfirm'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import Menu from 'primevue/menu'

const router = useRouter()
const toast = useToast()
const confirm = useConfirm()

const clientes = ref([])
const carregando = ref(true)
const erro = ref(false)
const filtro = ref('')
const filtroTipo = ref('todos')
const dialogoAberto = ref(false)
const salvando = ref(false)
const editando = ref(null)
const temFiltroAtivo = computed(() => filtro.value.trim() !== '' || filtroTipo.value !== 'todos')

const opcoesTipo = [
  { label: 'Externo', value: 'externo' },
  { label: 'Interno (frota própria)', value: 'interno' },
]

const opcoesFiltroTipo = [
  { label: 'Todos', value: 'todos' },
  { label: 'Internos', value: 'interno' },
  { label: 'Externos', value: 'externo' },
]

const formVazio = () => ({ id: null, tipo: 'externo', nome: '', documento: '', telefone: '', email: '' })
const form = ref(formVazio())

const clientesFiltrados = computed(() => {
  if (filtroTipo.value === 'todos') return clientes.value
  return clientes.value.filter((c) => c.tipo === filtroTipo.value)
})

// ETAPA UX-CLIENTES-01 — variações só de violeta (identidade única de marca),
// no lugar da paleta multicolorida anterior.
const gradientesAvatar = [
  'linear-gradient(135deg,#8b5cf6,#6d28d9)',
  'linear-gradient(135deg,#a78bfa,#7c3aed)',
  'linear-gradient(135deg,#c4b5fd,#8b5cf6)',
  'linear-gradient(135deg,#7c4de8,#5b21b6)',
]
function avatarGradiente(cliente) {
  const chave = cliente.nome ?? cliente.id ?? ''
  const hash = [...chave].reduce((s, c) => s + c.charCodeAt(0), 0)
  return gradientesAvatar[hash % gradientesAvatar.length]
}
function iniciaisCliente(nome) {
  const partes = (nome ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return '?'
  const primeira = partes[0][0]
  const ultima = partes.length > 1 ? partes[partes.length - 1][0] : ''
  return (primeira + ultima).toUpperCase()
}
function contagemVeiculos(cliente) {
  return cliente.veiculos?.[0]?.count ?? 0
}

async function carregar() {
  carregando.value = true
  erro.value = false
  const { data, error } = await supabase
    .from('clientes')
    .select('id, tipo, nome, documento, telefone, email, veiculos(count)')
    .is('deleted_at', null)
    .order('nome')
  if (error) {
    erro.value = true
    toast.add({ severity: 'error', summary: 'Erro ao carregar clientes', detail: error.message, life: 5000 })
  } else {
    clientes.value = data
  }
  carregando.value = false
}

function abrirNovo() {
  editando.value = null
  form.value = formVazio()
  dialogoAberto.value = true
}

function abrirEdicao(cliente) {
  editando.value = cliente
  form.value = { ...cliente }
  dialogoAberto.value = true
}

async function salvar() {
  salvando.value = true
  const payload = {
    tipo: form.value.tipo,
    nome: form.value.nome,
    documento: form.value.documento || null,
    telefone: form.value.telefone || null,
    email: form.value.email || null,
  }
  const query = editando.value
    ? supabase.from('clientes').update(payload).eq('id', editando.value.id)
    : supabase.from('clientes').insert(payload)

  const { error } = await query
  salvando.value = false

  if (error) {
    // CAD-004 (ETAPA 4 P1-A): índice único parcial normaliza CPF/CNPJ e
    // bloqueia duplicidade entre clientes ativos — mensagem amigável em vez
    // do texto cru do Postgres.
    const detalhe = error.code === '23505'
      ? 'Já existe um cliente ativo com este documento (CPF/CNPJ), mesmo com pontuação diferente.'
      : error.message
    toast.add({ severity: 'error', summary: 'Erro ao salvar', detail: detalhe, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Cliente salvo', life: 3000 })
  dialogoAberto.value = false
  await carregar()
}

function confirmarInativacao(cliente) {
  confirm.require({
    message: `Inativar o cliente "${cliente.nome}"? O histórico é preservado.`,
    header: 'Confirmar inativação',
    icon: 'pi pi-exclamation-triangle',
    acceptLabel: 'Inativar',
    rejectLabel: 'Cancelar',
    accept: () => inativar(cliente),
  })
}

async function inativar(cliente) {
  const { error } = await supabase
    .from('clientes')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', cliente.id)
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao inativar', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Cliente inativado', life: 3000 })
  await carregar()
}

// ETAPA UX-CLIENTES-01 — reorganiza visualmente a ação "Inativar" (já
// existente) num menu de três pontos, em vez de um ícone vermelho solto na
// linha; não adiciona nenhuma ação nova.
const menuAcoes = ref()
const clienteMenuAtual = ref(null)
const itensMenuAcoes = computed(() => [
  {
    label: 'Inativar',
    icon: 'pi pi-ban',
    command: () => clienteMenuAtual.value && confirmarInativacao(clienteMenuAtual.value),
  },
])
function abrirMenuAcoes(event, cliente) {
  clienteMenuAtual.value = cliente
  menuAcoes.value.toggle(event)
}

onMounted(carregar)
</script>

<template>
  <div>
    <div class="pagina-cabecalho">
      <h1 class="pagina-titulo">Clientes</h1>
      <p class="pagina-subtitulo">Gerencie clientes internos e externos da oficina.</p>
    </div>

    <div class="cabecalho">
      <div class="pills">
        <button
          v-for="opcao in opcoesFiltroTipo"
          :key="opcao.value"
          type="button"
          class="pill"
          :class="{ 'pill-ativa': filtroTipo === opcao.value }"
          @click="filtroTipo = opcao.value"
        >
          {{ opcao.label }}
        </button>
      </div>

      <IconField class="busca">
        <InputIcon class="pi pi-search" />
        <InputText v-model="filtro" placeholder="Buscar por nome, documento ou e-mail" />
      </IconField>

      <Button label="Novo Cliente" icon="pi pi-plus" class="btn-gradiente" @click="abrirNovo" />
    </div>

    <div class="panel">
      <DataTable
        :value="clientesFiltrados"
        :loading="carregando"
        :filters="{ global: { value: filtro, matchMode: 'contains' } }"
        :globalFilterFields="['nome', 'documento', 'email']"
        paginator
        :rows="15"
        dataKey="id"
        stripedRows
        paginatorTemplate="CurrentPageReport FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink"
        currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} clientes"
        @row-click="(e) => router.push(`/clientes/${e.data.id}`)"
        style="cursor: pointer"
      >
        <Column header="Nome" sortable sortField="nome">
          <template #body="{ data }">
            <div class="linha-nome">
              <span class="avatar-cliente" :style="{ background: avatarGradiente(data) }">{{ iniciaisCliente(data.nome) }}</span>
              <span>{{ data.nome }}</span>
            </div>
          </template>
        </Column>
        <Column field="documento" header="Documento" />
        <Column field="telefone" header="Telefone" />
        <Column field="email" header="E-mail" />
        <Column field="tipo" header="Tipo">
          <template #body="{ data }">
            <span class="badge-tipo" :class="data.tipo === 'interno' ? 'badge-interno' : 'badge-externo'">
              {{ data.tipo === 'interno' ? 'INTERNO' : 'EXTERNO' }}
            </span>
          </template>
        </Column>
        <Column header="Veículos">
          <template #body="{ data }">{{ contagemVeiculos(data) }}</template>
        </Column>
        <Column header="Ações" style="width: 100px">
          <template #body="{ data }">
            <div class="acoes-linha">
              <Button icon="pi pi-pencil" text rounded size="small" aria-label="Editar" @click.stop="abrirEdicao(data)" />
              <Button
                v-if="data.tipo !== 'interno'"
                icon="pi pi-ellipsis-v"
                text
                rounded
                size="small"
                aria-label="Mais ações"
                @click.stop="abrirMenuAcoes($event, data)"
              />
            </div>
          </template>
        </Column>

        <template #empty>
          <div class="estado-vazio-tabela">
            <i class="pi" :class="erro ? 'pi-exclamation-triangle' : 'pi-users'"></i>
            <p v-if="erro">Não foi possível carregar os clientes.</p>
            <p v-else-if="temFiltroAtivo">Nenhum cliente corresponde aos filtros informados.</p>
            <p v-else>Nenhum cliente encontrado.</p>
            <Button v-if="!erro" label="Novo Cliente" icon="pi pi-plus" size="small" @click="abrirNovo" />
          </div>
        </template>
      </DataTable>
    </div>

    <Menu ref="menuAcoes" :model="itensMenuAcoes" :popup="true" />

    <Dialog v-model:visible="dialogoAberto" modal :header="editando ? 'Editar Cliente' : 'Novo Cliente'" style="width: 420px">
      <div class="form-campo">
        <label>Tipo</label>
        <Select v-model="form.tipo" :options="opcoesTipo" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo">
        <label>Nome</label>
        <InputText v-model="form.nome" />
      </div>
      <div class="form-campo">
        <label>Documento (CPF/CNPJ)</label>
        <InputText v-model="form.documento" />
      </div>
      <div class="form-campo">
        <label>Telefone</label>
        <InputText v-model="form.telefone" />
      </div>
      <div class="form-campo">
        <label>E-mail</label>
        <InputText v-model="form.email" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAberto = false" />
        <Button label="Salvar" :loading="salvando" @click="salvar" />
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.pagina-cabecalho {
  margin-bottom: 18px;
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
.pills {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}
.pill {
  padding: 8px 16px;
  border-radius: 999px;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-muted-2);
  background: transparent;
  border: none;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.15s ease, color 0.15s ease;
}
.pill:hover:not(.pill-ativa) {
  background: var(--surface-hover);
  color: var(--text-heading);
}
.pill-ativa {
  color: #fff;
  background: var(--primary);
}
.btn-gradiente {
  margin-left: auto;
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

.linha-nome {
  display: flex;
  align-items: center;
  gap: 10px;
}
.avatar-cliente {
  width: 28px;
  height: 28px;
  border-radius: 999px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.2px;
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
  .cabecalho {
    flex-direction: column;
    align-items: stretch;
  }
  .btn-gradiente {
    margin-left: 0;
  }
  .busca {
    max-width: none;
  }
}
</style>
