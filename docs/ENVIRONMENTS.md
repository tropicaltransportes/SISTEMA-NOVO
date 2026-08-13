# Ambientes — DEV/QA vs PRODUÇÃO

Criado na ETAPA 7 (RC1 — Homologação Final), seção 20 do roteiro de
homologação. Define a separação entre o ambiente usado até aqui (todas as
etapas 1 a 7) e o ambiente de produção.

**Atualizado na ETAPA PROD-01 (2026-08-13): o projeto de produção agora
existe de verdade.** Ver seção "PRODUÇÃO — dados reais" abaixo. Tudo o que
estava descrito neste documento como "quando produção for criada" nas
rodadas RC1/RC2 já foi executado nesta rodada — ver
`docs/testing/TEST_REPORT_PROD01.md` para a evidência completa.

## PRODUÇÃO — dados reais (ETAPA PROD-01)

| | |
|---|---|
| **Nome** | SISTEMA NOVO - PROD |
| **Ref (`PRODUCTION_PROJECT_REF`)** | `wtxbodhqyasdlmyoyjur` |
| **Organização** | `rttewrcwuqafozthelqu` (a mesma do DEV/QA — projetos separados dentro da mesma organização) |
| **Região** | `sa-east-1` |
| **Postgres** | 17.6.1.155 (engine 17) |
| **Criado em** | 2026-08-12T19:58:37Z (pelo dono do projeto, antes desta rodada) |
| **Status** | ACTIVE_HEALTHY |
| **Papel** | **PRODUÇÃO** |
| **Migrations aplicadas** | 51/51, local == remote (`npx supabase migration list --project-ref wtxbodhqyasdlmyoyjur`) |
| **Massa QA** | Nenhuma — projeto nasceu vazio, `supabase/seed.sql` nunca foi executado contra ele (nem pode ser: `db push` não roda seed, só `db reset`, e `db reset` nunca foi usado aqui) |
| **Admin inicial** | Hammed de Carvalho Gurgel (`hammedgurgel@tropicaltransportes.com.br`), convidado via Supabase Auth Admin API (`/auth/v1/invite`), perfil `administrador_tecnico`, `ativo=true`. Convite enviado, ainda **não aceito** (sem senha definida) na data deste documento. |
| **Configuração administrativa** | 5/6 itens de `rpc_status_configuracao_sistema()` = CONFIGURADO (custo/hora R$50/h, desconto 20% teto, anexos 15MB jpeg/png/webp/pdf, 3 centros de custo). `checklist_template` = PENDENTE, por decisão do dono (ele criará os templates depois). |
| **Comando obrigatório para qualquer operação de banco nesta e em rodadas futuras** | sempre `--project-ref wtxbodhqyasdlmyoyjur` explícito. **Nunca** `supabase link` para produção, **nunca** `--linked` sozinho sem `--project-ref` também presente na mesma chamada (a combinação `--project-ref <ref> --linked` funciona sem alterar o estado de link persistido da CLI — confirmado nesta rodada). |

**Nunca registrado aqui**: `service_role key`, senha de banco, connection string com senha, access token. A `anon key` de produção NÃO é secreta e está em `frontend/.env.production` (build de produção) — pode ser obtida a qualquer momento com `npx supabase projects api-keys --project-ref wtxbodhqyasdlmyoyjur`.

### Como desativar um usuário em produção (procedimento operacional — AUT-007)

Não existe revogação instantânea de sessão (JWT stateless, risco aceito —
ver BUSINESS_RULES.md BR-040 Decisão #3). Para desligar um usuário:

1. `update profiles set ativo = false where id = '<uuid-do-usuario>';` (via
   painel administrativo do sistema quando existir essa tela, ou SQL direto
   pelo responsável técnico contra o projeto de produção).
2. Confirmado nesta rodada (ETAPA PROD-01, smoke test de segurança): com
   `ativo=false`, o usuário consegue tecnicamente autenticar no Supabase
   Auth (GoTrue não sabe nada sobre `profiles.ativo`), mas **toda** leitura
   e escrita no ERP fica bloqueada (`current_perfil()`/`current_user_ativo()`
   retornam falso/nulo) — confirmado com uma conta de smoke test
   (`smoke.prod.inativo@tropicaltransportes.com.br`): `SELECT` em `clientes`
   retornou vazio, RPC de escrita retornou `P0001 "Perfil sem permissão..."`.
3. Se for necessário garantir que o token de acesso já emitido pare de
   funcionar imediatamente (não só na próxima chamada ao ERP, mas em geral),
   é preciso usar `service_role` para revogar sessões no Supabase Auth — não
   existe um botão de "logout forçado" no ERP hoje. Tratar como exceção rara,
   não como procedimento padrão de desligamento.

## Situação DEV/QA (inalterada)

Existe **um único** projeto Supabase de DEV/QA para este sistema:

| | |
|---|---|
| **Nome** | SISTEMA NOVO |
| **Ref** | `jzjbiejmcaygwycvqggm` |
| **Organização** | `rttewrcwuqafozthelqu` |
| **Status** | ACTIVE_HEALTHY |
| **Papel** | **DEV/QA** — nunca foi, e não é, produção |

Este projeto **continua sendo DEV/QA** após a ETAPA 7. Nada nesta rodada o
transforma em produção. Ele contém:

- as 50 migrations do schema (reproduzidas do zero nesta rodada via
  `supabase db reset --linked`, ver `docs/testing/TEST_REPORT_RC1.md` seção
  7);
- massa de teste determinística (`supabase/seed.sql`) — usuários
  `*.qa.local`, clientes/veículos/peças/OS prefixados `TESTE_`/`QA_`;
  senha única de teste `Teste@2026!Qa`;
  dados adicionais criados por scripts de teste (`docs/testing/scripts/*.sh`)
  ao longo de 7 rodadas de homologação, sempre com prefixo `TESTE_`/`PGTAP`.

Existe também um segundo projeto na mesma organização, `cedqaxmkffqrwfopgyze`
("YNAB COVER"), **sem nenhuma relação com este sistema** — não usar para
nada relacionado ao ERP Oficina.

## O que PRODUÇÃO precisa ter, obrigatoriamente — status após ETAPA PROD-01

1. **Projeto Supabase próprio**, separado do DEV/QA. ✅ **FEITO** — `wtxbodhqyasdlmyoyjur`.
2. **Secrets próprios**: nova `anon key` e `service_role key`, nunca as
   mesmas usadas em DEV/QA. ✅ **FEITO** — confirmado por chaves distintas
   (`iss`/`ref` do JWT diferentes) retornadas por
   `projects api-keys --project-ref wtxbodhqyasdlmyoyjur`.
3. **Mesmas 51 migrations**, aplicadas na mesma ordem, sem alteração. ✅
   **FEITO** — 51/51, local == remote.
4. **Nenhuma massa de teste**: `supabase/seed.sql` **não** aplicado em
   produção. ✅ **FEITO** — nunca executado (só `db push`, que não roda
   seed); confirmado 0 `auth.users` antes do admin, 0 `profiles`/`veiculos`/
   `ordens_servico` antes do smoke test.
5. **Usuários reais**: pelo menos 1 administrador técnico real. 🟡
   **PARCIAL** — convite enviado a Hammed de Carvalho Gurgel, perfil já
   promovido a `administrador_tecnico` em `profiles`, mas o convite ainda
   **não foi aceito** (sem senha própria definida) na data deste documento.
6. **Configuração administrativa inicial preenchida de verdade**. 🟡
   **PARCIAL (5/6)** — custo/hora, desconto, anexos e centros de custo
   configurados com os valores reais fornecidos pelo dono do projeto;
   checklists ficam PENDENTE por decisão dele (fará depois, dentro do
   sistema).
7. **Storage**: os buckets `comprovantes` e `os-fotos` recriados. ✅
   **FEITO** — confirmados via migrations + smoke test de policies (upload/
   leitura por perfil, DELETE bloqueado para todos inclusive admin, BR-043).
8. **Frontend apontando para o projeto de produção**. ✅ **FEITO** —
   `frontend/.env.production` aponta para `wtxbodhqyasdlmyoyjur`; `.env`
   (dev) inalterado, continua `jzjbiejmcaygwycvqggm`. **Achado desta
   rodada**: antes desta correção, `.env.production` estava commitado
   apontando por engano para o DEV/QA desde a rodada em que o GitHub Pages
   foi publicado pela primeira vez (commit `1ce7af5`) — ver seção DEPLOY de
   `docs/testing/TEST_REPORT_PROD01.md`.
9. **HTTPS/domínio próprio**. ⬜ **NÃO FEITO NESTA RODADA** — depende do
   deploy real do frontend (`git push` para `main`), que não foi executado
   por decisão explícita do roteiro desta rodada (ver seção 12/DEPLOY do
   relatório). Rewrite de SPA continua **não necessário** (hash routing,
   `createWebHashHistory`).
10. **Backup e restore documentados e testados**. 🟡 **PARCIAL** — backup
    automático do Supabase depende do plano contratado (não verificável via
    CLI nesta rodada — confirmar no dashboard, Settings → Billing). Restore
    real continua **BLOQUEADO**, mesma causa raiz do RC2 (sem Docker/
    pg_dump/psql neste ambiente) — ver `docs/PRODUCTION_BACKUP_RESTORE.md`.

## Regra permanente

- DEV/QA (`jzjbiejmcaygwycvqggm`) é o único ambiente onde é permitido rodar
  testes destrutivos, resets, massa de teste e scripts de homologação.
- PRODUÇÃO nunca recebe: `supabase/seed.sql`, scripts de
  `docs/testing/scripts/`, usuários `*.qa.local`, ou qualquer comando `db
  reset`.
- Migrations fluem sempre **DEV/QA → homologadas → produção**, nunca ao
  contrário, e nunca é criada uma migration só para produção.
- Ao criar o projeto de produção, seguir exatamente
  `docs/PRODUCTION_READINESS_CHECKLIST.md` antes de liberar acesso a
  usuários reais.
