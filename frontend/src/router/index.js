import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore, temSenhaPendente } from '../stores/auth'

const routes = [
  {
    path: '/login',
    name: 'login',
    component: () => import('../views/LoginView.vue'),
    meta: { public: true },
  },
  {
    // ETAPA AUTH-01 — "esqueci minha senha": e-mail -> resetPasswordForEmail.
    path: '/esqueci-senha',
    name: 'esqueci-senha',
    component: () => import('../views/EsqueciSenhaView.vue'),
    meta: { public: true },
  },
  {
    // ETAPA AUTH-01 — destino do convite/recuperação de senha: exige uma
    // sessão (o GoTrue já autentica ao consumir o token da URL), mas NÃO é
    // marcada como `public` nem tem `requiresAuth` no sentido normal — tem
    // guarda própria em beforeEach (precisa apenas de sessão, não de perfil
    // ativo/carregado, já que o usuário pode ainda não ter senha definida).
    path: '/definir-senha',
    name: 'definir-senha',
    component: () => import('../views/DefinirSenhaView.vue'),
    meta: { public: true, semSessaoRedirecionaLogin: true },
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
        path: 'clientes/:id',
        name: 'cliente-detalhe',
        component: () => import('../views/clientes/ClienteDetalhe.vue'),
      },
      {
        path: 'veiculos',
        name: 'veiculos',
        component: () => import('../views/veiculos/VeiculosList.vue'),
      },
      {
        // ETAPA 6 (P1-C) — item 7 (CAD-012): histórico do veículo.
        path: 'veiculos/:id/historico',
        name: 'veiculo-historico',
        component: () => import('../views/veiculos/VeiculoHistorico.vue'),
      },
      {
        path: 'estoque/pecas',
        name: 'pecas',
        component: () => import('../views/estoque/PecasList.vue'),
      },
      {
        // FEATURE-SERVICOS-01 — catálogo de serviços/mão de obra.
        path: 'servicos',
        name: 'servicos',
        component: () => import('../views/servicos/ServicosList.vue'),
      },
      {
        path: 'estoque/nf-entrada',
        name: 'nf-entrada',
        component: () => import('../views/estoque/NFEntradaList.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        path: 'estoque/ajustes',
        name: 'estoque-ajustes',
        component: () => import('../views/estoque/AjustesEstoqueList.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        path: 'importacao',
        name: 'importacao',
        component: () => import('../views/importacao/ImportacaoInicial.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        path: 'solicitacoes',
        name: 'solicitacoes',
        component: () => import('../views/solicitacoes/SolicitacoesList.vue'),
      },
      {
        path: 'orcamentos',
        name: 'orcamentos',
        component: () => import('../views/orcamentos/OrcamentosList.vue'),
      },
      {
        // ETAPA 6 (P1-C) — item 1 (ORC-013/DOC-001/DOC-002): PDF de orçamento.
        path: 'orcamentos/:id/pdf',
        name: 'orcamento-pdf',
        component: () => import('../views/orcamentos/OrcamentoPdf.vue'),
      },
      {
        path: 'os',
        name: 'os',
        component: () => import('../views/os/OrdensServicoList.vue'),
      },
      {
        path: 'os/:id',
        name: 'os-detalhe',
        component: () => import('../views/os/OrdemServicoDetalhe.vue'),
      },
      {
        // ETAPA 6 (P1-C) — item 4 (CON-005/CON-006/DOC-003): relatório de encerramento.
        path: 'os/:id/relatorio-encerramento',
        name: 'os-relatorio-encerramento',
        component: () => import('../views/os/OsRelatorioEncerramento.vue'),
      },
      {
        // ETAPA 6 (P1-C) — item 5 (GAR-007): relatório de garantia.
        path: 'os/:id/relatorio-garantia',
        name: 'os-relatorio-garantia',
        component: () => import('../views/os/OsRelatorioGarantia.vue'),
      },
      {
        // ETAPA DOC-OS-FINAL-01: documento comercial de conclusão da OS
        // (distinto do relatório de encerramento acima, que é interno).
        path: 'os/:id/documento',
        name: 'os-documento-final',
        component: () => import('../views/os/OsDocumentoFinal.vue'),
      },
      {
        path: 'vendas-avulsas',
        name: 'vendas-avulsas',
        component: () => import('../views/vendas/VendaAvulsaView.vue'),
        meta: { perfis: ['suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        path: 'dashboard',
        name: 'dashboard',
        component: () => import('../views/dashboard/DashboardView.vue'),
        meta: { perfis: ['encarregado', 'suporte_administrativo', 'diretoria', 'administrador_tecnico'] },
      },
      {
        path: 'financeiro/cobrancas',
        name: 'financeiro-cobrancas',
        component: () => import('../views/financeiro/CobrancasList.vue'),
        meta: { perfis: ['encarregado', 'suporte_administrativo', 'diretoria', 'administrador_tecnico'] },
      },
      {
        path: 'admin/checklist',
        name: 'admin-checklist',
        component: () => import('../views/admin/ChecklistTemplatesList.vue'),
        meta: { perfis: ['encarregado', 'administrador_tecnico'] },
      },
      {
        path: 'admin/faixas-acrescimo',
        name: 'admin-faixas-acrescimo',
        component: () => import('../views/admin/FaixasAcrescimoList.vue'),
        meta: { perfis: ['administrador_tecnico'] },
      },
      {
        // ETAPA 8 (RC2) — seção 2: bootstrap/configuração inicial.
        path: 'admin/status-configuracao',
        name: 'admin-status-configuracao',
        component: () => import('../views/admin/StatusConfiguracaoView.vue'),
        meta: { perfis: ['encarregado', 'suporte_administrativo', 'administrador_tecnico'] },
      },
      {
        // ETAPA AUTH-01 — trocar senha estando logado (menu do usuário).
        path: 'perfil/alterar-senha',
        name: 'perfil-alterar-senha',
        component: () => import('../views/perfil/AlterarSenhaView.vue'),
      },
    ],
  },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.loading) {
    await auth.init()
  }

  // ETAPA AUTH-01 — achado real de teste: sem isso, um convite/recuperação
  // abandonado antes de confirmar a senha (aba nova, reload) deixa a
  // sessão já autenticada "solta" no localStorage, e o usuário cairia no
  // ERP sem nunca ter definido senha própria. Vale para qualquer
  // navegação, em qualquer aba — só sai desse estado definindo a senha de
  // verdade (ou saindo/entrando de novo com uma senha que já funcione).
  if (to.name !== 'definir-senha' && to.name !== 'login' && auth.session && temSenhaPendente()) {
    return { name: 'definir-senha' }
  }

  if (to.meta.public) {
    // ETAPA AUTH-01 — /definir-senha é pública no sentido de não exigir
    // perfil/permissão, mas precisa de uma sessão (o GoTrue já autentica
    // sozinho ao consumir o token de convite/recuperação da URL, ver
    // main.js). Sem sessão nenhuma, não há o que definir — manda pro login.
    if (to.meta.semSessaoRedirecionaLogin && !auth.session) {
      return { name: 'login' }
    }
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
