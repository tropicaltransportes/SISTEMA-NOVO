import { defineStore } from 'pinia'
import { supabase } from '../lib/supabaseClient'

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

      supabase.auth.onAuthStateChange(async (_event, session) => {
        this.session = session
        if (session) {
          await this.carregarPerfil()
          await this._encerrarSeInativo()
        } else {
          this.profile = null
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
    },
  },
})
