# Checklist de Produção — ERP Oficina (Tropical Transportes)

Criado na ETAPA 7 (RC1), seção 21 do roteiro de homologação final. Nenhum
item abaixo foi marcado apenas por suposição — os itens já cobertos por
evidência real desta rodada estão anotados; os demais são ações que só
fazem sentido quando o projeto de produção for criado de fato (fora do
escopo desta rodada, que é só de homologação).

## Infraestrutura Supabase

**Atualizado na ETAPA PROD-01 (2026-08-13) — ver `docs/testing/TEST_REPORT_PROD01.md`
para a evidência completa de cada item marcado abaixo.**

- [x] Projeto Supabase de **produção** criado (separado de
      `jzjbiejmcaygwycvqggm`, que continua DEV/QA — ver `docs/ENVIRONMENTS.md`)
      — `wtxbodhqyasdlmyoyjur` ("SISTEMA NOVO - PROD"), `sa-east-1`.
- [x] Migrations aplicadas — as mesmas 51 migrations homologadas, na mesma
      ordem, sem edição (`npx supabase db push --project-ref wtxbodhqyasdlmyoyjur`);
      `migration list --project-ref wtxbodhqyasdlmyoyjur` confirma 51/51
      local == remote.
- [x] RLS validada em produção — anon RPC scan (26 RPCs de escrita testadas,
      0 bypass), usuário inativo bloqueado, perfil errado bloqueado, perfil
      correto permitido — ver seção SEGURANÇA de `TEST_REPORT_PROD01.md`.
- [x] Storage policies validadas em produção — buckets `comprovantes` e
      `os-fotos` confirmados privados; upload/leitura testados por perfil
      (anon/executor bloqueados, suporte/encarregado permitidos conforme
      regra); DELETE bloqueado para todos os perfis, inclusive
      administrador (BR-043 reconfirmada em produção).
- [x] Política de exclusão de arquivos — **decisão formal registrada**
      (ETAPA 8/RC2, `docs/testing/BUSINESS_RULES.md` BR-043): arquivos
      operacionais (comprovantes, fotos de OS) não devem ser apagados
      fisicamente por nenhum perfil, nem administrador. Confirmado que
      nenhuma migration cria policy de DELETE em `storage.objects` para os
      dois buckets — reconfirmado em produção nesta rodada (tentativa real
      de DELETE por conta smoke administrador_tecnico → 403).
- [x] Usuários QA ausentes — projeto nasceu vazio, nenhum `*.qa.local`,
      nenhum `Teste@2026!Qa` (nunca existiu massa QA em produção, por
      construção — seed nunca rodou aqui).
- [x] Seed QA **não** aplicado (`supabase/seed.sql` é só para DEV/QA —
      nunca rodado contra produção; `db push` não executa seed).
- [x] Secrets de produção configurados — `anon key`/`service_role key`
      próprios do projeto de produção, obtidos via
      `npx supabase projects api-keys --project-ref wtxbodhqyasdlmyoyjur`,
      nunca reaproveitados de DEV/QA.
- [x] Frontend apontando para produção — `frontend/.env.production`
      corrigido nesta rodada para `wtxbodhqyasdlmyoyjur` (estava apontando
      por engano para DEV/QA desde a primeira publicação no GitHub Pages —
      achado real desta rodada, ver `TEST_REPORT_PROD01.md` seção DEPLOY);
      `frontend/.env` (dev) confirmado inalterado.

## Continuidade operacional

- [x] Backup configurado (parcial) — backup lógico real **executado** na
      ETAPA 8 (RC2) contra DEV/QA (schema via migrations + dados via REST,
      ver `docs/testing/TEST_REPORT_RC2.md` seção 5). **Achado importante**:
      `npx supabase db dump --linked` (o comando recomendado em
      `docs/PRODUCTION_BACKUP_RESTORE.md`) **não funciona sem Docker Desktop
      ou `pg_dump` instalado localmente** — confirmado por execução real
      nesta rodada, não só suposição. Antes do go-live, garantir que a
      máquina/pipeline responsável pelo backup de produção tenha Docker ou
      `pg_dump` disponível, ou usar o método alternativo (schema =
      migrations, dados = REST API) documentado no RC2. Ainda falta
      confirmar retenção/frequência do backup automático do plano Supabase
      contratado.
- [ ] Restore documentado, **mas não testado ponta a ponta** — continua
      **BLOQUEADO** também na ETAPA PROD-01, mesma causa raiz do RC2 (sem
      Docker/`pg_dump`/`psql` locais, sem autorização para criar projeto
      Supabase descartável nesta rodada). **`RESTORE_TESTED = FALSE`** —
      maior risco operacional aberto antes de operar com dados reais de
      clientes. Ver `docs/PRODUCTION_BACKUP_RESTORE.md` (atualizado).

## Validação pré-go-live

- [x] Smoke test em produção — login com uma conta de smoke test
      `administrador_tecnico` (o admin real ainda não aceitou o convite) +
      fluxo completo cliente `SMOKE_PROD` → veículo `SMOKE_PROD` → orçamento
      `SMOKE_PROD` (com item), executado contra o projeto de produção. RLS
      confirmada (executor bloqueado de alterar orçamento diretamente).
      Registros preservados, inativados (`deleted_at`/`ativo=false`) como
      evidência — ver `docs/testing/TEST_REPORT_PROD01.md` seção SMOKE.
- [x] Admin inicial criado — Hammed de Carvalho Gurgel
      (`hammedgurgel@tropicaltransportes.com.br`), convidado via Auth Admin
      API (`/auth/v1/invite`), `profiles.perfil='administrador_tecnico'`,
      `ativo=true`. **Convite enviado, ainda não aceito** — ele precisa
      definir a própria senha e fazer seu próprio smoke test depois.
- [x] Configurações de negócio preenchidas — `custo_hora_config` (R$50/h),
      `desconto_config` (habilitado, teto 20%), `anexos_config` (15MB,
      jpeg/png/webp/pdf), `centro_custo` (3 registros: "Manutenção -
      Interna", "Manutenção - Externa", "Receita com Peças") — todos com
      valores reais fornecidos pelo dono do projeto, confirmados via
      `rpc_status_configuracao_sistema()` = CONFIGURADO. `checklist_template`
      continua **PENDENTE**, por decisão explícita do dono (criará os
      templates depois, dentro do sistema) — não é um erro, é intencional.
- [ ] Logs verificados — procedimento documentado (só via dashboard do
      Supabase — Auth/API/Postgres/Storage em *Logs*/*Log Explorer*; não há
      subcomando de CLI para logs sem Docker), mas **não observado
      continuamente ainda** (sem operação real rodando). Ver
      `docs/testing/TEST_REPORT_PROD01.md` seção LOGS.
- [x] URLs/SPA — **não aplicável hoje.** Confirmado na ETAPA 8 (RC2), seção
      3 (`frontend/src/router/index.js`, `createWebHashHistory`): o
      roteamento é hash-based (`#/os/:id`), então o navegador sempre pede só
      `index.html` ao servidor — refresh/deep-link em qualquer rota interna
      funciona em qualquer hospedagem estática, sem nenhuma regra de rewrite
      de servidor. **Enquanto o frontend utilizar hash routing, não é
      necessário SPA rewrite. Se futuramente migrar para history routing,
      revisar esta decisão.**
- [ ] HTTPS habilitado no domínio de produção — depende do deploy real
      (GitHub Pages já é HTTPS por padrão, mas o deploy com os valores
      corretos de produção ainda não foi publicado — ver seção 12/DEPLOY).
- [ ] Domínio próprio configurado — não decidido nesta rodada; a URL
      definida é a padrão do GitHub Pages
      (`https://tropicaltransportes.github.io/SISTEMA-NOVO/#/login`).
- [x] AUT-007 aceito/documentado — risco aceito de revogação de sessão via
      JWT stateless do Supabase (não corrigido por decisão de escopo, ver
      `docs/testing/BUSINESS_RULES.md` BR-040 Decisão #3); reconfirmado
      nesta rodada contra produção (conta smoke `ativo=false` conseguiu
      autenticar no Auth mas foi bloqueada em toda leitura/escrita do ERP).
      Procedimento de desligamento documentado em `docs/ENVIRONMENTS.md`.

## FEATURE-SERVICOS-01 (2026-08-17)

- [x] Migrations `20260817140000_p2_servicos_catalogo.sql` e
      `20260817140100_p2_fix_natureza_gerada.sql` aplicadas em produção
      (`npx supabase db push --project-ref wtxbodhqyasdlmyoyjur`, executado
      pelo usuário), confirmadas por `migration list` (remote preenchido) e
      por contagem de objetos (7 categorias seedadas, 5 funções, coluna
      `orcamento_itens.natureza` gerada) — ver
      `docs/testing/TEST_REPORT_SERVICOS01.md`.
- [ ] Homologação visual real (clique no browser) em produção — **pendente**,
      mesma limitação de credenciais das etapas anteriores; usuário optou
      por aprovar com base em migration real + pgTAP (60/60) + build.
- **Nota operacional:** o deploy do frontend (GitHub Pages, CI on-push-to-main)
      ocorreu **antes** da migration ser aplicada em produção — o merge do PR
      já dispara o build/deploy automaticamente, sem esperar confirmação da
      migration. Houve uma janela curta em que a tela "Serviços" ficaria com
      erro de carregamento em produção (degradação graciosa, sem quebrar o
      restante do app). Fechada no mesmo dia. Considerar, em etapas futuras,
      aplicar a migration de produção **antes** de mesclar o PR que expõe a
      tela nova no frontend, para evitar essa janela.

## FEATURE-ORCAMENTO-EXCLUSAO-01 (2026-08-18)

- [x] Implementada e homologada em DEV/QA (`jzjbiejmcaygwycvqggm`): migrations
      `20260818150000_p2b_orcamento_exclusao_rascunho.sql`,
      `20260818150100_p2b_status_orcamento_cancelado_enum.sql`,
      `20260818150200_p2b_orcamento_cancelamento.sql`. 92/92 pgTAP (32 novas +
      60 regressão), `npm run build` ok, validação por clique real no browser
      confirmada (fluxo completo excluir/restaurar/cancelar/PDF) — ver
      `docs/testing/TEST_REPORT_ORCAMENTO_EXCLUSAO01.md`.
- [ ] **Não promovida para produção nesta rodada** — aguardando autorização
      explícita do usuário, por decisão do próprio pedido original ("NÃO
      aplicar automaticamente em produção").
- **Nota operacional (repetir o cuidado de FEATURE-SERVICOS-01):** ao
      promover, aplicar as 3 migrations em produção **antes** de mesclar o
      PR do frontend para `main` — o deploy do GitHub Pages dispara em todo
      push para `main` sem checar estado do banco, e desta vez o risco é
      maior que o da etapa anterior: se o frontend for ao ar antes da
      migration, a listagem inteira de Orçamentos quebra (colunas
      `deleted_at`/`cancelado_em` inexistentes), não só uma tela isolada.

## Observação sobre o estado desta rodada

**Atualizado na ETAPA PROD-01 (2026-08-13).** A maior parte deste checklist
foi executada de fato contra o projeto de produção real
(`wtxbodhqyasdlmyoyjur`) nesta rodada — ver `docs/testing/TEST_REPORT_PROD01.md`
para evidência completa de cada item. Os itens que continuam pendentes
(restore real, publicação do frontend/HTTPS/domínio, logs observados
continuamente, aceite do convite do admin real, checklists) são pendências
explícitas e conscientes, não itens esquecidos — a maioria é bloqueada por
decisão explícita do roteiro desta rodada (não publicar no GitHub Pages
ainda) ou por limitação de infraestrutura já conhecida desde o RC2 (restore
sem Docker/pg_dump local).
