<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import InputText from 'primevue/inputtext'
import Button from 'primevue/button'
import Message from 'primevue/message'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import AuthLayout from '../components/auth/AuthLayout.vue'

const email = ref('')
const enviado = ref(false)
const erro = ref('')
const carregando = ref(false)

const auth = useAuthStore()
const router = useRouter()

async function enviar() {
  erro.value = ''
  carregando.value = true
  try {
    await auth.solicitarRecuperacaoSenha(email.value)
    // ETAPA AUTH-01 — mensagem de sucesso é sempre a mesma, exista ou não
    // o e-mail informado (o próprio Supabase Auth já não vaza essa
    // informação na resposta da API; não adicionamos lógica que vazasse).
    enviado.value = true
  } catch (e) {
    erro.value = 'Não foi possível enviar o e-mail agora. Tente novamente em instantes.'
  } finally {
    carregando.value = false
  }
}
</script>

<template>
  <AuthLayout tagline="Recupere o acesso à sua conta de forma rápida e segura.">
    <form v-if="!enviado" @submit.prevent="enviar">
      <button type="button" class="auth-back-link" @click="router.push('/login')">
        <i class="pi pi-arrow-left"></i> Voltar ao login
      </button>

      <h1 class="auth-title">Esqueci minha senha</h1>
      <p class="auth-subtitle">Informe seu e-mail cadastrado para receber o link de recuperação.</p>

      <div class="auth-messages">
        <Message v-if="erro" severity="error" :closable="false">{{ erro }}</Message>
      </div>

      <div class="auth-field">
        <label for="email">E-mail</label>
        <IconField>
          <InputIcon class="pi pi-envelope" />
          <InputText
            id="email"
            v-model="email"
            type="email"
            autocomplete="username"
            placeholder="voce@tropicaltransportes.com.br"
            fluid
            required
          />
        </IconField>
      </div>

      <div class="auth-actions">
        <Button
          type="submit"
          label="Enviar link de recuperação"
          :loading="carregando"
          class="auth-btn-primary"
          fluid
        />
      </div>
    </form>

    <div v-else class="auth-success">
      <div class="auth-success-icon"><i class="pi pi-check"></i></div>
      <h1 class="auth-title">Verifique seu e-mail</h1>
      <Message severity="success" :closable="false">
        Se houver uma conta cadastrada com esse e-mail, enviamos um link para você redefinir sua senha.
      </Message>
      <Button
        label="Voltar ao login"
        class="auth-btn-primary"
        style="margin-top: 20px"
        fluid
        @click="router.push('/login')"
      />
    </div>
  </AuthLayout>
</template>

<style scoped>
.auth-success {
  display: flex;
  flex-direction: column;
}
.auth-success .auth-title {
  margin-bottom: 10px;
}
</style>
