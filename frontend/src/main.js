import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import ConfirmationService from 'primevue/confirmationservice'
import Aura from '@primeuix/themes/aura'

import 'primeicons/primeicons.css'
import './style.css'

import App from './App.vue'
import router from './router'
import { authRedirect } from './lib/supabaseClient'
import { useAuthStore, marcarSenhaPendente } from './stores/auth'

// ETAPA AUTH-01 — a inicialização é sequenciada (não apenas
// app.use(router) + app.mount() direto) para evitar uma condição de corrida
// real entre o Vue Router (createWebHashHistory, dono do "#" da URL) e o
// GoTrue (que também usa "#access_token=...&type=invite|recovery" para
// convite/recuperação de senha). Sem isso, o router tenta casar o hash cru
// do token como se fosse uma rota (não existe rota catch-all) e o usuário
// vê uma tela em branco antes do GoTrue terminar de consumir o hash de
// forma assíncrona. Ver docs/testing/TEST_REPORT_AUTH01.md.
async function bootstrap() {
  const app = createApp(App)
  app.use(createPinia())

  // Espera a sessão (se houver token de convite/recuperação na URL) ser
  // totalmente processada pelo GoTrue ANTES de instalar o router — assim
  // o router nunca chega a ver o hash cru do token.
  const auth = useAuthStore()
  await auth.init()

  // Normaliza o hash para uma rota válida ANTES do router ser instalado,
  // usando o tipo capturado de forma síncrona em supabaseClient.js (não
  // depende do evento PASSWORD_RECOVERY do GoTrue, que não é disparado
  // para type=invite).
  if (authRedirect.type === 'invite' || authRedirect.type === 'recovery') {
    // Persistido em localStorage (não só nesta variável de módulo) porque
    // um teste real contra produção mostrou que, se o usuário abrir uma
    // aba nova ou recarregar antes de confirmar a senha, o gate baseado só
    // no hash desta página específica não protege mais nada — a sessão já
    // existe no localStorage compartilhado. O guard em router/index.js lê
    // essa flag em toda navegação. Ver docs/testing/TEST_REPORT_AUTH01.md.
    marcarSenhaPendente()
    window.location.hash = '#/definir-senha'
  } else if (authRedirect.type === 'error') {
    window.location.hash = `#/login?erroAuth=${encodeURIComponent(authRedirect.errorCode)}`
  }

  app.use(router)
  app.use(PrimeVue, {
    theme: {
      preset: Aura,
      options: { darkModeSelector: '.dark' },
    },
  })
  app.use(ToastService)
  app.use(ConfirmationService)

  await router.isReady()
  app.mount('#app')
}

bootstrap()
