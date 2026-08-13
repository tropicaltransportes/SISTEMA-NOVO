# TEST REPORT — ETAPA AUTH-01 — Ciclo de Autenticação (Produção)

Data: 2026-08-13. Continuação de `TEST_REPORT_PROD01.md` (preservado
intacto). Objetivo desta rodada: corrigir e homologar o ciclo completo de
autenticação em **PRODUÇÃO real** — convite, "esqueci minha senha", troca
de senha logado — depois que o administrador técnico real tentou usar o
link de convite original e caiu num erro
(`access_denied&error_code=otp_expired`, redirecionando para
`localhost:3000`). Nenhuma outra funcionalidade do ERP foi criada ou
alterada nesta etapa.

**AMBIENTE = PRODUÇÃO | PROJECT_REF = `wtxbodhqyasdlmyoyjur`.** O projeto
DEV/QA e o projeto sem relação ("YNAB COVER") não foram tocados em nenhum
momento (refs omitidos deste documento público por princípio de menor
exposição — ver `docs/ENVIRONMENTS.md`, não publicado, para os valores
reais). Toda chamada de CLI que afetou produção usou `--project-ref`
explícito do projeto de produção.

**Nota sobre execução**: os comandos de CLI que alteram configuração de
produção (`supabase config push`) foram bloqueados para execução direta
pelo classificador de auto-modo desta sessão de trabalho (tanto para mim
quanto para uma tentativa do dono via ferramenta equivalente) — ele deixou
passar rodando diretamente no terminal dele. As três rodadas de
`config push` desta etapa (a original, uma correção de efeito colateral, e
uma segunda correção depois do achado crítico da seção "INCIDENTE" abaixo)
foram todas executadas pelo dono do projeto, fora do classificador; toda a
edição do `supabase/config.toml`, toda a investigação/reprodução da causa
raiz, toda a implementação de frontend, todos os testes A–G e a rotação de
senha foram executados nesta sessão via Admin API (curl) e Browser real
contra o site público, sem exceção.

---

## CAUSA DO ERRO DO CONVITE (real, reproduzida)

Reproduzida contra produção antes de qualquer alteração, gerando um link
real via Admin API (`POST /auth/v1/admin/generate_link`, `type: "recovery"`,
para o e-mail do administrador) e seguindo o redirect de verdade:

1. **`site_url` de produção ainda era `http://127.0.0.1:3000`** (valor
   padrão de dev local, nunca atualizado desde o provisionamento em
   PROD-01). Confirmado dois níveis: o `generate_link` retornou
   `"redirect_to": "http://localhost:3000"`, e seguir o `action_link` real
   (`GET` no endpoint `/auth/v1/verify` do GoTrue) devolveu
   `HTTP 303, Location: http://localhost:3000/#access_token=...`. Isso
   bate exatamente com o que o administrador relatou.
2. **O token chega como fragmento de hash da URL** (`#access_token=...&type=recovery&refresh_token=...`),
   nunca como `?code=`. Confirmado em duas frentes: (a) o `Location` real
   capturado acima tinha `HAS HASH FRAGMENT: true` e `QUERY PARAM KEYS: []`;
   (b) `node_modules/@supabase/auth-js/dist/main/GoTrueClient.js` linha 24
   mostra que o SDK (`@supabase/supabase-js@2.109.0`) usa `flowType: 'implicit'`
   por padrão, e `frontend/src/lib/supabaseClient.js` nunca sobrescrevia
   isso. Convites (sempre disparados via Admin API, nunca pelo cliente)
   **sempre** vão vir nesse formato implícito, independente de qualquer
   configuração de `flowType` no frontend — não dá pra evitar trocando pra
   PKCE (testado: o GoTrue rejeitaria o link implícito com
   `AuthPKCEGrantCodeExchangeError` se o cliente exigisse PKCE).
3. **Esse formato de hash colide com o hash de rota do Vue Router**
   (`createWebHashHistory()`, dono do mesmo `#` da URL). Analisando o
   código-fonte do GoTrue (`_getSessionFromURL`, linha ~3167): o hash só é
   limpo (`window.location.hash = ''`) **depois de uma chamada de rede
   assíncrona** (`_getUser`) no caminho de sucesso, e **nunca é limpo no
   caminho de erro** (ex.: `otp_expired`). Sem tratamento, o Vue Router
   tentaria casar o hash cru do token como se fosse um path de rota — não
   existe rota catch-all em `router/index.js` — resultando em tela em
   branco antes do GoTrue terminar de processar, e (no caminho de erro)
   permanentemente.
4. **Nenhum tratamento do evento `PASSWORD_RECOVERY`/`type=invite`** em
   `frontend/src/stores/auth.js`: mesmo que os itens 1–3 fossem corrigidos,
   o usuário seria autenticado silenciosamente e cairia direto no
   dashboard sem nunca ter definido senha própria — confirmado que o GoTrue
   só emite `PASSWORD_RECOVERY` para `type=recovery`; para `type=invite`
   emite `SIGNED_IN` genérico (linha 1573/1990 do GoTrueClient.js), então a
   distinção precisa ser feita a partir do parâmetro `type` da própria URL,
   não de um evento dedicado.

**Causa raiz = combinação dos 4 itens acima**, não um único bug isolado.

---

## CORREÇÃO

### Configuração de produção (`supabase/config.toml`, aplicada e revertida)

- `site_url` → `https://tropicaltransportes.github.io/SISTEMA-NOVO/`.
- `additional_redirect_urls` → `["https://tropicaltransportes.github.io/SISTEMA-NOVO/"]`.
- `[auth] enable_signup` → `false`. **Decisão de segurança desta etapa**:
  a tela de login já diz "Acesso restrito a usuários convidados"; este ERP
  não tem (nem deve ter) cadastro público aberto — usuários só entram por
  convite do administrador. Confirmado via `GET /auth/v1/settings` que
  isso mapeia corretamente para `"disable_signup": true` (bloqueia só
  self-service signup, não login/recovery de quem já existe).
- `git diff` em `supabase/config.toml` está **vazio** ao final desta etapa
  (arquivo revertido para os valores de dev local depois de confirmado que
  a config de produção real está aplicada só no projeto remoto).

### INCIDENTE — `[auth.email] enable_signup=false` desligou login por e-mail inteiro

Achado real e sério durante o TESTE B, registrado aqui com transparência:

- **Causa**: ao aplicar a mesma decisão de "desabilitar signup" também em
  `[auth.email] enable_signup` (por simetria com `[auth]`, presumindo que
  fosse um filtro fino "só bloqueia cadastro novo via e-mail"), o valor
  real aplicado no GoTrue foi diferente do que o nome/comentário da CLI
  sugere: `[auth.email] enable_signup=false` mapeia para
  `"external": { "email": false }` no GoTrue — o **interruptor mestre do
  provider "email" inteiro**, não um filtro fino de signup.
- **Detecção**: ao testar TESTE B (esqueci senha) pela UI real, a chamada
  de `resetPasswordForEmail` voltou com erro. Investigação imediata via
  `GET https://wtxbodhqyasdlmyoyjur.supabase.co/auth/v1/settings` confirmou
  `"external": {"email": false}`. Testes diretos confirmaram o alcance
  real do problema:
  - `POST /auth/v1/token?grant_type=password` → `422 email_provider_disabled`
    ("Email logins are disabled") — **login normal por e-mail/senha estava
    quebrado para qualquer usuário, incluindo o administrador real**.
  - `POST /auth/v1/recover` → `400 email_provider_disabled`.
  - Confirmado que **não afetava** o Admin API (`generate_link`,
    `admin/users`) nem o endpoint `/auth/v1/verify` (consumo de token de
    convite/recuperação) — o TESTE A (convite), que já tinha rodado antes
    desse incidente ser identificado, completou com sucesso mesmo com essa
    config quebrada no ar, porque não depende do provider "email" da mesma
    forma.
- **Correção**: revertido só `[auth.email] enable_signup` para `true`
  (comentário extenso deixado no `config.toml` documentando o porquê, para
  não repetir o erro). `[auth] enable_signup=false` (o filtro certo,
  confirmado via `disable_signup: true` nas settings) foi mantido — cobre
  sozinho o objetivo de segurança de bloquear cadastro público.
- **Tempo até resolver**: identificado durante o próprio TESTE B desta
  sessão de trabalho e corrigido (novo `config push`, aplicado pelo dono
  do projeto) na sequência imediata, dentro da mesma sessão — sem
  intervalo de dias/horas, mas com uma janela real (minutos) em que login
  por e-mail/senha ficou indisponível em produção, incluindo para o
  administrador real. Nenhum outro usuário real dependia do sistema nesse
  intervalo (UAT ainda não executado, conforme PROD-01).
- **Verificação pós-correção** (por mim, além da confirmação do dono):
  `GET /auth/v1/settings` → `"external": {"email": true}`,
  `"disable_signup": true`; `POST /auth/v1/token?grant_type=password` com
  credenciais de teste válidas → `200`, `access_token` presente.

### Frontend (`frontend/src/`)

- **`main.js`** — bootstrap sequenciado: `auth.init()` roda e o hash é
  normalizado **antes** do router ser instalado (`app.use(router)`), então
  o router nunca chega a ver o hash cru do token de convite/recuperação —
  elimina a corrida descrita no item 3 da causa raiz, não só mascara o
  sintoma.
- **`supabaseClient.js`** — captura síncrona do tipo de callback de auth
  (`invite`/`recovery`/`error`) direto do hash cru da URL, antes de
  qualquer coisa (GoTrue incluído) consumir/limpar esse hash. `flowType`
  mantido explicitamente `'implicit'` (documentado o porquê — trocar para
  `'pkce'` quebraria os links reais deste sistema).
- **Telas novas**: `DefinirSenhaView.vue` (convite e recuperação, com
  textos e comportamento pós-sucesso diferentes para cada caso — convite
  entra direto no ERP, recuperação desloga e manda pro login);
  `EsqueciSenhaView.vue`; `views/perfil/AlterarSenhaView.vue` (trocar
  senha logado, acessível pelo botão "Alterar senha" no topo do
  `AppShell.vue`).
- **`LoginView.vue`** — link "Esqueci minha senha", mensagem amigável para
  link inválido/expirado (`?erroAuth=otp_expired` etc.), mensagem de
  sucesso pós-recuperação (`?senhaRedefinida=1`).
- **`stores/auth.js`** — `solicitarRecuperacaoSenha`, `definirNovaSenha`,
  `alterarSenha` (100% Supabase Auth nativo via `updateUser`/
  `resetPasswordForEmail`, nenhuma coluna de senha em tabela `public`);
  rede de segurança para o evento `PASSWORD_RECOVERY` chegar com o app já
  rodando.
- **Achado de teste real corrigido em uma segunda rodada de código**: o
  gate para `/definir-senha` baseado só no boot da página não protegia um
  usuário que abrisse uma aba nova (ou recarregasse) antes de confirmar a
  senha — a sessão já ficava válida no `localStorage` compartilhado entre
  abas, e ele caía direto no ERP sem nunca ter definido senha própria.
  Corrigido com uma flag persistida em `localStorage`
  (`auth01-senha-pendente`), checada em **todo** guard de navegação do
  router (não só no boot), limpa ao definir senha de verdade ou em
  logout/login normal.

---

## CONVITE (TESTE A) — PASSOU

Executado de ponta a ponta contra produção real, com conta de teste
descartável (`smoke.auth01@tropicaltransportes.com.br`, perfil `executor`
padrão do trigger `handle_new_user`):

1. `generate_link type=invite` real (Admin API) → `action_link` com token
   real, mesmo mecanismo que um convite por e-mail de verdade usaria.
2. Aberto no Browser real contra `https://tropicaltransportes.github.io/SISTEMA-NOVO/`:
   landou em `#/definir-senha`, sem tela em branco, 0 erros de console
   (confirmado via rede: todos os assets carregados com `200`).
3. Senha definida pela UI real (`updateUser`) → redirecionado
   automaticamente para `/` → `#/clientes`, já dentro do ERP.
4. Reconfirmado numa aba nova (sessão via `localStorage` compartilhado):
   não foi mais pedida a senha de novo (flag `auth01-senha-pendente`
   corretamente limpa).

**TESTE A = PASSOU**, com link real e válido (`generate_link`).

---

## RECUPERAÇÃO (TESTE B) — PASSOU

Dois caminhos exercidos e documentados:

1. **UI real**: `/esqueci-senha` → e-mail informado →
   `resetPasswordForEmail` disparado pela tela de verdade → tela de
   sucesso ("Se houver uma conta cadastrada... enviamos um link"). Isso
   foi o que primeiro revelou o INCIDENTE acima (erro `email_provider_disabled`
   antes da correção); depois da correção, o mesmo fluxo completou com
   `200`.
2. **Conclusão do fluxo via `generate_link type=recovery`** (mesmo
   mecanismo/token real que o Supabase geraria para o e-mail de verdade,
   sem precisar de acesso a caixa de e-mail real): aberto no Browser real
   → landou em `#/definir-senha` com o texto específico de recuperação
   ("Defina sua nova senha") → nova senha definida → **deslogado
   automaticamente e redirecionado para `/login?senhaRedefinida=1`**,
   mensagem de sucesso exibida ("Senha redefinida com sucesso. Faça login
   com sua nova senha.") → login com a nova senha → `200`, entrou no ERP.

**TESTE B = PASSOU.**

---

## TROCA DE SENHA (TESTE D) — PASSOU

Logado como a conta de teste (senha definida no TESTE B), navegado até
`/perfil/alterar-senha` (acessível pelo botão "Alterar senha" no topo do
`AppShell`), nova senha + confirmação enviadas via `updateUser` →
toast "Senha alterada com sucesso" confirmado no DOM. Confirmado por
chamada direta à API: senha antiga (do TESTE B) → `400 invalid_credentials`;
senha nova (do TESTE D) → `200`, login funciona.

**TESTE D = PASSOU.**

---

## TESTES C, E, F, G

| Teste | Descrição | Resultado |
|---|---|---|
| C | Senha anterior ao TESTE B deixa de funcionar | **PASSOU** — `POST /auth/v1/token?grant_type=password` com a senha do TESTE A → `400 invalid_credentials`, depois que B trocou a senha. |
| E | Link inválido/expirado (mesmo link do TESTE A, reutilizado) | **PASSOU** — landou em `#/login?erroAuth=otp_expired`, mensagem amigável exibida ("Esse link expirou ou já foi usado..."), 0 tela em branco. |
| F | `profiles.ativo=false` continua sem acessar dados mesmo com credenciais válidas (regra já existente, só reconfirmada) | **PASSOU** — `POST /auth/v1/token?grant_type=password` com credenciais válidas de uma conta desativada → `200` (GoTrue não checa `profiles.ativo`, comportamento arquitetural já documentado em BR-028/AUT-007), mas `GET /rest/v1/clientes` com o token dessa sessão → `200` com corpo `[]` (RLS bloqueia). Nenhuma mudança de código feita aqui — só reconfirmado. |
| G | Nenhum redirecionamento para `localhost`/DEV-QA em nenhum momento | **PASSOU** — toda URL observada durante A, B, D, E ficou em `https://tropicaltransportes.github.io/SISTEMA-NOVO/...`; `generate_link` (antes e depois da correção de config) sempre retornou `redirect_to` apontando pra essa URL de produção depois da correção da seção 2; bundle publicado (`assets/supabaseClient-Dh4Js_sG.js`) contém a referência do projeto de produção e **não** contém a do projeto DEV/QA em nenhum momento. |

Conta de teste `smoke.auth01@tropicaltransportes.com.br` **desativada
(`profiles.ativo=false`) ao final** desta rodada — preservada como
evidência, não deletada fisicamente (mesmo padrão de PROD-01/BR-043).

---

## ROTAÇÃO DE SENHA DO ADMINISTRADOR (seção 6)

A senha temporária do administrador real (definida administrativamente em
PROD-01, considerada comprometida) foi **rotacionada para um valor
aleatório gerado com `crypto.randomBytes` do Node, usado uma única vez
diretamente na chamada `PUT /auth/v1/admin/users/{id}` e imediatamente
descartado** — nunca impresso, nunca logado, nunca escrito em nenhum
arquivo. Confirmado por `updated_at` do usuário refletindo o horário exato
da rotação. O administrador real agora **precisa usar o fluxo de "esqueci
minha senha"** (testado e funcionando, TESTE B) para definir sua própria
senha definitiva — não recebe uma senha pronta de novo.

---

## FRONTEND / DEPLOY (seção 8)

Publicado de verdade: dois pushes para `main`
(`e0a69a9`→`c2a396c`→`be7db96`, o segundo corrigindo o achado da brecha de
convite abandonado), disparando `.github/workflows/deploy.yml` em ambos.
Confirmado no site público real (`https://tropicaltransportes.github.io/SISTEMA-NOVO/`):

- Login (com link "Esqueci minha senha") — confirmado.
- Esqueci minha senha — confirmado (TESTE B).
- Definir nova senha (convite e recuperação) — confirmado (TESTE A e B).
- Alterar senha (logado) — confirmado (TESTE D).
- Bundle publicado aponta só para o projeto de produção, nunca para o
  projeto DEV/QA ou `localhost`.

**Achado operacional (não é bug de código, registrado para conhecimento)**:
o `index.html` do GitHub Pages é servido com `Cache-Control: max-age=600`.
Nos minutos logo após um deploy, abas/edges de CDN que já tinham
cacheado um `index.html` anterior podem referenciar nomes de chunk
JS com hash que não existem mais no novo `dist` (o deploy substitui o
`dist` inteiro), causando uma tela em branco real com
"Failed to fetch dynamically imported module" até esse cache expirar ou
ser contornado (`?cb=` na URL força um fetch novo). Isso é uma
característica geral de hospedagem SPA no GitHub Pages, não específica do
ciclo de autenticação, e não foi alterada nesta etapa (fora de escopo).
Recomendação para uma etapa futura: cache-busting mais agressivo no
`index.html` do deploy (fora do escopo de AUTH-01).

---

## BUILD (seção 9)

`npm run build` dentro de `frontend/`: **limpo, 0 erros**, rodado duas
vezes (antes e depois da correção da brecha de convite abandonado).
Bundle final confirmado apontando só para `wtxbodhqyasdlmyoyjur`.

---

## REGRESSÃO (seção 9)

Smoke test rápido contra produção, autenticado com a conta de teste
(reativada temporariamente para este teste, desativada de novo ao final):

- **Login**: funcionando (testado exaustivamente em A–F acima).
- **Clientes**: `ClientesList` renderizou normalmente com dado real
  (`Tropical Transportes (Frota Própria)`), 0 erros de console numa carga
  limpa.
- **Veículos**: `VeiculosList` renderizou normalmente (cabeçalhos e
  colunas corretos).
- **Orçamentos**: `OrcamentosList` renderizou normalmente, mostrando o
  registro `SMOKE_PROD` já existente de PROD-01 (`SMK0P01`, rascunho,
  R$ 100,00) — 0 erros de console.

Nenhuma regra de negócio do ERP foi alterada nesta etapa — as únicas
mudanças fora de `main.js`/`supabaseClient.js`/`router/index.js`/`stores/auth.js`/
telas novas de auth foram uma adição visual em `AppShell.vue` (botão
"Alterar senha" no topo, ao lado de "Sair").

**REGRESSÃO = PASSOU.**

---

## GATES — avaliação honesta

| Item | Status |
|---|---|
| Causa raiz do convite identificada e reproduzida com evidência real | ✅ |
| Config de produção corrigida (`site_url`, redirect, signup público) | ✅ |
| `config.toml` revertido para dev local (`git diff` vazio) | ✅ |
| Incidente do `email_provider_disabled` identificado e corrigido | ✅ (documentado com transparência) |
| Convite (TESTE A) | ✅ PASSOU |
| Recuperação (TESTE B) | ✅ PASSOU |
| Troca de senha logado (TESTE D) | ✅ PASSOU |
| Senha antiga invalidada após troca (TESTE C) | ✅ PASSOU |
| Link inválido/expirado com mensagem amigável (TESTE E) | ✅ PASSOU |
| `profiles.ativo=false` reconfirmado (TESTE F) | ✅ PASSOU |
| Nunca redireciona para localhost/DEV-QA (TESTE G) | ✅ PASSOU |
| Frontend publicado de verdade com as 4 telas | ✅ Confirmado no site público |
| Senha temporária do admin rotacionada e descartada | ✅ Confirmado (nunca exibida) |
| Build limpo | ✅ |
| Regressão (clientes/veículos/orçamentos) | ✅ |

## STATUS FINAL

**CICLO DE AUTENTICAÇÃO CORRIGIDO E HOMOLOGADO EM PRODUÇÃO.**

O administrador técnico real precisa agora acessar
`https://tropicaltransportes.github.io/SISTEMA-NOVO/`, clicar em "Esqueci
minha senha", informar o e-mail cadastrado, e seguir
o link recebido para definir sua senha definitiva — a senha temporária
anterior não funciona mais.

### Pendências que continuam em aberto (não desta etapa, herdadas de PROD-01)

1. Restore real nunca testado (`RESTORE_TESTED = FALSE`).
2. UAT não executado — sem usuários piloto reais ainda.
3. Plano de billing/backup automático de produção não confirmado.
4. Achado operacional de cache do GitHub Pages (seção FRONTEND/DEPLOY
   acima) — não bloqueante, registrado para uma rodada futura.
