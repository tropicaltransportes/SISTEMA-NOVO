<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import Button from 'primevue/button'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const itensMenu = computed(() => {
  const perfil = auth.perfil
  const itens = [
    {
      rota: '/dashboard',
      label: 'Dashboard',
      icone: 'pi pi-chart-bar',
      perfis: ['encarregado', 'suporte_administrativo', 'diretoria', 'administrador_tecnico'],
    },
    { rota: '/clientes', label: 'Clientes', icone: 'pi pi-building', perfis: null },
    { rota: '/veiculos', label: 'Veículos', icone: 'pi pi-car', perfis: null },
    { rota: '/solicitacoes', label: 'Solicitações', icone: 'pi pi-inbox', perfis: null },
    { rota: '/orcamentos', label: 'Orçamentos', icone: 'pi pi-file-edit', perfis: null },
    { rota: '/os', label: 'Ordens de Serviço', icone: 'pi pi-wrench', perfis: null },
    { rota: '/estoque/pecas', label: 'Peças', icone: 'pi pi-box', perfis: null },
    { rota: '/servicos', label: 'Serviços', icone: 'pi pi-cog', perfis: null },
    {
      rota: '/estoque/nf-entrada',
      label: 'Entrada de NF',
      icone: 'pi pi-file-import',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
    },
    {
      rota: '/estoque/ajustes',
      label: 'Ajustes de Estoque',
      icone: 'pi pi-sliders-h',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
    },
    {
      rota: '/vendas-avulsas',
      label: 'Venda Avulsa',
      icone: 'pi pi-shopping-cart',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
    },
    {
      rota: '/financeiro/cobrancas',
      label: 'Financeiro',
      icone: 'pi pi-wallet',
      perfis: ['encarregado', 'suporte_administrativo', 'diretoria', 'administrador_tecnico'],
    },
    {
      rota: '/importacao',
      label: 'Importação Inicial',
      icone: 'pi pi-upload',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
    },
    {
      rota: '/admin/checklist',
      label: 'Checklists Técnicos',
      icone: 'pi pi-check-square',
      perfis: ['encarregado', 'administrador_tecnico'],
    },
    {
      rota: '/admin/faixas-acrescimo',
      label: 'Faixas de Acréscimo',
      icone: 'pi pi-percentage',
      perfis: ['administrador_tecnico'],
    },
    {
      rota: '/admin/status-configuracao',
      label: 'Configuração Inicial',
      icone: 'pi pi-verified',
      perfis: ['encarregado', 'suporte_administrativo', 'administrador_tecnico'],
    },
  ]
  return itens.filter((item) => !item.perfis || item.perfis.includes(perfil))
})

const iniciaisUsuario = computed(() => {
  const nome = auth.profile?.nome?.trim()
  if (!nome) return ''
  const partes = nome.split(/\s+/)
  const primeira = partes[0]?.[0] ?? ''
  const ultima = partes.length > 1 ? partes[partes.length - 1][0] : ''
  return (primeira + ultima).toUpperCase()
})

const nomePerfil = computed(() => {
  const rotulos = {
    executor: 'Executor',
    encarregado: 'Encarregado',
    suporte_administrativo: 'Suporte Administrativo',
    diretoria: 'Diretoria',
    administrador_tecnico: 'Administrador Técnico',
  }
  return rotulos[auth.perfil] ?? auth.perfil
})

const tituloPagina = computed(() => {
  const rotulos = {
    dashboard: 'Dashboard',
    clientes: 'Clientes',
    'cliente-detalhe': 'Detalhe do Cliente',
    veiculos: 'Veículos',
    solicitacoes: 'Solicitações',
    orcamentos: 'Orçamentos',
    os: 'Ordens de Serviço',
    'os-detalhe': 'Detalhe da OS',
    pecas: 'Peças',
    servicos: 'Serviços',
    'nf-entrada': 'Entrada de NF',
    'estoque-ajustes': 'Ajustes de Estoque',
    'vendas-avulsas': 'Venda Avulsa',
    'financeiro-cobrancas': 'Financeiro',
    importacao: 'Importação Inicial',
    'admin-checklist': 'Checklists Técnicos',
    'admin-faixas-acrescimo': 'Faixas de Acréscimo',
    'admin-status-configuracao': 'Configuração Inicial',
  }
  return rotulos[route.name] ?? ''
})

async function sair() {
  await auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="page-bg">
    <div class="shell">
      <aside class="sidebar">
        <div class="marca">
          <div class="marca-logo"><span></span></div>
          <div class="marca-texto">Tropical Transportes<br /><span class="marca-sub">ERP</span></div>
        </div>

        <nav>
          <router-link
            v-for="item in itensMenu"
            :key="item.rota"
            :to="item.rota"
            class="item-menu"
            active-class="item-menu-ativo"
          >
            <i :class="item.icone"></i>
            <span>{{ item.label }}</span>
          </router-link>
        </nav>

        <div class="sidebar-footer">
          <div class="avatar">{{ iniciaisUsuario }}</div>
          <div class="sidebar-footer-texto">
            <div class="user-nome">{{ auth.profile?.nome }}</div>
            <div class="user-perfil">{{ nomePerfil }}</div>
          </div>
        </div>
      </aside>

      <div class="main-col">
        <header class="topbar">
          <div class="titulo-pagina">{{ tituloPagina }}</div>
          <div class="topbar-acoes">
            <Button
              label="Alterar senha"
              icon="pi pi-lock"
              severity="secondary"
              text
              @click="router.push('/perfil/alterar-senha')"
            />
            <Button label="Sair" icon="pi pi-sign-out" severity="secondary" text @click="sair" />
          </div>
        </header>
        <main class="pagina">
          <router-view />
        </main>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-bg {
  position: relative;
  width: 100%;
  min-height: 100vh;
  background: var(--bg-page-gradient), var(--bg-page);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 28px;
  box-sizing: border-box;
}

.shell {
  position: relative;
  width: 100%;
  max-width: 1560px;
  height: calc(100vh - 56px);
  border-radius: var(--shell-radius);
  background: var(--panel-shell-bg);
  backdrop-filter: var(--shell-blur);
  -webkit-backdrop-filter: var(--shell-blur);
  border: 1px solid var(--border-panel);
  box-shadow: var(--shell-shadow);
  display: flex;
  overflow: hidden;
}

.sidebar {
  flex-shrink: 0;
  width: 252px;
  display: flex;
  flex-direction: column;
  padding: 22px 14px;
}

.marca {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 10px 22px;
}
.marca-logo {
  width: 32px;
  height: 32px;
  border-radius: 9px;
  background: var(--accent-gradient);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.marca-logo span {
  width: 11px;
  height: 11px;
  border-radius: 3px;
  background: #fff;
  display: block;
}
.marca-texto {
  color: var(--text-heading);
  font-weight: 700;
  font-size: 14px;
  letter-spacing: -0.2px;
  line-height: 1.2;
}
.marca-sub {
  color: var(--accent-text);
  font-weight: 600;
  font-size: 11.5px;
}

nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-top: 6px;
  overflow-y: auto;
}
.item-menu {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 11px;
  border-radius: 9px;
  color: var(--text-muted-2);
  text-decoration: none;
  font-size: 13px;
  font-weight: 550;
}
.item-menu i {
  font-size: 14px;
  color: inherit;
  flex-shrink: 0;
}
.item-menu:hover {
  background: rgba(255, 255, 255, 0.06);
}
.item-menu-ativo {
  background: var(--accent-soft-bg);
  color: var(--text-heading);
}

.sidebar-footer {
  margin-top: auto;
  padding-top: 14px;
  border-top: 1px solid var(--border-footer);
  display: flex;
  align-items: center;
  gap: 10px;
}
.avatar {
  width: 30px;
  height: 30px;
  border-radius: 999px;
  background: var(--accent-gradient);
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.2px;
}
.sidebar-footer-texto {
  min-width: 0;
}
.user-nome {
  color: var(--text-heading);
  font-size: 12.5px;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.user-perfil {
  color: var(--text-faint);
  font-size: 11px;
}

.main-col {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}
.topbar {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 28px;
}
.titulo-pagina {
  color: var(--text-heading);
  font-size: 19px;
  font-weight: 700;
  letter-spacing: -0.3px;
}
.topbar-acoes {
  display: flex;
  align-items: center;
  gap: 4px;
}
.pagina {
  flex: 1;
  padding: 0 28px 32px;
  overflow: auto;
}

/* ETAPA UX-DASHBOARD-01 — adapta o shell em notebooks/telas menores sem
   alterar navegação/permissões, só a apresentação (item 14 do roteiro). */
@media (max-width: 1280px) {
  .page-bg {
    padding: 14px;
  }
  .shell {
    height: calc(100vh - 28px);
  }
  .sidebar {
    width: 76px;
    padding: 18px 10px;
  }
  .marca-texto,
  .item-menu span,
  .sidebar-footer-texto {
    display: none;
  }
  .marca {
    justify-content: center;
    padding: 6px 0 22px;
  }
  .item-menu {
    justify-content: center;
    padding: 10px;
  }
  .sidebar-footer {
    justify-content: center;
  }
  .topbar {
    padding: 16px 20px;
  }
  .pagina {
    padding: 0 20px 24px;
  }
}

@media (max-width: 760px) {
  .topbar {
    flex-wrap: wrap;
    gap: 10px;
  }
}
</style>
