<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import InputText from 'primevue/inputtext'
import Password from 'primevue/password'
import Button from 'primevue/button'
import Message from 'primevue/message'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import AuthLayout from '../components/auth/AuthLayout.vue'

const email = ref('')
const password = ref('')
const erro = ref('')
const carregando = ref(false)

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

// ETAPA AUTH-01 — mensagens vindas de outros pontos do ciclo de
// autenticação: link de convite/recuperação inválido ou expirado
// (?erroAuth=..., setado em main.js a partir do hash cru do GoTrue) e
// confirmação de senha redefinida com sucesso (?senhaRedefinida=1, setado
// em DefinirSenhaView.vue depois do fluxo de recuperação).
const MENSAGENS_ERRO_AUTH = {
  otp_expired: 'Esse link expirou ou já foi usado. Solicite um novo convite/recuperação.',
  access_denied: 'Esse link não é mais válido. Solicite um novo convite/recuperação.',
}
const erroAuthUrl = route.query.erroAuth
  ? MENSAGENS_ERRO_AUTH[route.query.erroAuth] ||
    'Esse link não é mais válido. Solicite um novo convite/recuperação.'
  : ''
const senhaRedefinidaOk = route.query.senhaRedefinida === '1'

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
  <AuthLayout>
    <form @submit.prevent="entrar">
      <h1 class="auth-title">Bem-vindo</h1>
      <p class="auth-subtitle">Entre com suas credenciais para acessar o ERP Oficina.</p>

      <div class="auth-messages">
        <Message v-if="erroAuthUrl" severity="warn" :closable="false">{{ erroAuthUrl }}</Message>
        <Message v-if="senhaRedefinidaOk" severity="success" :closable="false">
          Senha redefinida com sucesso. Faça login com sua nova senha.
        </Message>
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

      <div class="auth-field">
        <label for="senha">Senha</label>
        <Password
          id="senha"
          v-model="password"
          :feedback="false"
          toggleMask
          autocomplete="current-password"
          placeholder="Sua senha"
          fluid
          required
        />
      </div>

      <div class="auth-actions">
        <Button
          type="submit"
          label="Entrar"
          :loading="carregando"
          class="auth-btn-primary"
          fluid
        />
        <Button
          label="Esqueci minha senha"
          text
          class="auth-btn-link"
          @click="router.push('/esqueci-senha')"
        />
      </div>
    </form>
  </AuthLayout>
</template>
