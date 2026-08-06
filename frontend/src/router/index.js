import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
  {
    path: '/login',
    name: 'login',
    component: () => import('../views/LoginView.vue'),
    meta: { public: true },
  },
  {
    path: '/',
    component: () => import('../layouts/AppShell.vue'),
    meta: { requiresAuth: true },
    children: [
      { path: '', redirect: '/clientes' },
      {
        path: 'clientes',
        name: 'clientes',
        component: () => import('../views/clientes/ClientesList.vue'),
      },
      {
        path: 'veiculos',
        name: 'veiculos',
        component: () => import('../views/veiculos/VeiculosList.vue'),
      },
      {
        path: 'estoque/pecas',
        name: 'pecas',
        component: () => import('../views/estoque/PecasList.vue'),
      },
      {
        path: 'estoque/nf-entrada',
        name: 'nf-entrada',
        component: () => import('../views/estoque/NFEntradaList.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        path: 'importacao',
        name: 'importacao',
        component: () => import('../views/importacao/ImportacaoInicial.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.loading) {
    await auth.init()
  }

  if (to.meta.public) {
    if (auth.autenticado && to.name === 'login') {
      return { path: '/' }
    }
    return true
  }

  if (to.meta.requiresAuth && !auth.autenticado) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.perfis && !to.meta.perfis.includes(auth.perfil)) {
    return { path: '/', query: { erro: 'sem-permissao' } }
  }

  return true
})

export default router
