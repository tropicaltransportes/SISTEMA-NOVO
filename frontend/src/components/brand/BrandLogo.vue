<script setup>
// ETAPA BRAND-01 — componente central de logo. Nenhuma tela deve mais
// desenhar a marca via CSS/monograma provisório: toda exibição da logo
// Tropical passa por aqui, escolhendo entre os PNGs oficiais fornecidos
// pelo dono do projeto (frontend/src/assets/brand/), preservados como
// estão (sem redesenho, sem filtro CSS "fabricando" variante — item 18 da
// instrução). Ver frontend/src/assets/brand/README.md para o mapeamento
// completo Prancheta -> arquivo.
import { computed } from 'vue'
import symbolLight from '../../assets/brand/tropical-symbol-light.png'
import symbolDark from '../../assets/brand/tropical-symbol-dark.png'
import horizontalLight from '../../assets/brand/tropical-logo-horizontal-light.png'
import horizontalDark from '../../assets/brand/tropical-logo-horizontal-dark.png'
import verticalLight from '../../assets/brand/tropical-logo-vertical-light.png'
import verticalDark from '../../assets/brand/tropical-logo-vertical-dark.png'

const props = defineProps({
  variant: {
    type: String,
    default: 'horizontal',
    validator: (v) => ['symbol', 'horizontal', 'vertical'].includes(v),
  },
  surface: {
    type: String,
    default: 'dark',
    validator: (v) => ['light', 'dark'].includes(v),
  },
  // altura do logo (largura é livre, a imagem já vem com aspect-ratio
  // correto do arquivo oficial — nunca esticada/deformada, ver estilo
  // abaixo: width auto + object-fit: contain).
  size: {
    type: [String, Number],
    default: 40,
  },
})

// item 19 da instrução: só o asset realmente usado entra no bundle da tela
// que importa BrandLogo — os outros 5 ficam como chunks separados (imports
// estáticos do Vite, um por variant×surface), nunca os 6 juntos numa tela só.
const ASSETS = {
  symbol: { light: symbolLight, dark: symbolDark },
  horizontal: { light: horizontalLight, dark: horizontalDark },
  vertical: { light: verticalLight, dark: verticalDark },
}

const src = computed(() => ASSETS[props.variant][props.surface])

const sizePx = computed(() => (typeof props.size === 'number' ? `${props.size}px` : props.size))

// símbolo é quadrado (1:1) -- largura = altura. horizontal/vertical mantêm
// a proporção real do PNG por conta própria (height fixo, width auto).
const isSymbol = computed(() => props.variant === 'symbol')
</script>

<template>
  <img
    :src="src"
    alt="Tropical Transportes"
    class="brand-logo"
    :class="[`brand-logo--${variant}`]"
    :style="{ height: sizePx, width: isSymbol ? sizePx : 'auto' }"
  />
</template>

<style scoped>
.brand-logo {
  display: block;
  object-fit: contain;
  max-width: 100%;
}
</style>
