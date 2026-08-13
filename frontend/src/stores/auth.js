import { defineStore } from 'pinia'
import { supabase } from '../lib/supabaseClient'

// ETAPA AUTH-01 — achado real de teste contra produção: o gate para
// /definir-senha em main.js só roda no boot da PÁGINA que consumiu o hash
// de convite/recuperação. Se o usuário convidado abandonar essa aba antes
// de confirmar a senha (ex.: abre uma aba nova, ou só recarrega depois de
// a sessão já existir no localStorage), ele cai direto no ERP sem nunca
// ter definido senha própria — exatamente o que a seção 3 do roteiro pede
// para evitar. localStorage é compartilhado entre abas da mesma origem
// (diferente de sessionStorage), então essa flag sobrevive a troca de aba
// e reload, e é limpa assim que a senha é realmente definida (ou em
// logout/login normal, para não prender à toa uma sessão futura legítima
// que já tenha senha).
const CHAVE_SENHA_PENDENTE = 'auth01-senha-pendente'
export function marcarSenhaPendente() {
  window.localStorage.setItem(CHAVE_SENHA_PENDENTE, '1')
}
function limparSenhaPendente() {
  window.localStorage.removeItem(CHAVE_SENHA_PENDENTE)
}
export function temSenhaPendente() {
  return window.localStorage.getItem(CHAVE_SENHA_PENDENTE) === '1'
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    session: null,
    profile: null, // { id, nome, perfil, ativo }
    loading: true,
  }),
  getters: {
    // ETAPA 4 (P1-A) — decisão de negócio #2: profiles.ativo=false é
    // bloqueio TOTAL no ERP. O backend (RLS/RPC) já falha fechado de
    // verdade (current_perfil()/current_user_ativo() retornam NULL/false —
    // ver docs/testing/TEST_REPORT_P1A.md), então mesmo se este getter
    // fosse contornado o usuário não conseguiria ler nem escrever nada. Ele
    // existe só para dar feedback claro em vez de telas vazias/quebradas.
    autenticado: (state) => !!state.session && state.profile?.ativo !== false,
    perfil: (state) => (state.profile?.ativo === false ? null : (state.profile?.perfil ?? null)),
    contaInativa: (state) => !!state.session && state.profile?.ativo === false,
  },
  actions: {
    async init() {
      const { data } = await supabase.auth.getSession()
      this.session = data.session
      if (this.session) {
        await this.carregarPerfil()
        await this._encerrarSeInativo()
      }
      this.loading = false

      supabase.auth.onAuthStateChange(async (event, session) => {
        this.session = session
        if (session) {
          await this.carregarPerfil()
          await this._encerrarSeInativo()
        } else {
          this.profile = null
        }
        // ETAPA AUTH-01 — rede de segurança para o caso de o evento
        // PASSWORD_RECOVERY chegar com o app já rodando (ex.: aba aberta
        // recebe o hash de recuperação depois do boot). O caminho
        // principal (main.js, na inicialização) já cobre o caso mais
        // comum de forma determinística; isto aqui não deixa o usuário
        // "logado" sem ter passado pela tela de definir senha.
        if (event === 'PASSWORD_RECOVERY' && window.location.hash !== '#/definir-senha') {
          window.location.hash = '#/definir-senha'
        }
      })
    },
    // Cobre o caso de uma sessão já aberta (reload de página, ou aba
    // esquecida) cujo usuário foi inativado NO MEIO da sessão — não só o
    // momento do login. Sem isso, o router ainda funcionaria com dados em
    // cache até a próxima leitura real (que o backend já bloquearia, mas a
    // UI ficaria confusa em vez de deslogar com uma mensagem clara).
    async _encerrarSeInativo() {
      if (this.profile?.ativo === false) {
        await supabase.auth.signOut()
        this.session = null
        this.profile = null
      }
    },
    async carregarPerfil() {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, nome, perfil, ativo')
        .eq('id', this.session.user.id)
        .single()
      if (!error) {
        this.profile = data
      }
    },
    async login(email, password) {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) throw error
      this.session = data.session
      await this.carregarPerfil()
      // Login normal com senha funcionando prova que essa conta já tem
      // senha própria — qualquer flag de "senha pendente" deixada por um
      // convite/recuperação anterior e nunca concluído está obsoleta.
      limparSenhaPendente()
      if (this.profile?.ativo === false) {
        // Sessão do Supabase Auth foi criada (login tecnicamente válido),
        // mas o ERP nunca deve considerar essa sessão utilizável — encerra
        // no cliente imediatamente e sinaliza com um erro claro. O backend
        // já bloqueia qualquer operação/leitura de qualquer forma; isso é
        // só para não deixar a sessão "pairando" no frontend.
        await supabase.auth.signOut()
        this.session = null
        this.profile = null
        throw new Error('Sua conta está inativa. Procure o administrador do sistema.')
      }
    },
    async logout() {
      await supabase.auth.signOut()
      this.session = null
      this.profile = null
      limparSenhaPendente()
    },
    // ETAPA AUTH-01 — seção 4 (esqueci minha senha). Não revela se o
    // e-mail existe: o próprio endpoint /recover do Supabase Auth já
    // responde de forma uniforme independente disso (comportamento padrão
    // seguro), então não há branch de erro "e-mail não encontrado" aqui.
    async solicitarRecuperacaoSenha(email) {
      const redirectTo = window.location.origin + import.meta.env.BASE_URL
      const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo })
      if (error) throw error
    },
    // ETAPA AUTH-01 — seções 3 (primeiro acesso/convite) e 4 (recuperação):
    // usado pela tela /definir-senha, que já tem uma sessão válida
    // (estabelecida pelo próprio GoTrue ao consumir o token da URL).
    async definirNovaSenha(novaSenha) {
      const { error } = await supabase.auth.updateUser({ password: novaSenha })
      if (error) throw error
      limparSenhaPendente()
      // Sessão pode ter sido re-emitida; garante que o estado local reflita
      // o usuário já com senha própria definida.
      const { data } = await supabase.auth.getSession()
      this.session = data.session
      if (this.session) {
        await this.carregarPerfil()
      }
    },
    // ETAPA AUTH-01 — seção 5 (trocar senha estando logado).
    async alterarSenha(novaSenha) {
      const { error } = await supabase.auth.updateUser({ password: novaSenha })
      if (error) throw error
    },
  },
})
