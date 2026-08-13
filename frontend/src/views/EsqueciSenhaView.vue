<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import InputText from 'primevue/inputtext'
import Button from 'primevue/button'
import Message from 'primevue/message'

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
  <div class="login-page">
    <form v-if="!enviado" class="login-card" @submit.prevent="enviar">
      <h1>Esqueci minha senha</h1>
      <p class="subtitulo">Informe seu e-mail cadastrado para receber o link de recuperação.</p>

      <label for="email">E-mail</label>
      <InputText id="email" v-model="email" type="email" autocomplete="username" required />

      <Message v-if="erro" severity="error" :closable="false">{{ erro }}</Message>

      <Button type="submit" label="Enviar link de recuperação" :loading="carregando" class="botao-entrar" />
      <Button label="Voltar ao login" text @click="router.push('/login')" />
    </form>

    <div v-else class="login-card">
      <h1>Verifique seu e-mail</h1>
      <Message severity="success" :closable="false">
        Se houver uma conta cadastrada com esse e-mail, enviamos um link para você redefinir sua senha.
      </Message>
      <Button label="Voltar ao login" class="botao-entrar" @click="router.push('/login')" />
    </div>
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
