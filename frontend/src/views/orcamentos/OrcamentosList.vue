<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../lib/supabaseClient'
import { useAuthStore } from '../../stores/auth'
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
import Tag from 'primevue/tag'

const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()
const auth = useAuthStore()

const podeGerir = () => ['encarregado', 'administrador_tecnico'].includes(auth.perfil)
const podeAutorizar = () => ['encarregado', 'suporte_administrativo', 'administrador_tecnico'].includes(auth.perfil)

const orcamentos = ref([])
const veiculos = ref([])
const pecas = ref([])
const carregando = ref(true)

const severidadeStatus = {
  rascunho: 'secondary',
  enviado: 'warn',
  aprovado: 'success',
  rejeitado: 'danger',
  substituido: 'contrast',
}

function formatarMoeda(valor) {
  return (valor ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

async function carregar() {
  carregando.value = true
  const [respOrc, respVeiculos, respPecas] = await Promise.all([
    supabase
      .from('orcamentos')
      .select(
        'id, versao, status, valor_total, autorizado_por_nome, comprovante_path, criado_em, solicitacao_id, veiculo:veiculos(id, placa, cliente_id), cliente:clientes(id, nome, tipo), orcamento_itens(id, peca_id, descricao, quantidade, valor_unitario), orcamento_acrescimos(id, valor_acrescimo, justificativa, criado_em)'
      )
      .order('criado_em', { ascending: false }),
    supabase.from('veiculos').select('id, placa, prefixo, cliente_id, cliente:clientes(nome, tipo)').is('deleted_at', null).order('placa'),
    supabase.from('pecas').select('id, sku, descricao').is('deleted_at', null).order('descricao'),
  ])

  if (respOrc.error) {
    toast.add({ severity: 'error', summary: 'Erro ao carregar orçamentos', detail: respOrc.error.message, life: 5000 })
  } else {
    orcamentos.value = respOrc.data
  }
  veiculos.value = respVeiculos.data ?? []
  pecas.value = respPecas.data ?? []
  carregando.value = false
}

// ---------- Criação (rascunho) ----------
const dialogoNovoAberto = ref(false)
const salvandoNovo = ref(false)
const formNovo = ref({ veiculo_id: null, solicitacao_id: null })
// ORC-016: chave de idempotência gerada uma única vez por abertura do
// formulário e reaproveitada em qualquer retry (clique duplo ou retry de
// rede) — protegida de verdade pelo índice único parcial
// ux_orcamentos_client_request_id no backend (não depende só do botão
// desabilitado, que não segura um retry de rede real). Só é trocada quando
// o diálogo é reaberto do zero (abrirNovo) ou depois de sucesso.
let clientRequestId = crypto.randomUUID()

function abrirNovo() {
  formNovo.value = {
    veiculo_id: route.query.veiculo_id || null,
    solicitacao_id: route.query.solicitacao_id || null,
  }
  clientRequestId = crypto.randomUUID()
  dialogoNovoAberto.value = true
}

async function criarRascunho() {
  if (!formNovo.value.veiculo_id) {
    toast.add({ severity: 'warn', summary: 'Selecione o veículo', life: 4000 })
    return
  }
  if (salvandoNovo.value) return // trava extra de UI contra duplo clique; a garantia real é o backend
  const veiculo = veiculos.value.find((v) => v.id === formNovo.value.veiculo_id)
  salvandoNovo.value = true
  const { data, error } = await supabase
    .from('orcamentos')
    .insert({
      veiculo_id: veiculo.id,
      cliente_id: veiculo.cliente_id,
      solicitacao_id: formNovo.value.solicitacao_id || null,
      criado_por: auth.profile.id,
      client_request_id: clientRequestId,
    })
    .select('id')
    .single()
  salvandoNovo.value = false
  if (error) {
    if (error.code === '23505') {
      // Retry/duplo clique real: a 1ª tentativa (desta ou de outra aba/requisição
      // concorrente) já criou o orçamento com esta chave — busca o registro
      // existente em vez de mostrar erro ou deixar o usuário tentar de novo.
      const { data: existente } = await supabase
        .from('orcamentos')
        .select('id')
        .eq('client_request_id', clientRequestId)
        .single()
      if (existente) {
        toast.add({ severity: 'info', summary: 'Orçamento já criado', detail: 'Esta submissão já havia sido processada.', life: 4000 })
        dialogoNovoAberto.value = false
        await carregar()
        abrirItens(orcamentos.value.find((o) => o.id === existente.id))
        return
      }
    }
    toast.add({ severity: 'error', summary: 'Erro ao criar orçamento', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Orçamento criado em rascunho', life: 3000 })
  dialogoNovoAberto.value = false
  clientRequestId = crypto.randomUUID()
  if (route.query.solicitacao_id) router.replace({ path: '/orcamentos' })
  await carregar()
  abrirItens(orcamentos.value.find((o) => o.id === data.id))
}

// ---------- Itens (só em rascunho) ----------
const dialogoItensAberto = ref(false)
const orcamentoAtual = ref(null)
const itens = ref([])
const salvandoItens = ref(false)

function abrirItens(orc) {
  orcamentoAtual.value = orc
  itens.value = orc.orcamento_itens.map((i) => ({ id: i.id, peca_id: i.peca_id, descricao: i.descricao, quantidade: i.quantidade, valor_unitario: i.valor_unitario }))
  dialogoItensAberto.value = true
}

function adicionarItemPeca() {
  itens.value.push({ id: null, peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0 })
}
function adicionarItemMaoDeObra() {
  itens.value.push({ id: null, peca_id: null, descricao: 'Mão de obra', quantidade: 1, valor_unitario: 0 })
}
function removerItem(index) {
  itens.value.splice(index, 1)
}
function selecionouPeca(item) {
  const p = pecas.value.find((x) => x.id === item.peca_id)
  if (p && !item.descricao) item.descricao = p.descricao
}

async function salvarItens() {
  if (itens.value.length === 0 || itens.value.some((i) => !i.descricao || i.quantidade <= 0)) {
    toast.add({ severity: 'warn', summary: 'Revise os itens', detail: 'Cada item precisa de descrição e quantidade maior que zero.', life: 4000 })
    return
  }
  salvandoItens.value = true
  await supabase.from('orcamento_itens').delete().eq('orcamento_id', orcamentoAtual.value.id)
  const payload = itens.value.map((i) => ({
    orcamento_id: orcamentoAtual.value.id,
    peca_id: i.peca_id || null,
    descricao: i.descricao,
    quantidade: i.quantidade,
    valor_unitario: i.valor_unitario,
  }))
  const { error } = await supabase.from('orcamento_itens').insert(payload)
  salvandoItens.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao salvar itens', detail: error.message, life: 5000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Itens salvos', life: 3000 })
  dialogoItensAberto.value = false
  await carregar()
}

// ---------- Transições ----------
async function enviar(orc) {
  const { error } = await supabase.rpc('rpc_enviar_orcamento', { p_orcamento_id: orc.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao enviar', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Orçamento enviado', life: 3000 })
  await carregar()
}

function confirmarAprovacao(orc) {
  confirm.require({
    message: `Aprovar o orçamento (v${orc.versao}) de ${formatarMoeda(orc.valor_total)}?`,
    header: 'Confirmar aprovação',
    icon: 'pi pi-check-circle',
    acceptLabel: 'Aprovar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_aprovar_orcamento', { p_orcamento_id: orc.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao aprovar', detail: error.message, life: 6000 })
        return
      }
      toast.add({ severity: 'success', summary: 'Orçamento aprovado', life: 3000 })
      await carregar()
    },
  })
}

function confirmarRejeicao(orc) {
  confirm.require({
    message: 'Rejeitar este orçamento?',
    header: 'Confirmar rejeição',
    icon: 'pi pi-times-circle',
    acceptLabel: 'Rejeitar',
    rejectLabel: 'Cancelar',
    accept: async () => {
      const { error } = await supabase.rpc('rpc_rejeitar_orcamento', { p_orcamento_id: orc.id })
      if (error) {
        toast.add({ severity: 'error', summary: 'Erro ao rejeitar', detail: error.message, life: 6000 })
        return
      }
      await carregar()
    },
  })
}

async function novaVersao(orc) {
  const { data, error } = await supabase.rpc('rpc_criar_versao_orcamento', { p_orcamento_id: orc.id })
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao criar nova versão', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Nova versão criada em rascunho', life: 3000 })
  await carregar()
  abrirItens(orcamentos.value.find((o) => o.id === data))
}

function criarOs(orc) {
  router.push({
    path: '/os',
    query: { orcamento_id: orc.id, veiculo_id: orc.veiculo.id, cliente_id: orc.cliente.id, solicitacao_id: orc.solicitacao_id || '' },
  })
}

// ---------- Autorização (comprovante, cliente externo) ----------
const dialogoAutorizacaoAberto = ref(false)
const salvandoAutorizacao = ref(false)
const formAutorizacao = ref({ autorizado_por_nome: '', arquivo: null })

function abrirAutorizacao(orc) {
  orcamentoAtual.value = orc
  formAutorizacao.value = { autorizado_por_nome: orc.autorizado_por_nome || '', arquivo: null }
  dialogoAutorizacaoAberto.value = true
}

function onArquivoSelecionado(event) {
  formAutorizacao.value.arquivo = event.target.files[0] || null
}

async function salvarAutorizacao() {
  const orc = orcamentoAtual.value
  const ehExterno = orc.cliente?.tipo === 'externo'
  if (ehExterno && (!formAutorizacao.value.autorizado_por_nome || (!formAutorizacao.value.arquivo && !orc.comprovante_path))) {
    toast.add({ severity: 'warn', summary: 'Cliente externo exige nome do autorizador e comprovante', life: 5000 })
    return
  }
  salvandoAutorizacao.value = true
  let caminho = orc.comprovante_path || null
  if (formAutorizacao.value.arquivo) {
    const arquivo = formAutorizacao.value.arquivo
    const caminhoDestino = `${orc.id}/${Date.now()}-${arquivo.name}`
    const { error: erroUpload } = await supabase.storage.from('comprovantes').upload(caminhoDestino, arquivo)
    if (erroUpload) {
      salvandoAutorizacao.value = false
      toast.add({ severity: 'error', summary: 'Erro ao enviar comprovante', detail: erroUpload.message, life: 6000 })
      return
    }
    caminho = caminhoDestino
  }

  const { error } = await supabase.rpc('rpc_registrar_autorizacao_orcamento', {
    p_orcamento_id: orc.id,
    p_autorizado_por_nome: formAutorizacao.value.autorizado_por_nome || null,
    p_comprovante_path: caminho,
  })
  salvandoAutorizacao.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Erro ao registrar autorização', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Autorização registrada', life: 3000 })
  dialogoAutorizacaoAberto.value = false
  await carregar()
}

// ---------- Acréscimo (pós-aprovação) ----------
const dialogoAcrescimoAberto = ref(false)
const salvandoAcrescimo = ref(false)
const formAcrescimo = ref({ valor_acrescimo: 0, justificativa: '' })

function abrirAcrescimo(orc) {
  orcamentoAtual.value = orc
  formAcrescimo.value = { valor_acrescimo: 0, justificativa: '' }
  dialogoAcrescimoAberto.value = true
}

async function salvarAcrescimo() {
  if (!formAcrescimo.value.valor_acrescimo || !formAcrescimo.value.justificativa) {
    toast.add({ severity: 'warn', summary: 'Informe valor e justificativa', life: 4000 })
    return
  }
  salvandoAcrescimo.value = true
  const { error } = await supabase.rpc('rpc_registrar_acrescimo', {
    p_orcamento_id: orcamentoAtual.value.id,
    p_valor_acrescimo: formAcrescimo.value.valor_acrescimo,
    p_justificativa: formAcrescimo.value.justificativa,
  })
  salvandoAcrescimo.value = false
  if (error) {
    toast.add({ severity: 'error', summary: 'Acréscimo recusado', detail: error.message, life: 8000 })
    return
  }
  toast.add({ severity: 'success', summary: 'Acréscimo registrado', life: 3000 })
  dialogoAcrescimoAberto.value = false
  await carregar()
}

onMounted(() => {
  carregar().then(() => {
    if (route.query.veiculo_id && !route.query.orcamento_id) abrirNovo()
  })
})
</script>

<template>
  <div>
    <div class="cabecalho">
      <h2>Orçamentos</h2>
      <Button v-if="podeGerir()" label="Novo Orçamento" icon="pi pi-plus" @click="abrirNovo" />
    </div>

    <DataTable :value="orcamentos" :loading="carregando" paginator :rows="15" dataKey="id" stripedRows>
      <Column header="Veículo">
        <template #body="{ data }">{{ data.veiculo?.placa }}</template>
      </Column>
      <Column header="Cliente">
        <template #body="{ data }">{{ data.cliente?.nome }}</template>
      </Column>
      <Column field="versao" header="Versão" style="width: 90px" />
      <Column header="Status">
        <template #body="{ data }">
          <Tag :severity="severidadeStatus[data.status]" :value="data.status" />
        </template>
      </Column>
      <Column header="Valor Total">
        <template #body="{ data }">{{ formatarMoeda(data.valor_total) }}</template>
      </Column>
      <Column header="Acréscimos" v-if="true">
        <template #body="{ data }">
          {{ formatarMoeda(data.orcamento_acrescimos.reduce((s, a) => s + a.valor_acrescimo, 0)) }}
        </template>
      </Column>
      <Column header="Ações" style="width: 420px">
        <template #body="{ data }">
          <template v-if="data.status === 'rascunho' && podeGerir()">
            <Button icon="pi pi-list" label="Itens" size="small" text @click="abrirItens(data)" />
            <Button icon="pi pi-send" label="Enviar" size="small" @click="enviar(data)" />
          </template>
          <template v-if="data.status === 'enviado'">
            <Button v-if="podeAutorizar()" label="Autorização" size="small" text @click="abrirAutorizacao(data)" />
            <Button v-if="podeGerir()" label="Aprovar" size="small" severity="success" @click="confirmarAprovacao(data)" />
            <Button v-if="podeGerir()" label="Rejeitar" size="small" severity="danger" text @click="confirmarRejeicao(data)" />
          </template>
          <template v-if="data.status === 'aprovado' && podeGerir()">
            <Button label="Acréscimo" size="small" text @click="abrirAcrescimo(data)" />
            <Button label="Criar OS" size="small" severity="success" @click="criarOs(data)" />
          </template>
          <Button
            v-if="['enviado', 'aprovado', 'rejeitado'].includes(data.status) && podeGerir()"
            label="Nova Versão"
            size="small"
            text
            @click="novaVersao(data)"
          />
        </template>
      </Column>
    </DataTable>

    <!-- Novo orçamento -->
    <Dialog v-model:visible="dialogoNovoAberto" modal header="Novo Orçamento" style="width: 420px">
      <div class="form-campo">
        <label>Veículo</label>
        <Select
          v-model="formNovo.veiculo_id"
          :options="veiculos"
          optionLabel="placa"
          optionValue="id"
          filter
          placeholder="Selecione o veículo"
          :disabled="!!route.query.veiculo_id"
        />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovoAberto = false" />
        <Button label="Criar Rascunho" :loading="salvandoNovo" @click="criarRascunho" />
      </template>
    </Dialog>

    <!-- Itens -->
    <Dialog v-model:visible="dialogoItensAberto" modal header="Itens do Orçamento" style="width: 680px">
      <div v-for="(item, index) in itens" :key="index" class="linha-item">
        <Select
          v-model="item.peca_id"
          :options="pecas"
          optionLabel="descricao"
          optionValue="id"
          filter
          showClear
          placeholder="Peça (opcional)"
          class="item-peca"
          @update:modelValue="selecionouPeca(item)"
        />
        <InputText v-model="item.descricao" placeholder="Descrição" class="item-descricao" />
        <InputNumber v-model="item.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" class="item-qtd" />
        <InputNumber v-model="item.valor_unitario" placeholder="Valor Unit." mode="currency" currency="BRL" locale="pt-BR" class="item-valor" />
        <Button icon="pi pi-trash" text rounded severity="danger" @click="removerItem(index)" />
      </div>
      <div class="botoes-item">
        <Button label="Adicionar item de peça" icon="pi pi-plus" text size="small" @click="adicionarItemPeca" />
        <Button label="Adicionar mão de obra" icon="pi pi-plus" text size="small" @click="adicionarItemMaoDeObra" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoItensAberto = false" />
        <Button label="Salvar Itens" :loading="salvandoItens" @click="salvarItens" />
      </template>
    </Dialog>

    <!-- Autorização / comprovante -->
    <Dialog v-model:visible="dialogoAutorizacaoAberto" modal header="Autorização do Cliente" style="width: 420px">
      <div class="form-campo">
        <label>Autorizado por (nome)</label>
        <InputText v-model="formAutorizacao.autorizado_por_nome" />
      </div>
      <div class="form-campo">
        <label>Comprovante (foto/PDF)</label>
        <input type="file" @change="onArquivoSelecionado" accept="image/*,application/pdf" />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAutorizacaoAberto = false" />
        <Button label="Salvar" :loading="salvandoAutorizacao" @click="salvarAutorizacao" />
      </template>
    </Dialog>

    <!-- Acréscimo -->
    <Dialog v-model:visible="dialogoAcrescimoAberto" modal header="Registrar Acréscimo" style="width: 420px">
      <div class="form-campo">
        <label>Valor do Acréscimo</label>
        <InputNumber v-model="formAcrescimo.valor_acrescimo" mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Justificativa</label>
        <Textarea v-model="formAcrescimo.justificativa" rows="3" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoAcrescimoAberto = false" />
        <Button label="Registrar" :loading="salvandoAcrescimo" @click="salvarAcrescimo" />
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
.linha-item {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.5rem;
}
.item-peca {
  flex: 1.5;
}
.item-descricao {
  flex: 2;
}
.item-qtd,
.item-valor {
  flex: 1;
}
.botoes-item {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.25rem;
}
</style>
