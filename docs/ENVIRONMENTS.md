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
| **Migrations aplicadas** | 57/57, local == remote (`npx supabase migration list --project-ref wtxbodhqyasdlmyoyjur`). As 4 de `20260818170000`..`20260818170300` (FEATURE-OS-CANCELAMENTO-01) foram promovidas em caráter emergencial em 2026-08-19; as 2 de `20260819180000`/`20260819180100` (OS-FLOW-03) foram promovidas em caráter emergencial em 2026-08-20 — ver seção "Promoção emergencial" abaixo (2 incidentes). |
| **Massa QA** | Nenhuma — projeto nasceu vazio, `supabase/seed.sql` nunca foi executado contra ele (nem pode ser: `db push` não roda seed, só `db reset`, e `db reset` nunca foi usado aqui) |
| **Admin inicial** | Hammed de Carvalho Gurgel (`hammedgurgel@tropicaltransportes.com.br`), convidado via Supabase Auth Admin API (`/auth/v1/invite`), perfil `administrador_tecnico`, `ativo=true`. Convite enviado, ainda **não aceito** (sem senha definida) na data deste documento. |
| **Configuração administrativa** | 5/6 itens de `rpc_status_configuracao_sistema()` = CONFIGURADO (custo/hora R$50/h, desconto 20% teto, anexos 15MB jpeg/png/webp/pdf, 3 centros de custo). `checklist_template` = PENDENTE, por decisão do dono (ele criará os templates depois). |
| **Comando obrigatório para qualquer operação de banco nesta e em rodadas futuras** | sempre `--project-ref wtxbodhqyasdlmyoyjur` explícito. **Nunca** `supabase link` para produção, **nunca** `--linked` sozinho sem `--project-ref` também presente na mesma chamada (a combinação `--project-ref <ref> --linked` funciona sem alterar o estado de link persistido da CLI — confirmado nesta rodada). |

**Nunca registrado aqui**: `service_role key`, senha de banco, connection string com senha, access token. A `anon key` de produção NÃO é secreta e está em `frontend/.env.production` (build de produção) — pode ser obtida a qualquer momento com `npx supabase projects api-keys --project-ref wtxbodhqyasdlmyoyjur`.

### Promoção emergencial de 2026-08-19 (FEATURE-OS-CANCELAMENTO-01)

**Achado real, fora do roteiro:** a feature foi implementada e testada
integralmente em DEV/QA (ver `docs/testing/TEST_REPORT_OS_CANCELAMENTO01.md`),
sem qualquer intenção de tocar produção nesta rodada. Durante a sessão, um
merge de PR feito **pelo dono do projeto, fora da sessão** (PR #30,
`feature/ux-pdf-orcamento-01` → `main`) trouxe o frontend novo (que já
referencia as colunas `deleted_at`/`cancelado_em`/etc. de `ordens_servico`)
para `main`. Isso disparou automaticamente `.github/workflows/deploy.yml`,
publicando esse frontend em `https://tropicaltransportes.github.io/SISTEMA-NOVO/`
— que já aponta para **produção** (`frontend/.env.production`) desde a
ETAPA PROD-01. Como as 4 migrations da feature nunca tinham sido aplicadas
em produção, a listagem de Ordens de Serviço quebrou ao vivo
(`column ordens_servico.deleted_at does not exist`).

O dono do projeto foi consultado e **autorizou explicitamente** a promoção
emergencial das 4 migrations (`20260818170000` a `20260818170300`) para
produção, para realinhar o banco com o frontend já publicado — não houve
decisão de "pular homologação", foi resposta a uma quebra real já ao vivo,
com a feature já 50/50 pgTAP + 84/84 regressão verde em DEV/QA antes da
promoção. Aplicado via `npx supabase db push --project-ref wtxbodhqyasdlmyoyjur --linked`,
55/55 local == remote confirmado depois.

**Risco estrutural exposto por este incidente, não corrigido nesta
rodada**: `deploy.yml` builda e publica automaticamente qualquer coisa que
chegue em `main`, sem gate de "as migrations correspondentes já estão em
produção?". Combinado com um hook deste ambiente que comita/dá push
automaticamente ao final de sessões de trabalho, um merge para `main` feito
sem coordenação pode publicar frontend incompatível com o schema de
produção a qualquer momento. Vale considerar, em rodada futura: (a) um
gate manual antes do deploy de produção, ou (b) checar programaticamente
que `supabase migration list --project-ref wtxbodhqyasdlmyoyjur` está em
dia antes de publicar.

### Promoção emergencial de 2026-08-20 (OS-FLOW-03)

**Achado real, fora do roteiro — mesma causa raiz do incidente de
2026-08-19, desta vez sem intervenção de terceiros:** o hook de
auto-commit/push deste ambiente comitou, deu push e teve PR
auto-mergeada em `main` (PR #33) ao final da sessão de trabalho da
ETAPA OS-FLOW-03 — incluindo o frontend que chama `rpc_transicionar_os`
com um 3º parâmetro (`p_motivo`). O pedido original era **explícito**:
implementar só em DEV/QA, não promover a produção. O hook não distingue
isso — qualquer coisa que chegue em `main` é publicada.

Isso disparou `deploy.yml` automaticamente, publicando o frontend novo em
produção **sem** as migrations correspondentes
(`20260819180000`/`20260819180100`) terem sido aplicadas lá. Confirmado
via chamada real (papel anon, UUID falso, sem risco de mutação):
```
POST rpc_transicionar_os(p_os_id, p_novo_status, p_motivo)
→ PGRST202: função não encontrada com esses parâmetros
```
**Toda transição de status de OS ficou quebrada em produção** (não só o
retorno de fase novo — qualquer transição, porque o frontend sempre
manda `p_motivo` agora, mesmo `null`).

O dono do projeto foi consultado e **autorizou explicitamente** a
promoção emergencial das 2 migrations para realinhar produção com o
frontend já publicado — mesmo racional do incidente anterior: não foi
decisão de pular homologação, foi resposta a uma quebra real já ao vivo,
com a etapa já 16/16 pgTAP + 218/218 regressão verde em DEV/QA antes da
promoção. Aplicado via
`npx supabase db push --project-ref wtxbodhqyasdlmyoyjur --linked`,
confirmado com a mesma chamada de teste retornando o erro de permissão
normal (`P0001: Perfil sem permissão`, não mais `PGRST202`), 57/57
local == remote depois.

**Efeito colateral aceito:** a regra de negócio do OS-FLOW-03 (bloqueio
de transição/conclusão com apontamento aberto, retorno controlado de
fase) passou a valer em produção também, antes do previsto — não havia
como restaurar o frontend antigo sem reverter o merge em `main` (opção
não escolhida).

**Este é o SEGUNDO incidente idêntico em 2 dias** (19/08 e 20/08), mesma
causa raiz do risco já registrado acima: `deploy.yml` sem gate de schema
+ hook de auto-commit/push/PR/merge que não distingue "só DEV/QA" de
"pronto pra produção". Recomendação forte, ainda não implementada:
bloquear ou revisar esse hook antes de qualquer próxima etapa que deva
ficar restrita a DEV/QA — do contrário, o padrão vai se repetir.

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
