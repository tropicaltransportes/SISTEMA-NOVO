import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn(
    'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY não configuradas. Copie .env.example para .env e preencha com os dados do seu projeto Supabase.'
  )
}

// ETAPA AUTH-01 — causa raiz investigada e documentada em
// docs/testing/TEST_REPORT_AUTH01.md: o SDK usa flowType 'implicit' (padrão
// do @supabase/supabase-js quando não configurado — confirmado em
// node_modules/@supabase/auth-js/dist/main/GoTrueClient.js), então convite e
// recuperação de senha chegam como fragmento de hash na URL
// (#access_token=...&type=invite|recovery&...), nunca como ?code=. Isso
// colide com o hash de rota do Vue Router (createWebHashHistory) — o
// GoTrue só limpa esse hash de forma assíncrona (depois de uma chamada de
// rede), então o router pode tentar casar o hash cru como um path antes
// disso acontecer. Por isso capturamos aqui, de forma síncrona, ANTES de
// `createClient` (que dispara a inicialização assíncrona do GoTrue) ou de
// qualquer outro código rodar, qual é o tipo real desse callback — o
// `main.js` usa esse valor para decidir a navegação inicial de forma
// determinística, sem depender de timing de rede.
function parseAuthRedirectFromHash(hash) {
  if (!hash || hash === '#' || hash.startsWith('#/')) return { type: null }
  const raw = hash.startsWith('#') ? hash.slice(1) : hash
  let params
  try {
    params = new URLSearchParams(raw)
  } catch {
    return { type: null }
  }
  if (params.has('error') || params.has('error_code')) {
    return {
      type: 'error',
      errorCode: params.get('error_code') || params.get('error') || 'erro_desconhecido',
      errorDescription: params.get('error_description') || '',
    }
  }
  const tipo = params.get('type')
  if (tipo === 'invite' || tipo === 'recovery') {
    return { type: tipo }
  }
  return { type: null }
}

export const authRedirect = parseAuthRedirectFromHash(
  typeof window !== 'undefined' ? window.location.hash : ''
)

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Mantido explícito (em vez de deixar implícito no default do SDK) por
    // documentação/clareza — ver comentário acima sobre a causa raiz.
    // NÃO trocar para 'pkce': todos os links reais deste sistema (convite
    // via Admin API, recuperação via generate_link ou via
    // resetPasswordForEmail sem code_challenge) chegam no formato implicit;
    // se o cliente exigisse pkce, o GoTrue rejeitaria esses links com
    // AuthPKCEGrantCodeExchangeError.
    flowType: 'implicit',
  },
})
