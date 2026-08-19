<script setup>
import { ref, watch } from 'vue'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import InputText from 'primevue/inputtext'
import Button from 'primevue/button'
import Tag from 'primevue/tag'

// OS-UX-02 — conteúdo movido da antiga aba "Fotos" para dialog sob demanda
// (item 21 do pedido). Mesma RPC (rpc_registrar_foto_os) + mesmo upload de
// storage ('os-fotos') do arquivo original; formulário agora é local.
const props = defineProps({
  osFotos: { type: Array, default: () => [] },
  checklistTemplateAtual: { type: Object, default: null },
  podeAnexarFoto: Boolean,
  osEncerrada: Boolean,
  enviarFoto: { type: Function, required: true },
})

const visible = defineModel('visible', { default: false })

const form = ref({ tipo: 'antes', arquivo: null, observacao: '' })
const enviando = ref(false)
watch(visible, (v) => {
  if (v) form.value = { tipo: 'antes', arquivo: null, observacao: '' }
})

function onArquivoSelecionado(event) {
  form.value.arquivo = event.target.files[0] || null
}

async function confirmarEnvio() {
  if (!form.value.arquivo) return
  enviando.value = true
  const ok = await props.enviarFoto({ tipo: form.value.tipo, arquivo: form.value.arquivo, observacao: form.value.observacao })
  enviando.value = false
  if (ok) form.value = { tipo: 'antes', arquivo: null, observacao: '' }
}
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Fotos" style="width: 520px">
    <p v-if="checklistTemplateAtual" class="hint">
      Este tipo de serviço exige:
      <Tag :severity="checklistTemplateAtual.foto_antes_obrigatoria ? 'danger' : 'secondary'" :value="checklistTemplateAtual.foto_antes_obrigatoria ? 'foto antes obrigatória' : 'foto antes opcional'" style="margin-right:0.3rem" />
      <Tag :severity="checklistTemplateAtual.foto_depois_obrigatoria ? 'danger' : 'secondary'" :value="checklistTemplateAtual.foto_depois_obrigatoria ? 'foto depois obrigatória' : 'foto depois opcional'" />
    </p>
    <div class="form-linha" v-if="podeAnexarFoto && !osEncerrada">
      <Select v-model="form.tipo" :options="[{ label: 'Antes', value: 'antes' }, { label: 'Depois', value: 'depois' }, { label: 'Outro', value: 'outro' }]" optionLabel="label" optionValue="value" />
      <input type="file" accept="image/jpeg,image/png,image/webp" @change="onArquivoSelecionado" />
      <InputText v-model="form.observacao" placeholder="Observação (opcional)" />
      <Button label="Enviar" size="small" :loading="enviando" :disabled="!form.arquivo" @click="confirmarEnvio" />
    </div>

    <div v-if="osFotos.length === 0" class="estado-vazio-card">
      <i class="pi pi-image"></i>
      <div>
        <strong>Nenhuma foto anexada</strong>
        <p>Adicione imagens de antes, durante ou depois para compor o histórico visual da OS.</p>
      </div>
    </div>
    <ul v-else class="checklist">
      <li v-for="f in osFotos" :key="f.id">
        <Tag :severity="f.tipo === 'antes' ? 'info' : f.tipo === 'depois' ? 'success' : 'secondary'" :value="f.tipo" />
        <span>{{ f.arquivo_path.split('/').pop() }}</span>
        <span class="hint">por {{ f.enviado_por_profile?.nome }} em {{ new Date(f.enviado_em).toLocaleString('pt-BR') }}</span>
      </li>
    </ul>
  </Dialog>
</template>

<style scoped>
.form-linha {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.9rem;
  flex-wrap: wrap;
}
.hint {
  color: var(--text-muted);
  font-size: 0.85rem;
}
.checklist {
  list-style: none;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  margin: 0;
}
.checklist li {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
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
</style>
