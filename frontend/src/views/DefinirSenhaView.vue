<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { authRedirect } from '../lib/supabaseClient'
import Password from 'primevue/password'
import Button from 'primevue/button'
import Message from 'primevue/message'
import AuthLayout from '../components/auth/AuthLayout.vue'

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
  <AuthLayout tagline="Escolha uma senha forte para proteger o acesso à sua conta.">
    <form @submit.prevent="confirmar">
      <h1 class="auth-title">{{ titulo }}</h1>
      <p class="auth-subtitle">{{ subtitulo }}</p>

      <div class="auth-messages">
        <Message v-if="erro" severity="error" :closable="false">{{ erro }}</Message>
      </div>

      <div class="auth-field">
        <label for="senha">Nova senha</label>
        <Password
          id="senha"
          v-model="senha"
          toggleMask
          autocomplete="new-password"
          placeholder="Mínimo de 8 caracteres"
          fluid
          required
        />
      </div>

      <div class="auth-field">
        <label for="confirmacao">Confirme a nova senha</label>
        <Password
          id="confirmacao"
          v-model="confirmacao"
          :feedback="false"
          toggleMask
          autocomplete="new-password"
          placeholder="Repita a senha"
          fluid
          required
        />
      </div>

      <div class="auth-actions">
        <Button
          type="submit"
          label="Confirmar senha"
          :loading="carregando"
          class="auth-btn-primary"
          fluid
        />
      </div>
    </form>
  </AuthLayout>
</template>
