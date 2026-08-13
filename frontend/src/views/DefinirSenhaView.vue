<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { authRedirect } from '../lib/supabaseClient'
import Password from 'primevue/password'
import Button from 'primevue/button'
import Message from 'primevue/message'

const senha = ref('')
const confirmacao = ref('')
const erro = ref('')
const carregando = ref(false)

const auth = useAuthStore()
const router = useRouter()

// ETAPA AUTH-01 — distingue convite (primeiro acesso) de recuperação, para
// decidir o que acontece depois de definir a senha (seções 3 e 4 do
// roteiro): convite entra direto no ERP; recuperação encerra a sessão e
// manda pro login normal, por segurança (a sessão usada para chegar aqui
// veio de um link de e-mail, não de um login com a senha definitiva).
const ehRecuperacao = authRedirect.type === 'recovery'

const titulo = computed(() =>
  ehRecuperacao ? 'Defina sua nova senha' : 'Defina sua senha de acesso'
)
const subtitulo = computed(() =>
  ehRecuperacao
    ? 'Escolha uma nova senha para sua conta.'
    : 'Bem-vindo(a) ao ERP Oficina — Tropical Transportes. Escolha uma senha para concluir seu primeiro acesso.'
)

async function confirmar() {
  erro.value = ''
  if (senha.value.length < 8) {
    erro.value = 'A senha precisa ter pelo menos 8 caracteres.'
    return
  }
  if (senha.value !== confirmacao.value) {
    erro.value = 'As senhas não coincidem.'
    return
  }
  carregando.value = true
  try {
    await auth.definirNovaSenha(senha.value)
    if (ehRecuperacao) {
      await auth.logout()
      router.push({ name: 'login', query: { senhaRedefinida: '1' } })
    } else {
      router.push('/')
    }
  } catch (e) {
    erro.value = e?.message || 'Não foi possível definir a senha agora. Tente novamente.'
  } finally {
    carregando.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <form class="login-card" @submit.prevent="confirmar">
      <h1>{{ titulo }}</h1>
      <p class="subtitulo">{{ subtitulo }}</p>

      <label for="senha">Nova senha</label>
      <Password id="senha" v-model="senha" toggleMask autocomplete="new-password" required />

      <label for="confirmacao">Confirme a nova senha</label>
      <Password
        id="confirmacao"
        v-model="confirmacao"
        :feedback="false"
        toggleMask
        autocomplete="new-password"
        required
      />

      <Message v-if="erro" severity="error" :closable="false">{{ erro }}</Message>

      <Button type="submit" label="Confirmar senha" :loading="carregando" class="botao-entrar" />
    </form>
  </div>
</template>

<style scoped>
.login-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f4f5f7;
}
.login-card {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  width: 100%;
  max-width: 360px;
  padding: 2rem;
  background: white;
  border-radius: 12px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
}
.login-card h1 {
  font-size: 1.25rem;
  margin: 0;
}
.subtitulo {
  margin: 0 0 0.5rem;
  color: #6b7280;
  font-size: 0.875rem;
}
.botao-entrar {
  margin-top: 0.5rem;
}
</style>
