import { defineStore } from 'pinia'
import { supabase } from '../lib/supabaseClient'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    session: null,
    profile: null, // { id, nome, perfil, ativo }
    loading: true,
  }),
  getters: {
    autenticado: (state) => !!state.session,
    perfil: (state) => state.profile?.perfil ?? null,
  },
  actions: {
    async init() {
      const { data } = await supabase.auth.getSession()
      this.session = data.session
      if (this.session) {
        await this.carregarPerfil()
      }
      this.loading = false

      supabase.auth.onAuthStateChange(async (_event, session) => {
        this.session = session
        if (session) {
          await this.carregarPerfil()
        } else {
          this.profile = null
        }
      })
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
    },
    async logout() {
      await supabase.auth.signOut()
      this.session = null
      this.profile = null
    },
  },
})
