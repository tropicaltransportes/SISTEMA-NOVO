<script setup>
import { ref } from 'vue'
import { useAuthStore } from '../../stores/auth'
import { useToast } from 'primevue/usetoast'
import Password from 'primevue/password'
import Button from 'primevue/button'

const auth = useAuthStore()
const toast = useToast()

const novaSenha = ref('')
const confirmacao = ref('')
const salvando = ref(false)

// ETAPA AUTH-01 — seção 5. O Supabase Auth updateUser() não pede/valida
// "senha atual": a sessão autenticada já é a prova de identidade (mesma
// API nativa do Supabase Auth usada em toda a etapa — nenhuma coluna de
// senha em tabela public foi criada).
async function salvar() {
  if (novaSenha.value.length < 8) {
    toast.add({ severity: 'warn', summary: 'Senha muito curta', detail: 'Use pelo menos 8 caracteres.', life: 4000 })
    return
  }
  if (novaSenha.value !== confirmacao.value) {
    toast.add({ severity: 'warn', summary: 'Senhas não coincidem', detail: 'Confirme a nova senha corretamente.', life: 4000 })
    return
  }
  salvando.value = true
  try {
    await auth.alterarSenha(novaSenha.value)
    toast.add({ severity: 'success', summary: 'Senha alterada com sucesso', life: 4000 })
    novaSenha.value = ''
    confirmacao.value = ''
  } catch (e) {
    toast.add({
      severity: 'error',
      summary: 'Não foi possível alterar a senha',
      detail: e?.message || 'Tente novamente.',
      life: 6000,
    })
  } finally {
    salvando.value = false
  }
}
</script>

<template>
  <div class="pagina-senha">
    <h2>Alterar senha</h2>
    <p class="descricao">Defina uma nova senha para sua conta ({{ auth.profile?.nome }}).</p>

    <form class="form-senha" @submit.prevent="salvar">
      <div class="form-campo">
        <label for="nova-senha">Nova senha</label>
        <Password id="nova-senha" v-model="novaSenha" toggleMask autocomplete="new-password" />
      </div>
      <div class="form-campo">
        <label for="confirmar-nova-senha">Confirme a nova senha</label>
        <Password
          id="confirmar-nova-senha"
          v-model="confirmacao"
          :feedback="false"
          toggleMask
          autocomplete="new-password"
        />
      </div>
      <Button type="submit" label="Salvar nova senha" :loading="salvando" />
    </form>
  </div>
</template>

<style scoped>
.pagina-senha {
  max-width: 420px;
}
.descricao {
  color: var(--text-muted-2, #6b7280);
  font-size: 0.85rem;
  margin-bottom: 1.25rem;
}
.form-senha {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.form-campo {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}
.form-campo label {
  font-size: 0.8rem;
  color: var(--text-muted-2, #4b5563);
}
</style>
