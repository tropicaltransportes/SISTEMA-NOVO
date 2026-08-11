<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import InputText from 'primevue/inputtext'
import Password from 'primevue/password'
import Button from 'primevue/button'
import Message from 'primevue/message'

const email = ref('')
const password = ref('')
const erro = ref('')
const carregando = ref(false)

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

async function entrar() {
  erro.value = ''
  carregando.value = true
  try {
    await auth.login(email.value, password.value)
    router.push(route.query.redirect ?? '/')
  } catch (e) {
    // ETAPA 4 (P1-A): conta inativa tem mensagem própria (auth.js lança
    // esse erro específico) — o resto continua como "credenciais inválidas"
    // genérico, para não vazar se um e-mail existe ou não.
    erro.value = e?.message?.includes('inativa') ? e.message : 'E-mail ou senha inválidos.'
  } finally {
    carregando.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <form class="login-card" @submit.prevent="entrar">
      <h1>ERP Oficina — Tropical Transportes</h1>
      <p class="subtitulo">Acesso restrito a usuários convidados</p>

      <label for="email">E-mail</label>
      <InputText id="email" v-model="email" type="email" autocomplete="username" required />

      <label for="senha">Senha</label>
      <Password
        id="senha"
        v-model="password"
        :feedback="false"
        toggleMask
        autocomplete="current-password"
        required
      />

      <Message v-if="erro" severity="error" :closable="false">{{ erro }}</Message>

      <Button type="submit" label="Entrar" :loading="carregando" class="botao-entrar" />
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
