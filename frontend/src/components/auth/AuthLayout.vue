<script setup>
defineProps({
  tagline: {
    type: String,
    default: 'Gestão de manutenção, serviços e controle operacional.',
  },
})
</script>

<template>
  <div class="auth-bg">
    <div class="auth-frame">
      <aside class="auth-brand">
        <div class="brand-mark">
          <div class="brand-logo"><span></span></div>
          <div class="brand-name">Tropical Transportes</div>
        </div>

        <div class="brand-copy">
          <h1>ERP Oficina</h1>
          <p>{{ tagline }}</p>
        </div>

        <div class="brand-footer">Sistema de Gestão da Oficina &middot; acesso restrito</div>
      </aside>

      <section class="auth-panel">
        <div class="auth-card">
          <slot />
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.auth-bg {
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

.auth-frame {
  position: relative;
  width: 100%;
  max-width: 940px;
  min-height: 560px;
  border-radius: var(--shell-radius);
  background: var(--panel-shell-bg);
  backdrop-filter: var(--shell-blur);
  -webkit-backdrop-filter: var(--shell-blur);
  border: 1px solid var(--border-panel);
  box-shadow: var(--shell-shadow);
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.05fr);
  overflow: hidden;
}

/* --- lado esquerdo: branding --- */
.auth-brand {
  position: relative;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 44px 40px;
  background:
    radial-gradient(ellipse 120% 80% at 20% 0%, var(--accent-soft-bg) 0%, transparent 55%),
    radial-gradient(ellipse 90% 70% at 90% 100%, rgba(109, 40, 217, 0.25) 0%, transparent 60%);
  border-right: 1px solid var(--border-panel);
  overflow: hidden;
}
.auth-brand::before {
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(rgba(255, 255, 255, 0.06) 1px, transparent 1px);
  background-size: 22px 22px;
  mask-image: radial-gradient(ellipse 80% 60% at 30% 20%, #000 0%, transparent 70%);
  pointer-events: none;
}

.brand-mark {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
}
.brand-logo {
  width: 40px;
  height: 40px;
  border-radius: 11px;
  background: var(--accent-gradient);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  box-shadow: 0 8px 20px rgba(139, 92, 246, 0.35);
}
.brand-logo span {
  width: 13px;
  height: 13px;
  border-radius: 4px;
  background: #fff;
  display: block;
}
.brand-name {
  color: var(--text-heading);
  font-weight: 700;
  font-size: 14.5px;
  letter-spacing: -0.1px;
}

.brand-copy {
  position: relative;
  margin-top: 32px;
}
.brand-copy h1 {
  margin: 0 0 12px;
  font-size: 34px;
  font-weight: 800;
  letter-spacing: -0.7px;
  line-height: 1.15;
  color: var(--text-heading);
}
.brand-copy p {
  margin: 0;
  max-width: 34ch;
  font-size: 14.5px;
  line-height: 1.6;
  color: var(--text-secondary);
}

.brand-footer {
  position: relative;
  font-size: 12px;
  color: var(--text-faint);
}

/* --- lado direito: formulário --- */
.auth-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
}
.auth-card {
  width: 100%;
  max-width: 360px;
  display: flex;
  flex-direction: column;
}

@media (max-width: 860px) {
  .auth-bg {
    padding: 0;
  }
  .auth-frame {
    grid-template-columns: 1fr;
    max-width: 100%;
    min-height: 100vh;
    border-radius: 0;
    border: none;
  }
  .auth-brand {
    padding: 28px 24px;
    border-right: none;
    border-bottom: 1px solid var(--border-panel);
  }
  .brand-copy {
    margin-top: 18px;
  }
  .brand-copy h1 {
    font-size: 24px;
  }
  .brand-copy p {
    display: none;
  }
  .brand-footer {
    display: none;
  }
  .auth-panel {
    padding: 32px 24px 40px;
  }
}
</style>
