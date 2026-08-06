<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import Button from 'primevue/button'

const auth = useAuthStore()
const router = useRouter()

const itensMenu = computed(() => {
  const perfil = auth.perfil
  const itens = [
    { rota: '/clientes', label: 'Clientes', icone: 'pi pi-building', perfis: null },
    { rota: '/veiculos', label: 'Veículos', icone: 'pi pi-car', perfis: null },
    { rota: '/solicitacoes', label: 'Solicitações', icone: 'pi pi-inbox', perfis: null },
    { rota: '/orcamentos', label: 'Orçamentos', icone: 'pi pi-file-edit', perfis: null },
    { rota: '/os', label: 'Ordens de Serviço', icone: 'pi pi-wrench', perfis: null },
    { rota: '/estoque/pecas', label: 'Peças', icone: 'pi pi-box', perfis: null },
    {
      rota: '/estoque/nf-entrada',
      label: 'Entrada de NF',
      icone: 'pi pi-file-import',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
    },
    {
      rota: '/vendas-avulsas',
      label: 'Venda Avulsa',
      icone: 'pi pi-shopping-cart',
      perfis: ['suporte_administrativo', 'administrador_tecnico'],
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
  ]
  return itens.filter((item) => !item.perfis || item.perfis.includes(perfil))
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

async function sair() {
  await auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="shell">
    <aside class="menu-lateral">
      <div class="marca">ERP Oficina</div>
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
    </aside>

    <div class="conteudo">
      <header class="topo">
        <div class="usuario-info">
          <strong>{{ auth.profile?.nome }}</strong>
          <span class="perfil-badge">{{ nomePerfil }}</span>
        </div>
        <Button label="Sair" icon="pi pi-sign-out" severity="secondary" text @click="sair" />
      </header>
      <main class="pagina">
        <router-view />
      </main>
    </div>
  </div>
</template>

<style scoped>
.shell {
  display: flex;
  min-height: 100vh;
}
.menu-lateral {
  width: 240px;
  background: #1f2937;
  color: white;
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
}
.marca {
  padding: 1.25rem 1rem;
  font-weight: 700;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}
nav {
  display: flex;
  flex-direction: column;
  padding: 0.5rem;
  gap: 0.25rem;
}
.item-menu {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.6rem 0.75rem;
  border-radius: 8px;
  color: #d1d5db;
  text-decoration: none;
  font-size: 0.9rem;
}
.item-menu:hover {
  background: rgba(255, 255, 255, 0.06);
}
.item-menu-ativo {
  background: #374151;
  color: white;
}
.conteudo {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.topo {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1.5rem;
  border-bottom: 1px solid #e5e7eb;
  background: white;
}
.usuario-info {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}
.perfil-badge {
  font-size: 0.75rem;
  background: #eef2ff;
  color: #4338ca;
  padding: 0.2rem 0.5rem;
  border-radius: 999px;
}
.pagina {
  padding: 1.5rem;
  flex: 1;
  overflow: auto;
}
</style>
