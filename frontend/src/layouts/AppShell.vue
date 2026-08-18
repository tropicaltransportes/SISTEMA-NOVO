<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import Button from 'primevue/button'
import BrandLogo from '../components/brand/BrandLogo.vue'

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
          <!-- ETAPA BRAND-01 — logo horizontal oficial expandida (já traz
               "Tropical TRANSPORTES" na própria imagem, por isso só
               "ERP Oficina" é adicionado como legenda, tipograficamente
               separada — item 5/7/18 da instrução: nada de monograma
               desenhado em CSS). -->
          <div class="marca-expandida">
            <BrandLogo variant="horizontal" surface="dark" :size="22" />
            <span class="marca-sub">ERP Oficina</span>
          </div>
          <!-- sidebar recolhida (item 7): só o símbolo oficial -->
          <BrandLogo variant="symbol" surface="dark" :size="30" class="marca-simbolo" />
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
  padding: 6px 10px 22px;
}
.marca-expandida {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 5px;
}
.marca-simbolo {
  display: none;
}
.marca-sub {
  color: var(--accent-text);
  font-weight: 600;
  font-size: 11px;
  letter-spacing: 0.3px;
  text-transform: uppercase;
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
  .marca-expandida,
  .item-menu span,
  .sidebar-footer-texto {
    display: none;
  }
  .marca-simbolo {
    display: block;
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

/* Achado incidental (BRAND-01, verificação de impressão — item 21): rotas
   de documento (orcamento-pdf, os-relatorio-encerramento/garantia,
   veiculo-historico) são filhas do AppShell, então sidebar/topbar
   apareciam na impressão real — cada documento só reseta o próprio
   .documento-papel, nunca escondia o chrome do ERP ao redor. Nenhum desses
   4 componentes tem como alcançar estes seletores (são do AppShell, fora
   do escopo do <style scoped> deles). Corrigido aqui, uma vez, para todos. */
@media print {
  .page-bg {
    padding: 0;
    background: none;
    display: block;
    min-height: 0;
  }
  .shell {
    display: block;
    height: auto;
    max-width: none;
    border: none;
    border-radius: 0;
    box-shadow: none;
    background: none;
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }
  .sidebar,
  .topbar {
    display: none !important;
  }
  .main-col {
    display: block;
  }
  .pagina {
    padding: 0;
    overflow: visible;
  }
}
</style>

<!-- BUG-PDF-EXPORT-02 (item 5/8) — bloco SEM `scoped` de propósito. O banner
     "Invalid PrimeUI License" (`#p-license-host`, injetado direto em
     document.body pelo license-manager do PrimeVue, fora de qualquer árvore
     Vue) e o Toast (`.p-toast`, declarado em App.vue e teleportado pra
     document.body) nunca recebem o atributo `data-v-*` de um `<style
     scoped>` daqui — não têm como ser alcançados por CSS com escopo, só por
     regra global. Isso esconde os dois SÓ na impressão (mesma categoria de
     já esconder sidebar/topbar acima); não desliga nem mascara a licença do
     PrimeVue na tela do app — decisão explícita de não mexer nisso nesta
     tarefa. -->
<style>
@media print {
  #p-license-host,
  .p-toast {
    display: none !important;
  }
}
</style>
