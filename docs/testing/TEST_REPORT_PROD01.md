# TEST REPORT — ETAPA PROD-01 — Provisionamento de Produção

Data: 2026-08-13. Continuação de `TEST_REPORT_RC2.md` (preservado intacto).
Objetivo desta rodada: provisionar e começar a homologar o ambiente de
**PRODUÇÃO real** (não DEV/QA) do ERP Oficina — Tropical Transportes.
Nenhuma funcionalidade nova foi desenvolvida, conforme instrução explícita.

**AMBIENTE = PRODUÇÃO | PROJECT_REF = `wtxbodhqyasdlmyoyjur` | PROJECT_NAME =
"SISTEMA NOVO - PROD"** — usado explicitamente em toda chamada de CLI que
alterou o banco nesta rodada (nunca `supabase link`, nunca `--linked`
sozinho). O projeto DEV/QA (`jzjbiejmcaygwycvqggm`) e o projeto sem relação
(`cedqaxmkffqrwfopgyze`, "YNAB COVER") não foram tocados.

---

## AMBIENTE CRIADO

| | |
|---|---|
| Nome | SISTEMA NOVO - PROD |
| Ref | `wtxbodhqyasdlmyoyjur` |
| Organização | `rttewrcwuqafozthelqu` |
| Região | `sa-east-1` |
| Postgres | 17.6.1.155 (engine 17) |
| Criado em | 2026-08-12T19:58:37Z, pelo dono do projeto, antes desta rodada |
| Status | ACTIVE_HEALTHY |

**Validação de projeto vazio (seção 3 do roteiro)**: confirmado antes de
aplicar qualquer migration — `db push --dry-run` mostrou 51 migrations
pendentes, 0 aplicadas, `"seeds":[]`, `"roles":[]`. Depois da aplicação,
consultas diretas confirmaram: 0 `auth.users`, 0 `profiles`, 0 `veiculos`,
0 `ordens_servico` antes da criação do admin. 1 linha pré-existente em
`clientes` foi investigada e é **legítima** (não é massa QA): vem da
migration base `20260806120100_clientes_veiculos.sql`, que semeia o
registro âncora "Tropical Transportes (Frota Própria)" usado por toda OS
interna (BR-036) — o mesmo comportamento já confirmado em DEV/QA. Nenhum
`*.qa.local`, `Teste@2026!Qa`, `TESTE_`, `QA_`, `PGTAP` encontrado.

---

## MIGRATIONS

- Local: 51 arquivos em `supabase/migrations/`.
- `npx supabase migration list --project-ref wtxbodhqyasdlmyoyjur` (antes):
  51 migrations locais, todas com `remote:""`.
- `npx supabase db push --project-ref wtxbodhqyasdlmyoyjur --yes`: as 51
  aplicadas com sucesso (único aviso, não-erro: falha ao cachear catálogo de
  migrations por falta de Docker — não impacta a aplicação real).
- `npx supabase migration list --project-ref wtxbodhqyasdlmyoyjur` (depois):
  **51/51 local == remote**, 0 divergências.
- Nenhuma migration antiga foi editada (nenhuma migration foi tocada nesta
  rodada — só aplicadas as já existentes).
- 35 tabelas confirmadas em `public` depois da aplicação (mesmo número
  reportado no RC2 para DEV/QA).

**MIGRATIONS = APLICADAS COM SUCESSO, 51/51.**

---

## ADMIN

- Convite enviado via `POST /auth/v1/invite` (Supabase Auth Admin API, com
  `service_role` usado só na variável de shell da chamada, nunca escrito em
  arquivo) para `hammedgurgel@tropicaltransportes.com.br` — HTTP 200,
  `user.id = 672383ef-b72c-4fc4-ae86-0fef88da4672`, `confirmation_sent_at`
  preenchido.
- Trigger `handle_new_user` criou a linha em `profiles` automaticamente,
  como esperado (perfil padrão `executor`, nome = e-mail, `ativo=true`).
- Promovido manualmente via SQL direto (não existe RPC de auto-promoção de
  admin, por decisão de segurança já documentada em
  `docs/PRODUCTION_INITIAL_CONFIGURATION.md`): `nome='Hammed de Carvalho
  Gurgel'`, `perfil='administrador_tecnico'`, `ativo=true`. Confirmado por
  `SELECT` de retorno da própria instrução.
- **Convite enviado, ainda não aceito** na data deste relatório — Hammed
  ainda não definiu senha própria. Login real com a conta dele **não foi
  testado** (não havia como, por desenho — ele define a própria senha).

**ADMIN = CRIADO E PROMOVIDO, CONVITE PENDENTE DE ACEITE.**

---

## CONFIGURAÇÃO

Aplicada via as RPCs reais do sistema (`rpc_definir_custo_hora`,
`rpc_definir_teto_desconto`, `rpc_definir_anexos_config`,
`rpc_criar_centro_custo`), executando-as como o admin real
(`672383ef-b72c-4fc4-ae86-0fef88da4672`) através de uma sessão SQL com
`request.jwt.claims`/`role=authenticated` simulando exatamente o que o
PostgREST monta a partir de um JWT — não um INSERT direto contornando a
checagem de perfil; o mesmo caminho de código (`tem_perfil()` +
`registrar_auditoria()`) que a API real executaria.

| Item | Valor aplicado | Justificativa |
|---|---|---|
| Custo/hora interno | R$ 50,00/h, vigência = hoje | Valor de teste explícito informado pelo dono ("só pra gente testar"), registrado no mecanismo histórico/vigência já existente — pode ser revisado depois sem afetar OS já encerradas (snapshot). |
| Desconto | habilitado=true, teto=20% | Valor informado pelo dono. Mecanismo já suporta alteração futura (histórico append-only, Decisão 7 do P1-C) — confirmado, nada novo foi construído. |
| Anexos | tamanho máximo **15 MB** (15728640 bytes) para qualquer tipo permitido; MIME: `image/jpeg`, `image/png`, `image/webp`, `application/pdf` | **Escolha desta rodada, documentada para o dono poder ajustar**: o schema de `anexos_config` tem **um único** campo de tamanho máximo para todos os tipos (não diferencia imagem de PDF) — por isso foi escolhido o teto único mais simples dado o schema existente, em vez de simular dois limites que o banco não representa. 15 MB é um valor comum/coerente tanto para fotos de celular em boa resolução quanto para PDFs de poucas páginas digitalizados; folga confortável acima do que os buckets tipicamente recebem, sem abrir demais o limite. **Se o dono preferir valores diferentes por tipo, isso exigiria uma mudança de schema (fora de escopo desta rodada, que é só de configuração)** — registrado como observação, não como pendência bloqueante. |
| Centros de custo | "Manutenção - Interna", "Manutenção - Externa", "Receita com Peças" (3 registros, `ativo=true`) | Nomes exatos fornecidos pelo dono. |
| Checklists | **PENDENTE, por decisão explícita do dono** | Ele criará os templates depois, dentro do sistema. Não é erro — proibido inventar valor. |

Resultado final de `rpc_status_configuracao_sistema()` (executado como
encarregado de teste, confirmando também o RBAC de leitura):

```
administrador_tecnico  | true  | Ativos: 2  (Hammed + 1 conta de smoke administrador_tecnico, ver seção SEGURANÇA)
custo_hora_config      | true  | Vigente: R$ 50.00/h
desconto_config        | true  | Teto vigente: 20.00% (habilitado=true)
anexos_config          | true  | Máx 15.0MB, MIME: image/jpeg, image/png, image/webp, application/pdf
centro_custo           | true  | Ativos: 3
checklist_template     | false | Ativos: 0
```

**CONFIGURAÇÃO = 5/6 CONFIGURADO. `checklist_template` PENDENTE por decisão
consciente do dono do projeto — não é uma falha desta rodada.**

### Achado / lacuna registrada (não corrigida nesta rodada — proibido)

O dono do projeto mencionou querer, no futuro, adicionar centros de custo
pela interface. **Não existe hoje nenhuma tela de frontend de CRUD de
centro de custo** (`rpc_criar_centro_custo` existe no backend, mas não há
`CentroCustoList.vue` ou equivalente, ao contrário do que existe para
Checklists/Faixas de Acréscimo). Os 3 centros de custo desta rodada foram
inseridos via RPC/SQL direto contra produção, como autorizado. **Não foi
construída nenhuma tela nova nesta rodada** (proibido — feature nova).
Registrado aqui como pendência explícita para uma rodada futura de
desenvolvimento.

---

## STORAGE

Buckets confirmados via `storage.buckets`: `comprovantes` (privado) e
`os-fotos` (privado) — únicos 2 buckets existentes, criados pelas
migrations (não é configuração manual).

Smoke test de policies (contas de smoke test descartáveis, ver seção
SEGURANÇA):

| Teste | Resultado |
|---|---|
| anon upload `comprovantes` | Bloqueado (sem header de autorização aceito) |
| executor upload `comprovantes` | Bloqueado — 403, RLS |
| suporte administrativo upload `comprovantes` | Permitido — 200 |
| executor ler o arquivo do suporte em `comprovantes` | Bloqueado — 404 (RLS torna o objeto invisível) |
| suporte ler o próprio arquivo | Permitido — 200 |
| admin (smoke) DELETE do arquivo em `comprovantes` | **Bloqueado — 403** (confirma BR-043 em produção: nenhuma policy de DELETE, nem para admin) |
| executor upload `os-fotos` sem vínculo a nenhuma OS | Bloqueado — 403, RLS |
| encarregado upload `os-fotos` | Permitido — 200 |
| anon ler bucket `os-fotos` | Bloqueado — 404 (bucket não descoberto sem sessão) |

Mesmo padrão de resultado do RC1 (DEV/QA) — nenhuma regressão, nenhuma
divergência de comportamento entre ambientes.

**STORAGE = VALIDADO EM PRODUÇÃO.**

---

## SEGURANÇA

### Contas de smoke test criadas (descartáveis, exclusivas desta rodada)

Criadas via Auth Admin API (`POST /auth/v1/admin/users`, sem envio de
convite real, senha temporária conhecida só para este teste), e-mails
claramente identificáveis:

| E-mail | Perfil |
|---|---|
| `smoke.prod.executor@tropicaltransportes.com.br` | executor |
| `smoke.prod.encarregado@tropicaltransportes.com.br` | encarregado |
| `smoke.prod.suporte@tropicaltransportes.com.br` | suporte_administrativo |
| `smoke.prod.diretoria@tropicaltransportes.com.br` | diretoria |
| `smoke.prod.admin@tropicaltransportes.com.br` | administrador_tecnico |
| `smoke.prod.inativo@tropicaltransportes.com.br` | executor, **ativo=false** desde a criação |

Nomes gravados como `SMOKE_PROD <perfil>`, claramente identificáveis. **Ao
final desta rodada, todas as 6 contas foram desativadas
(`profiles.ativo=false`)** — não são usuários reais.

### Anon RPC scan (script `docs/testing/scripts/safe_anon_rpc_checks_prod.sh`)

26 RPCs de escrita testadas com UUIDs falsos, chamador anônimo (sem
sessão):

- 23 retornaram `HTTP 400, P0001 "Perfil sem permissão para..."` — bloqueio
  em runtime via `tem_perfil()`.
- 2 (`rpc_registrar_saida_estoque`, `rpc_registrar_entrada_estoque`)
  retornaram `HTTP 401, 42501 "permission denied"` — bloqueadas por
  `REVOKE` (helpers internos, sem `EXECUTE` para `anon`/`authenticated`).
- `SELECT profiles` como anon retornou `[]` (RLS bloqueia leitura).
- Bearer JWT malformado numa RPC protegida → `401, PGRST301`.

**Zero bypass.**

### Usuário inativo, perfil errado, perfil correto

| Teste | Resultado |
|---|---|
| `smoke.prod.inativo` (ativo=false) faz login no Auth | **Sucesso** — GoTrue não verifica `profiles.ativo` (comportamento arquitetural conhecido, ver BR-028/AUT-007) |
| `smoke.prod.inativo` `SELECT clientes` | `[]` — bloqueado |
| `smoke.prod.inativo` chama `rpc_criar_centro_custo` | `400, P0001` — bloqueado |
| `smoke.prod.executor` (perfil errado) chama `rpc_definir_custo_hora` (só admin) | `400, P0001` — bloqueado |
| `smoke.prod.executor` `SELECT custo_hora_config` | `[]` — RLS bloqueia leitura para executor |
| `smoke.prod.encarregado` (perfil correto) `SELECT custo_hora_config` | `[{"valor_hora":50.00}]` — permitido |
| `smoke.prod.encarregado` chama `rpc_status_configuracao_sistema()` | `200`, 6 itens retornados — permitido |

**SEGURANÇA = PASSOU. Zero bypass de RLS/RPC confirmado em produção.**

---

## FRONTEND

- `frontend/.env.production` corrigido nesta rodada para apontar
  exclusivamente ao projeto de produção (`VITE_SUPABASE_URL=https://wtxbodhqyasdlmyoyjur.supabase.co`,
  `VITE_SUPABASE_ANON_KEY` obtida via `projects api-keys` — não é secreta).
- `frontend/.env` (dev) confirmado **inalterado**, continua
  `jzjbiejmcaygwycvqggm`.
- **Achado real desta rodada**: antes desta correção, `frontend/.env.production`
  já estava commitado no repositório (commit `1ce7af5`, "Publica o frontend
  no GitHub Pages") apontando por engano para o projeto **DEV/QA**
  (`jzjbiejmcaygwycvqggm`), não para produção (que ainda não existia quando
  aquele commit foi feito). Ver seção DEPLOY abaixo — esse valor errado já
  chegou a ser publicado.
- `npm run build` (dentro de `frontend/`): **limpo, 0 erros** (só o log
  informativo de `PLUGIN_TIMINGS`, não é warning de código, mesmo padrão
  de RC1/RC2), build em ~23s.
- Confirmado por `grep` no bundle gerado (`dist/assets/supabaseClient-*.js`):
  contém `wtxbodhqyasdlmyoyjur`, **não** contém `jzjbiejmcaygwycvqggm`.
- **Commit local usado para este build**: `0b98fcd` ("ETAPA PROD-01 parte 1:
  apontamento do frontend de producao + script de smoke anon"), branch
  `feature/veiculos-proprietario-cliente-detalhe`.

**FRONTEND = BUILD DE PRODUÇÃO LIMPO, apontando corretamente para
`wtxbodhqyasdlmyoyjur`.**

---

## DEPLOY

**Achado crítico não previsto pelo roteiro, verificado no início desta
rodada**: o frontend deste sistema **já está publicamente acessível** em
`https://tropicaltransportes.github.io/SISTEMA-NOVO/#/login` — a página de
login carrega normalmente (confirmado por navegação real). Investigação:

- `git log origin/main -1` mostra um merge commit (`f9592df`, "Merge pull
  request #14 from tropicaltransportes/feature/veiculos-proprietario-cliente-detalhe")
  que já trouxe toda a branch de trabalho para `main`, incluindo o commit
  `1ce7af5` ("Publica o frontend no GitHub Pages").
- Isso significa que o workflow `.github/workflows/deploy.yml` (dispara em
  push para `main`) **já rodou** contra esse estado, e o site já estava
  publicado **antes** desta rodada — apontando, até a correção desta
  rodada, para o projeto **DEV/QA**, não para produção (o dono do projeto
  não usou `git push`/merge para `main` nesta sessão de trabalho com Claude
  Code; o PR foi mergeado por fora dessas sessões, provavelmente
  diretamente pelo dono via GitHub).
- **Nenhuma ação de push/merge foi feita por esta rodada** — isso já
  existia quando a sessão começou. Reportado ao dono do projeto assim que
  encontrado, antes de continuar o restante do trabalho.

Nesta rodada:

- `frontend/.env.production` foi corrigido localmente e commitado
  **localmente** (commit `0b98fcd`), mas **não enviado** ao `origin` — a
  branch local está à frente do que está em `origin/feature/veiculos-proprietario-cliente-detalhe`
  agora.
- `git push` para `origin`/`main` **não foi executado nesta rodada**, por
  decisão explícita do roteiro (seção 12).
- `.github/workflows/deploy.yml` foi revisado: builda com `npm run build`
  dentro de `frontend/`, que automaticamente lê `frontend/.env.production`
  (comportamento padrão do Vite em modo produção) — **nenhuma mudança foi
  necessária no workflow em si**, ele já builda com os valores corretos
  assim que o commit `0b98fcd` chegar em `main`.

### O que falta fazer para publicar de verdade (ação humana, fora desta rodada)

1. Decidir o que fazer com o fato de que o GitHub Pages **já está no ar**
   apontando (até este momento) para o banco de DEV/QA — o dono do projeto
   deve avaliar se isso representa algum risco/exposição que precisa de
   atenção imediata (ex.: alguém acessando a tela de login pensando ser
   produção).
2. Trazer o commit `0b98fcd` (e os demais desta rodada) para `main` — via
   merge de PR (mesmo fluxo já usado antes) ou `git push` direto, **decisão
   do dono do projeto, não desta rodada**.
3. Isso disparará automaticamente `deploy.yml`, publicando um build que
   agora aponta corretamente para `wtxbodhqyasdlmyoyjur`.
4. Alternativa: disparar `workflow_dispatch` manualmente no GitHub Actions
   depois que o merge acontecer.

**DEPLOY = NÃO PUBLICADO NESTA RODADA (por decisão do roteiro), mas com um
achado real: uma versão anterior, apontando para o ambiente errado, já
estava publicamente no ar antes desta rodada começar.**

---

## SMOKE

Fluxo mínimo executado via chamadas API diretas (simulando o que o
frontend faria), autenticado como a conta de smoke `administrador_tecnico`
(`smoke.prod.admin@tropicaltransportes.com.br` — o admin real ainda não
aceitou o convite, então **ele ainda precisa fazer seu próprio smoke test
depois que definir a senha**):

1. `POST /rest/v1/clientes` — cliente `SMOKE_PROD Cliente Homologacao
   Producao` (tipo externo) criado com sucesso.
2. `POST /rest/v1/veiculos` — veículo `SMOKE_PROD Veiculo Teste` (placa
   `SMK0P01`) criado, vinculado ao cliente acima.
3. `POST /rest/v1/orcamentos` — orçamento criado (`status=rascunho`,
   `client_request_id` único).
4. `POST /rest/v1/orcamento_itens` — item de R$ 100,00 incluído;
   `orcamentos.valor_total` recalculado automaticamente para 100.00
   (trigger funcionando).
5. `GET /rest/v1/orcamentos?id=eq...` — consulta confirmada, dados
   corretos.
6. RLS: `smoke.prod.executor` tentando `PATCH` direto no orçamento →
   bloqueado (`403, 42501 "permission denied for table orcamentos"`).

**Não avançado para financeiro real** (conforme instrução).

### Preservação dos registros SMOKE_PROD

Decisão desta rodada: os registros **ficam preservados, mas inativados**,
como evidência de homologação — mesmo mecanismo de inativação já usado pelo
sistema (soft delete via `deleted_at`, o mesmo padrão de BR-001 para
clientes inativados, que continuam consultáveis no histórico):

- `clientes` (SMOKE_PROD Cliente): `deleted_at` preenchido.
- `veiculos` (SMK0P01): `deleted_at` preenchido.
- `orcamentos`: permanece em `rascunho` — nunca foi enviado, aprovado nem
  convertido em OS, então não tem efeito operacional; não há campo de
  inativação equivalente para orçamento, e o nome/dados já deixam claro que
  é um registro de teste.
- As 6 contas de smoke test (`profiles.ativo=false`) — preservadas como
  evidência, não deletadas (consistente com BR-043, nenhum DELETE físico
  neste sistema).

**SMOKE = PASSOU. Criação, consulta e RLS validadas em produção com dados
reais do banco de produção (não simulado).**

---

## BACKUP

- Backup automático gerenciado pelo Supabase: **plano de billing do projeto
  não verificado nesta rodada** — não há subcomando de CLI para isso;
  precisa ser confirmado no dashboard (`Settings → Billing` de
  `wtxbodhqyasdlmyoyjur`). **Risco/achado**: se o projeto estiver no plano
  Free, o backup automático diário e o PITR tipicamente não estão
  disponíveis na Supabase — isso precisa ser confirmado pelo responsável
  técnico antes do go-live.
- Backup lógico próprio (método schema=migrations + dados=REST, comprovado
  no RC2 contra DEV/QA): **não executado contra produção nesta rodada** —
  produção hoje só tem configuração administrativa + os registros
  `SMOKE_PROD`, sem massa de dados operacional real ainda; recomendação
  registrada em `docs/PRODUCTION_BACKUP_RESTORE.md` para rodar
  periodicamente assim que a operação real começar.
- `npx supabase db dump --project-ref wtxbodhqyasdlmyoyjur`: mesma
  limitação de infraestrutura do RC2 — sem Docker/`pg_dump` nesta máquina,
  não executável.

`docs/PRODUCTION_BACKUP_RESTORE.md` atualizado com uma seção específica de
produção.

---

## RESTORE

Reinvestigado nesta rodada, mesmo resultado do RC2:

- `docker`, `pg_dump`, `psql`: nenhum disponível (`which` vazio para os
  três).
- Driver Python de Postgres: não verificado de novo (já confirmado ausente
  no RC2, sem mudança de ambiente entre rodadas).
- Criação de projeto Supabase novo só para testar restore: **não
  autorizada nesta rodada** (proibido pelo roteiro sem antes parar e
  reportar) — não criada.

**`RESTORE_TESTED = FALSE`**, explícito, sem simulação de sucesso. Nenhum
`docs/testing/TEST_REPORT_RESTORE.md` foi criado (restore não foi
realmente executado). Continua sendo o maior risco operacional aberto do
sistema antes de operar com dados reais de clientes.

---

## UAT

- `docs/testing/UAT_OFICINA.md` criado — 18 cenários mínimos, linguagem
  operacional, sem nenhum resultado PASSOU/FALHOU preenchido (o UAT real
  ainda não rodou).
- **Não foram criados usuários piloto reais** (encarregado, suporte,
  executor) — o dono do projeto ainda não forneceu nomes/e-mails reais para
  essas pessoas. Pendência explícita para a próxima rodada.
- O smoke test técnico desta rodada (seção SMOKE acima) **não substitui** o
  UAT — usou contas descartáveis, não usuários reais da oficina operando o
  sistema pela interface.

**UAT = NÃO EXECUTADO** (documento pronto, aguardando usuários piloto
reais).

---

## LOGS (observabilidade)

Sem subcomando de CLI para logs (mesma limitação do RC2, sem Docker).
Procedimento documentado: acessar o dashboard do projeto de produção em
*Logs* (ou *Log Explorer*), com seções separadas para Auth, PostgREST
(API), Postgres (Database) e Storage. Não foi possível verificar via
CLI/API os logs do smoke test desta rodada dentro do tempo desta sessão —
registrado como limitação, não simulado.

---

## GATES DE GO-LIVE — avaliação honesta

| Gate | Status |
|---|---|
| Projeto PROD separado do DEV/QA | ✅ Sim |
| Migrations local == remote | ✅ 51/51 |
| Seed QA ausente | ✅ Confirmado |
| Admin real criado | 🟡 Convite enviado, **não aceito** |
| Configuração inicial completa | 🟡 5/6 (checklist pendente, por decisão do dono) |
| Storage validado | ✅ Sim |
| RLS/RPC smoke verde | ✅ Zero bypass |
| Frontend PROD publicado | ❌ **Não** — decisão desta rodada (seção 12) |
| HTTPS/domínio funcionando | ❌ Depende do deploy, que não aconteceu com os valores corretos ainda |
| Backup configurado | 🟡 Plano não verificado; backup lógico não executado contra produção ainda |
| Restore real testado | ❌ **`RESTORE_TESTED = FALSE`** |
| Logs acessíveis | 🟡 Procedimento documentado, não observado continuamente |
| UAT concluído | ❌ Não — sem usuários piloto reais ainda |
| Nenhuma falha crítica/alta aberta | ✅ Nenhuma encontrada nesta rodada (o achado do deploy antigo é uma pendência de decisão, não uma falha de código) |
| AUT-007 formalmente aceito | ✅ Reconfirmado, procedimento documentado |

## STATUS FINAL

# B) PRODUÇÃO CRIADA — NÃO PRONTA PARA GO-LIVE

**Justificativa**: a infraestrutura de produção existe, está corretamente
isolada do DEV/QA, com as 51 migrations aplicadas, configuração de negócio
majoritariamente completa, segurança e Storage validados com evidência
real, e um smoke test funcional executado com sucesso. Isso é
significativamente mais do que "só criada" — já dá para começar a preparar
o UAT assim que os usuários piloto existirem. Mas **C) PRONTA PARA UAT**
não foi escolhido porque ainda há bloqueios reais e não triviais: o admin
real não tem acesso ainda (convite pendente), o frontend de produção não
está publicado com a configuração correta, e o restore nunca foi provado —
esse último é o mesmo risco operacional aberto desde o RC2, sem mudança de
causa raiz. **D) GO-LIVE RECOMENDADO está claramente descartado** nesta
rodada: restore não testado, deploy não publicado com os valores corretos,
UAT não executado, e um achado real (deploy anterior apontando para o
banco errado) que precisa de decisão do dono antes de prosseguir.

### Pendências que impedem avançar para C/D, em ordem de prioridade

1. Dono do projeto decidir o que fazer com o deploy já publicado
   apontando para o ambiente errado (achado desta rodada).
2. Hammed aceitar o convite, definir senha, fazer seu próprio smoke test
   como admin real.
3. Resolver o restore real (Docker/pg_dump disponíveis, ou autorização
   para criar um projeto Supabase descartável).
4. Trazer o commit `0b98fcd` (e os demais desta rodada) para `main` e
   publicar o frontend de produção corretamente — decisão e ação do dono.
5. Confirmar o plano de billing/backup automático do projeto de produção.
6. Dono fornecer nomes/e-mails dos usuários piloto reais para começar o
   UAT.
7. Dono criar os templates de checklist (última peça de configuração
   inicial pendente).
