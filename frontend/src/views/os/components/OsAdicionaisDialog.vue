<script setup>
import { ref, watch } from 'vue'
import { useToast } from 'primevue/usetoast'
import Dialog from 'primevue/dialog'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Textarea from 'primevue/textarea'
import Tag from 'primevue/tag'

// OS-UX-02 — conteúdo movido da antiga aba "Adicionais" para dialog sob
// demanda (item 23 do pedido), incluindo os 4 sub-dialogs que já existiam
// (identificar/incluir item/decidir/cancelar). Mesmas 4 RPCs
// (rpc_criar_os_adicional, rpc_incluir_item_os_adicional,
// rpc_decidir_item_os_adicional, rpc_cancelar_os_adicional) e mesmo upload
// de storage ('comprovantes') do arquivo original — só a validação de
// formulário (motivo mín. 5 chars etc.) que era feita no pai antes de
// chamar a RPC agora é feita aqui antes de emitir o payload; a chamada
// RPC/upload em si continua só no pai.
const props = defineProps({
  osAdicionais: { type: Array, default: () => [] },
  pecas: { type: Array, default: () => [] },
  osEncerrada: Boolean,
  podeIdentificarAdicional: Boolean,
  podePrecificarAdicional: Boolean,
  podeDecidirAdicional: Boolean,
  podeCancelarAdicional: Boolean,
  podeMarcarExecucao: Boolean,
  formatarMoeda: { type: Function, required: true },
  valorAdicional: { type: Function, required: true },
  criarAdicional: { type: Function, required: true },
  incluirItemAdicional: { type: Function, required: true },
  decidirItemAdicional: { type: Function, required: true },
  marcarItemAdicionalExecutado: { type: Function, required: true },
  cancelarAdicional: { type: Function, required: true },
  abrirCancelarItem: { type: Function, required: true },
})

const toast = useToast()
const visible = defineModel('visible', { default: false })

const severidadeStatusAdicional = { aguardando_aprovacao: 'warn', aprovado: 'success', parcialmente_aprovado: 'warn', rejeitado: 'danger' }
const tagDecisaoItemAdicional = { pendente: 'warn', aprovado: 'success', rejeitado: 'danger' }

// ---------- Identificar necessidade ----------
const dialogoNovo = ref(false)
const formNovo = ref({ motivo: '' })
let idempotencyKey = crypto.randomUUID()
function abrirNovo() {
  formNovo.value = { motivo: '' }
  idempotencyKey = crypto.randomUUID()
  dialogoNovo.value = true
}
async function confirmarNovo() {
  if (!formNovo.value.motivo || formNovo.value.motivo.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Descreva o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const ok = await props.criarAdicional({ motivo: formNovo.value.motivo, idempotency_key: idempotencyKey })
  if (ok) {
    dialogoNovo.value = false
    idempotencyKey = crypto.randomUUID()
  }
}

// ---------- Incluir item precificado ----------
const dialogoItem = ref(false)
const adicionalAtual = ref(null)
const formItem = ref({ peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0, justificativa: '' })
function abrirIncluirItem(adicional) {
  adicionalAtual.value = adicional
  formItem.value = { peca_id: null, descricao: '', quantidade: 1, valor_unitario: 0, justificativa: '' }
  dialogoItem.value = true
}
function selecionouPeca() {
  const p = props.pecas.find((x) => x.id === formItem.value.peca_id)
  if (p && !formItem.value.descricao) formItem.value.descricao = p.descricao
}
async function confirmarItem() {
  if (!formItem.value.descricao || formItem.value.quantidade <= 0) {
    toast.add({ severity: 'warn', summary: 'Descrição e quantidade são obrigatórias', life: 4000 })
    return
  }
  const ok = await props.incluirItemAdicional({
    adicional_id: adicionalAtual.value.id,
    peca_id: formItem.value.peca_id,
    descricao: formItem.value.descricao,
    quantidade: formItem.value.quantidade,
    valor_unitario: formItem.value.valor_unitario,
    justificativa: formItem.value.justificativa,
  })
  if (ok) dialogoItem.value = false
}

// ---------- Decisão do cliente ----------
const dialogoDecisao = ref(false)
const itemAtual = ref(null)
const formDecisao = ref({ autorizado_por_nome: '', meio_aprovacao: 'sistema', observacao: '', arquivo: null })
const meiosAprovacao = [
  { label: 'Sistema (botão)', value: 'sistema' },
  { label: 'E-mail (evidência obrigatória)', value: 'email' },
  { label: 'Verbal documentado (observação obrigatória)', value: 'verbal_documentado' },
]
function abrirDecisao(item) {
  itemAtual.value = item
  formDecisao.value = { autorizado_por_nome: '', meio_aprovacao: 'sistema', observacao: '', arquivo: null }
  dialogoDecisao.value = true
}
function onArquivoDecisao(event) {
  formDecisao.value.arquivo = event.target.files[0] || null
}
async function confirmarDecisao(decisao) {
  if (!formDecisao.value.autorizado_por_nome || formDecisao.value.autorizado_por_nome.trim().length < 2) {
    toast.add({ severity: 'warn', summary: 'Informe o nome de quem autorizou', life: 5000 })
    return
  }
  if (formDecisao.value.meio_aprovacao === 'verbal_documentado' && formDecisao.value.observacao.trim().length < 10) {
    toast.add({ severity: 'warn', summary: 'Observação obrigatória (mín. 10 caracteres) para verbal documentado', life: 5000 })
    return
  }
  if (formDecisao.value.meio_aprovacao === 'email' && !formDecisao.value.arquivo) {
    toast.add({ severity: 'warn', summary: 'Anexe o comprovante do e-mail', life: 5000 })
    return
  }
  const ok = await props.decidirItemAdicional({
    item_id: itemAtual.value.id,
    decisao,
    meio_aprovacao: formDecisao.value.meio_aprovacao,
    autorizado_por_nome: formDecisao.value.autorizado_por_nome,
    observacao: formDecisao.value.observacao,
    arquivo: formDecisao.value.arquivo,
  })
  if (ok) dialogoDecisao.value = false
}

// ---------- Cancelar adicional ----------
const dialogoCancelar = ref(false)
const adicionalParaCancelar = ref(null)
const motivoCancelamento = ref('')
function abrirCancelarAdicional(adicional) {
  adicionalParaCancelar.value = adicional
  motivoCancelamento.value = ''
  dialogoCancelar.value = true
}
async function confirmarCancelarAdicional() {
  if (!motivoCancelamento.value || motivoCancelamento.value.trim().length < 5) {
    toast.add({ severity: 'warn', summary: 'Informe o motivo (mín. 5 caracteres)', life: 4000 })
    return
  }
  const ok = await props.cancelarAdicional({ adicional_id: adicionalParaCancelar.value.id, motivo: motivoCancelamento.value })
  if (ok) dialogoCancelar.value = false
}
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Adicionais" style="width: 700px">
    <div class="cabecalho-secao">
      <span></span>
      <Button v-if="podeIdentificarAdicional && !osEncerrada" label="Identificar Necessidade" icon="pi pi-plus" size="small" @click="abrirNovo" />
    </div>
    <div v-if="osAdicionais.length === 0" class="estado-vazio-card">
      <i class="pi pi-plus-circle"></i>
      <div>
        <strong>Nenhum adicional identificado</strong>
        <p>Necessidades identificadas durante a execução aparecerão aqui, aguardando precificação e decisão do cliente.</p>
      </div>
    </div>
    <div v-for="adicional in osAdicionais" :key="adicional.id" class="cartao-adicional">
      <div class="cabecalho-secao">
        <div>
          <strong>AD-{{ String(adicional.numero).padStart(3, '0') }}</strong>
          <Tag :severity="severidadeStatusAdicional[adicional.status]" :value="adicional.status" style="margin-left:0.5rem" />
          <span class="hint" style="margin-left:0.5rem">{{ adicional.motivo }}</span>
        </div>
        <div>
          <span class="hint" style="margin-right:0.75rem">
            Aprovado: <strong style="color:#4ade80">{{ formatarMoeda(valorAdicional(adicional, 'aprovado')) }}</strong>
            &nbsp;Rejeitado: <strong style="color:#f87171">{{ formatarMoeda(valorAdicional(adicional, 'rejeitado')) }}</strong>
          </span>
          <Button v-if="podePrecificarAdicional && !osEncerrada" label="Incluir item" size="small" text @click="abrirIncluirItem(adicional)" />
          <Button v-if="podeCancelarAdicional && adicional.status === 'aguardando_aprovacao'" label="Cancelar" size="small" text severity="danger" @click="abrirCancelarAdicional(adicional)" />
        </div>
      </div>
      <table class="tabela-itens-decisao" v-if="adicional.os_adicional_itens?.length">
        <thead>
          <tr><th>Item</th><th>Valor</th><th>Decisão</th><th>Meio</th><th>Execução</th><th>Ação</th></tr>
        </thead>
        <tbody>
          <tr v-for="item in adicional.os_adicional_itens" :key="item.id">
            <td>{{ item.descricao }}<span v-if="item.peca"> — {{ item.peca.descricao }}</span> <span class="hint">({{ item.quantidade }}x)</span></td>
            <td>{{ formatarMoeda(item.valor_total) }}</td>
            <td><Tag :severity="tagDecisaoItemAdicional[item.status_aprovacao]" :value="item.status_aprovacao" /></td>
            <td>{{ item.meio_aprovacao || '—' }}</td>
            <td><Tag v-if="item.status_aprovacao === 'aprovado'" :severity="item.execucao_status === 'executado' ? 'success' : item.execucao_status === 'cancelado' ? 'danger' : 'warn'" :value="item.execucao_status" /><span v-else class="hint">—</span></td>
            <td>
              <template v-if="item.status_aprovacao === 'pendente' && podeDecidirAdicional">
                <Button label="Decidir" size="small" @click="abrirDecisao(item)" />
              </template>
              <template v-else-if="item.status_aprovacao === 'aprovado' && !item.peca_id && podeMarcarExecucao && !['executado', 'cancelado'].includes(item.execucao_status)">
                <Button label="Executado" size="small" text @click="marcarItemAdicionalExecutado(item)" />
                <Button label="Dispensar" size="small" text severity="danger" @click="abrirCancelarItem(item, 'adicional')" />
              </template>
              <span v-else class="hint">—</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog v-model:visible="dialogoNovo" modal header="Identificar Necessidade de Adicional" style="width: 460px">
      <p class="hint">Descreva o que foi identificado durante a execução. O encarregado/admin técnico vai precificar e enviar para decisão do cliente em seguida.</p>
      <Textarea v-model="formNovo.motivo" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Cancelar" text @click="dialogoNovo = false" />
        <Button label="Registrar" @click="confirmarNovo" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoItem" modal header="Incluir Item Precificado" style="width: 480px">
      <div class="form-campo">
        <label>Peça (opcional — vazio = mão de obra)</label>
        <Select v-model="formItem.peca_id" :options="pecas" optionLabel="descricao" optionValue="id" filter showClear placeholder="Peça" @update:modelValue="selecionouPeca" />
      </div>
      <div class="form-campo">
        <label>Descrição</label>
        <InputText v-model="formItem.descricao" />
      </div>
      <div class="form-linha">
        <InputNumber v-model="formItem.quantidade" placeholder="Qtde" :minFractionDigits="0" :maxFractionDigits="3" />
        <InputNumber v-model="formItem.valor_unitario" placeholder="Valor Unit." mode="currency" currency="BRL" locale="pt-BR" />
      </div>
      <div class="form-campo">
        <label>Justificativa (opcional)</label>
        <Textarea v-model="formItem.justificativa" rows="2" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoItem = false" />
        <Button label="Incluir" @click="confirmarItem" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoDecisao" modal header="Decisão do Cliente — Item de Adicional" style="width: 460px">
      <div class="form-campo">
        <label>Meio de aprovação</label>
        <Select v-model="formDecisao.meio_aprovacao" :options="meiosAprovacao" optionLabel="label" optionValue="value" />
      </div>
      <div class="form-campo">
        <label>Autorizado por (nome do cliente/responsável)</label>
        <InputText v-model="formDecisao.autorizado_por_nome" />
      </div>
      <div class="form-campo" v-if="formDecisao.meio_aprovacao === 'email'">
        <label>Comprovante (evidência do e-mail)</label>
        <input type="file" @change="onArquivoDecisao" accept="image/*,application/pdf,.eml,.msg" />
      </div>
      <div class="form-campo" v-if="formDecisao.meio_aprovacao === 'verbal_documentado'">
        <label>Observação (obrigatória)</label>
        <Textarea v-model="formDecisao.observacao" rows="2" autoResize />
      </div>
      <template #footer>
        <Button label="Cancelar" text @click="dialogoDecisao = false" />
        <Button label="Rejeitar" severity="danger" text @click="confirmarDecisao('rejeitado')" />
        <Button label="Aprovar" severity="success" @click="confirmarDecisao('aprovado')" />
      </template>
    </Dialog>

    <Dialog v-model:visible="dialogoCancelar" modal header="Cancelar Adicional" style="width: 420px">
      <p class="hint">Cancela o adicional inteiro (itens ainda pendentes viram rejeitados) — fica registrado na trilha de auditoria.</p>
      <Textarea v-model="motivoCancelamento" rows="3" autoResize placeholder="Motivo (mínimo 5 caracteres)" style="width:100%" />
      <template #footer>
        <Button label="Voltar" text @click="dialogoCancelar = false" />
        <Button label="Confirmar cancelamento" severity="danger" @click="confirmarCancelarAdicional" />
      </template>
    </Dialog>
  </Dialog>
</template>

<style scoped>
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
}
.estado-vazio-card {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 16px 4px;
  color: var(--text-faint);
}
.estado-vazio-card i {
  font-size: 22px;
  margin-top: 2px;
}
.estado-vazio-card strong {
  display: block;
  color: var(--text-secondary);
  font-size: 13px;
  margin-bottom: 2px;
}
.estado-vazio-card p {
  margin: 0;
  font-size: 12.5px;
  line-height: 1.4;
}
.cabecalho-secao {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 10px;
}
.cartao-adicional {
  border: 1px solid var(--border-panel);
  border-radius: 10px;
  padding: 0.75rem 1rem;
  margin-top: 0.75rem;
  background: var(--surface-hover);
}
.tabela-itens-decisao {
  width: 100%;
  border-collapse: collapse;
  margin-top: 0.75rem;
}
.tabela-itens-decisao th,
.tabela-itens-decisao td {
  text-align: left;
  padding: 0.4rem 0.5rem;
  border-bottom: 1px solid var(--border-row);
  font-size: 0.85rem;
  vertical-align: middle;
  color: var(--text-body);
}
.tabela-itens-decisao th {
  color: var(--text-table-header);
  font-weight: 600;
  font-size: 0.75rem;
  text-transform: uppercase;
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
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.75rem;
  flex-wrap: wrap;
}
</style>
