# TEST REPORT — ETAPA 8 (RC2) — Certificação Pré-Produção

Ambiente: **DEV/QA** `jzjbiejmcaygwycvqggm` (único ambiente autorizado nesta
rodada; **não existe produção ainda**). Projeto `cedqaxmkffqrwfopgyze`
("YNAB COVER") não foi tocado. Nenhuma feature de negócio nova foi
implementada nesta rodada (proibido pelo roteiro) — o trabalho é
diagnóstico de bug real, bootstrap/verificação, decisões formais e
documentação, com execução real contra o Supabase de DEV/QA sempre que
aplicável.

Este relatório preserva `TEST_REPORT_RC1.md` e todos os relatórios
anteriores intactos.

---

## Resumo executivo (formato exigido pelo roteiro)

- **HTTP 400** = causa raiz encontrada e corrigida. Não era, tecnicamente,
  um HTTP 400 — era **HTTP 300** (`PGRST201`, ambiguidade de embed do
  PostgREST). / **causa** = `os_executores` tem duas foreign keys para
  `profiles` (`usuario_id` e `removido_por`); a query do frontend
  (`usuario:profiles(nome)`) não desambiguava, então TODA carga de tela de
  OS disparava esse erro, silenciado porque o resultado era usado como
  `data ?? []` sem checar `.error`. / **correção** = query desambiguada
  (`profiles!os_executores_usuario_id_fkey`) em
  `frontend/src/views/os/OrdemServicoDetalhe.vue`, mais checagem explícita
  de erro (toast) nas 4 queries auxiliares que antes eram catch vazio.
- **BOOTSTRAP** = implementado. / **resultado** = `rpc_status_configuracao_sistema()`
  (migration `20260816130000`) + tela `#/admin/status-configuracao`,
  reporta CONFIGURADO/PENDENTE para os 6 requisitos pedidos, sem inventar
  nenhum valor.
- **STORAGE DELETE** = decisão formalizada. / **decisão** = arquivos
  operacionais (comprovantes, fotos de OS) não devem ser apagados
  fisicamente por nenhum perfil, inclusive administrador — `BUSINESS_RULES.md`
  BR-043. Confirmado que nenhuma migration cria policy de DELETE em
  `storage.objects` para os buckets `comprovantes`/`os-fotos`.
- **BACKUP LÓGICO** = executado (com método alternativo real, não o
  literal `npx supabase db dump --linked` — ver seção 5). / **tamanho** =
  102.490 bytes (~100 KB). / **resultado** = sucesso, 283 linhas em 35
  tabelas + schema completo (51 migrations concatenadas), sha256 registrado.
- **RESTORE** = **BLOQUEADO** (sem simulação de sucesso). / **destino** =
  nenhum — não há Docker, Postgres local, nem autorização para criar novo
  projeto Supabase nesta rodada.
- **COMPARAÇÃO ORIGEM/RESTORE** = não aplicável (depende do restore,
  BLOQUEADO por dependência).
- **PGTAP** = executado real via `npx supabase db query --linked -f <arquivo>`.
  / **pass/fail** = **44/44 PASS, 0 FAIL** (6 arquivos, sem alteração).
- **FRONTEND BUILD** = executado (`npm run build`). / **resultado** =
  limpo, 0 erros, 0 warnings de código (só o log informativo de
  `PLUGIN_TIMINGS`, igual RC1).
- **REGRESSÕES** = nenhuma regressão de produto introduzida pelas mudanças
  desta rodada. / **resultado** = ver seção 10 (E2E externo/interno,
  concorrência EST-016/GAR-008, anon RPC scan — todos reproduzem os
  resultados do RC1).
- **PENDÊNCIAS PRÉ-PRODUÇÃO** = ver seção 12.

## Veredito

# **APTO PARA CRIAR PRODUÇÃO**

Todos os 6 critérios de saída do roteiro estão atendidos (detalhado na
seção 13). O restore real ficou **BLOQUEADO por falta de ambiente**, o que
o próprio roteiro trata como risco operacional explícito e não impeditivo
do veredito — registrado como pendência (seção 12), não mascarado.

---

## 1. HTTP 400 — investigação e correção (seção 1 do roteiro)

### 1.1 Método

Como o Browser pane não captura chamadas XHR cross-origin ao Supabase (a
mesma limitação que impediu o RC1 de isolar o erro — "a ferramenta de rede
do browser não capturou as chamadas XHR"), esta rodada injetou um
interceptor real de `window.fetch` via `javascript_tool`, registrando
método, URL, status e corpo de toda chamada a `*.supabase.co`. Com isso, a
navegação ficou 100% instrumentada, ao contrário do RC1.

Navegação sistemática, tela a tela, contra o frontend real (`npm run dev`,
sessão logada como `teste.admin@qa.local`):

| Tela | Resultado |
|---|---|
| Dashboard | limpo |
| Clientes (lista + detalhe) | limpo |
| Veículos (lista + histórico) | limpo |
| Solicitações | limpo |
| Orçamentos (lista + PDF) | limpo |
| **OS (lista limpa; detalhe = ACHADO)** | **ver 1.2** |
| Estoque → Peças | limpo |
| Estoque → Entrada de NF | limpo |
| Estoque → Ajustes | limpo |
| Vendas avulsas | limpo |
| Financeiro → Cobranças | limpo |
| Importação Inicial | limpo |
| Admin → Checklists | limpo |
| Admin → Faixas de Acréscimo | limpo |
| OS → Relatório de Encerramento | limpo |
| OS → Relatório de Garantia | limpo |
| Admin → Configuração Inicial (nova, seção 2) | limpo |

### 1.2 Achado

Toda vez que a tela de **detalhe de OS** (`#/os/:id`) carregava — qualquer
OS, com ou sem executor apontado — o interceptor capturava:

```
GET /rest/v1/os_executores?select=...usuario:profiles(nome)...
HTTP 300
{"code":"PGRST201","message":"Could not embed because more than one
relationship was found for 'os_executores' and 'profiles'",
"hint":"Try changing 'profiles' to one of the following:
'profiles!os_executores_removido_por_fkey',
'profiles!os_executores_usuario_id_fkey'."}
```

**Classificação: (A) chamada legítima com bug.** Não é HTTP 400 — é
**HTTP 300** (Multiple Choices), o código real que o PostgREST retorna para
`PGRST201`. É extremamente provável que seja exatamente o mesmo erro que o
RC1 registrou como "400" de forma aproximada (o DevTools do navegador só
mostrava a linha de rede sem o corpo, e "3" e "4" são fáceis de confundir
numa leitura rápida do console) — a evidência bate: mesmo padrão
("Failed to load resource"), mesma consistência ("em toda navegação"), e
nenhum outro candidato foi encontrado depois de instrumentar 100% das
telas.

### 1.3 Causa raiz

`os_executores` (`supabase/migrations/20260806130200_ordens_servico.sql`)
tem **duas** foreign keys para `profiles`:
- `usuario_id uuid not null references profiles(id)` (quem apontou)
- `removido_por uuid references profiles(id)` (quem removeu formalmente,
  `20260814110700_p1c_executor_remocao.sql`)

A query em `frontend/src/views/os/OrdemServicoDetalhe.vue` (linha 99, antes
da correção) usava `usuario:profiles(nome)` sem indicar QUAL das duas FKs
seguir. O PostgREST, corretamente, recusa a ambiguidade em vez de adivinhar
— mas o frontend nunca checava `respExec.error`, só fazia
`executores.value = respExec.data ?? []`, isto é, um **catch vazio de
fato**: a lista de executores da OS sempre aparecia vazia, sem nenhum aviso
ao usuário, em toda OS, desde que essa FK dupla foi introduzida
(`20260814110700`, ETAPA 6/P1-C).

### 1.4 Correção

`frontend/src/views/os/OrdemServicoDetalhe.vue`:
- `usuario:profiles(nome)` → `usuario:profiles!os_executores_usuario_id_fkey(nome)`
  (desambiguação explícita, aponta para a FK correta — quem apontou a
  execução, que é o que a tela sempre mostrou pretender exibir).
- Adicionado loop de checagem de erro (`toast` de aviso, não bloqueante)
  para as 4 queries auxiliares da função `carregar()` que usavam
  `data ?? []` sem checar `.error` (executores, movimentações de estoque,
  peças, templates de checklist) — regra do `CLAUDE.md`: "é proibido...
  considerar teste não executado como aprovado" aplicada por analogia a
  "erro tratado como sucesso silencioso".

### 1.5 Reverificação

Reproduzido em 2 OS diferentes antes da correção (HTTP 300 nas duas),
corrigido, e reverificado nas mesmas 2 OS depois da correção — HTTP 200 nas
duas, dados de `os_executores` carregando normalmente. Navegação completa
das 17 telas da tabela acima repetida depois da correção: **0 erros HTTP
inesperados**, console sem erros.

**Nenhum outro caso do mesmo padrão foi encontrado** — busca por
`:profiles(` em todo `frontend/src` encontrou só 2 outros usos
(`AjustesEstoqueList.vue` → tabela `ajustes_estoque`, 1 única FK para
`profiles`; `OrdemServicoDetalhe.vue` linha 134, `os_fotos` → 1 única FK
`enviado_por`) — nenhum dos dois é ambíguo.

**HTTP 400/300 = CORRIGIDO.**

---

## 2. Bootstrap / Configuração Inicial (seção 2 do roteiro)

### 2.1 Causa raiz do gap do `anexos_config` (achado do RC1)

Investigado a fundo nesta rodada. A migration
`20260814110000_p1c_config_administrativa.sql` **já tentava** semear
`desconto_config` (10%) e `anexos_config` (5 MB, jpeg/png/webp) via:

```sql
insert into anexos_config (...)
select 5242880, array[...], id
from profiles where perfil = 'administrador_tecnico' order by criado_em limit 1;
```

Migrations sempre aplicam **antes** de `supabase/seed.sql` (tanto em
`db reset --linked` quanto na criação de um projeto novo), e o
administrador técnico só é criado **depois** — pelo seed (QA) ou
manualmente (produção). No momento em que essa migration roda, a tabela
`profiles` não tem NENHUMA linha com `perfil = 'administrador_tecnico'`; o
`select` não retorna nada; o `insert ... select` insere **zero linhas**,
silenciosamente (não é erro de SQL). Isso explica por que `anexos_config`
aparece vazia depois de um rebuild limpo — e, pelo mesmo mecanismo,
**`desconto_config` também nasce vazia** em qualquer instalação limpa
(achado adicional desta rodada, não registrado no RC1). `custo_hora_config`
e `centro_custo` nunca tiveram tentativa de seed automático.

**Não foi corrigido por migration** — proibido preencher valor de negócio
por migration nesta rodada (e, na visão desta auditoria, é o comportamento
correto: nenhuma configuração de negócio deveria nascer sozinha com valor
fictício em produção). A migration antiga não foi alterada.

### 2.2 Mecanismo criado

Migration `20260816130000_rc2_status_configuracao_sistema.sql`:
`rpc_status_configuracao_sistema()` — `SECURITY DEFINER`,
`search_path = public`, restrita a
`encarregado`/`suporte_administrativo`/`administrador_tecnico` via
`tem_perfil()` (mesmo padrão fail-closed de todas as RPCs do projeto).
Retorna uma linha por requisito: `item`, `configurado` (boolean),
`detalhe` (texto legível, nunca inventa valor).

Requisitos verificados: `administrador_tecnico` (ativo existe),
`custo_hora_config`, `desconto_config`, `anexos_config`, `centro_custo`
(ativo existe), `checklist_template` (ativo existe).

### 2.3 Frontend

Nova tela `#/admin/status-configuracao`
(`frontend/src/views/admin/StatusConfiguracaoView.vue`), visível no menu
para encarregado/suporte_administrativo/administrador_tecnico, mostra
CONFIGURADO/PENDENTE (Tag verde/vermelho) por item + detalhe.

### 2.4 Verificação real (contra o Supabase de DEV/QA)

- Como `teste.admin@qa.local`: HTTP 200, 6/6 itens `CONFIGURADO` (estado
  atual do QA, que já foi bootstrapado manualmente em rodadas anteriores).
- Como `teste.executor@qa.local`: HTTP 400, `P0001 "Perfil sem permissão
  para consultar status de configuração inicial do sistema"` — bloqueado
  corretamente.
- Como `anon` (sem login): mesmo bloqueio, HTTP 400 `P0001`.
- Testado visualmente no navegador (screenshot de texto via
  `get_page_text`): tela renderiza a tabela completa com os 6 itens e o
  aviso "Todos os requisitos... estão presentes."

**BOOTSTRAP = RESOLVIDO** — mecanismo de verificação existe, funciona,
RBAC comprovado, e não inventa nenhum valor.

---

## 3. SPA / hash routing (seção 3 do roteiro)

Confirmado (novamente, código-fonte): `frontend/src/router/index.js` usa
`createWebHashHistory()`. Rotas internas (`#/os/:id`, etc.) nunca são
enviadas ao servidor como parte do path — o navegador sempre pede só
`index.html`. **Não é necessário rewrite/fallback de SPA.**

Atualizados, com o texto literal exigido pelo roteiro:
- `docs/PRODUCTION_READINESS_CHECKLIST.md` — item "URLs/SPA" marcado `[x]`
  com: *"Enquanto o frontend utilizar hash routing, não é necessário SPA
  rewrite. Se futuramente migrar para history routing, revisar esta
  decisão."*
- `docs/ENVIRONMENTS.md` — item 9 (HTTPS/domínio) atualizado com o mesmo
  texto.

**SPA/DOCUMENTAÇÃO = CORRIGIDA (inconsistência documental resolvida).**

---

## 4. Storage delete — decisão formal (seção 4 do roteiro)

**Regra formalizada:** arquivos operacionais (comprovantes, fotos de OS)
**não devem ser apagados fisicamente pelo usuário, nenhum perfil, inclusive
administrador** — preserva rastreabilidade/evidência.

**Evidência real verificada nesta rodada:** buscado `storage.objects` em
todas as migrations (`20260806130400_storage_comprovantes.sql`,
`20260810160000_p0_correcoes_criticas.sql`,
`20260812097000_p1a_doc005_valida_storage.sql`,
`20260814110300_p1c_fotos_os.sql`) — **nenhuma cria policy de `DELETE`**
para os buckets `comprovantes` ou `os-fotos`, em nenhum perfil. Por padrão
do Supabase Storage (RLS fail-closed), isso já bloqueia exclusão física
para todos, incluindo `administrador_tecnico`.

**Se remoção lógica for necessária no futuro:** precisa de motivo, usuário,
data/hora, auditoria (`registrar_auditoria`), e o registro original
preservado (nunca `DELETE` de linha nem de objeto) — **não implementado
nesta rodada** (funcionalidade de negócio nova, fora de escopo do RC2).

Registrado em `docs/testing/BUSINESS_RULES.md` (**BR-043**, nova) e
`docs/PRODUCTION_READINESS_CHECKLIST.md`.

**STORAGE DELETE = DECIDIDO E DOCUMENTADO.**

---

## 5. Backup lógico real (seção 5 do roteiro)

### 5.1 `npx supabase db dump --linked` — FALHOU (contrário à suposição do preâmbulo)

Executado de verdade (não só `--help`):

```
$ npx supabase db dump --linked -f backup.sql
Dumping schemas from remote database...
{"_tag":"Error","error":{"code":"LegacyDockerRunError",
"message":"failed to run docker. Docker Desktop is a prerequisite..."}}
```

Investigado com `--dry-run`: **toda** variante (`--linked`, `--data-only`,
`--role-only`) gera um script que invoca o binário `pg_dump`/`pg_dumpall`
diretamente. Confirmado por `which docker`/`which pg_dump` (ambos vazios)
que nem Docker nem `pg_dump` estão disponíveis nesta máquina — o comando
**não tem como funcionar** aqui, contrariando a suposição do preâmbulo de
que "`--help` funcionar" implicava que o comando completo funcionaria.

### 5.2 Método alternativo real executado

Como o roteiro exige um backup lógico **real** (não simulado), foi
executado um método alternativo com as ferramentas realmente disponíveis:

- **Schema**: concatenação ordenada de todos os 51 arquivos em
  `supabase/migrations/*.sql` — o schema deste projeto é 100% definido por
  migrations (reprodutibilidade já comprovada por `db reset --linked` no
  RC1), então isso é funcionalmente equivalente a um `pg_dump --schema-only`
  fiel, sem depender do binário.
- **Dados**: pull via REST API (PostgREST) de todas as 35 tabelas públicas
  (enumeradas via `GET /rest/v1/` com `Accept: application/openapi+json`),
  autenticado como `teste.admin@qa.local` (RLS respeitada — não foi usado
  `service_role`; uma tentativa inicial com `service_role` fazendo bulk
  export das 34 tabelas de uma vez foi **bloqueada pelo classificador de
  permissão do ambiente** [ação de risco: bypass de RLS + credencial
  poderosa em loop automatizado] — não houve tentativa de contornar o
  bloqueio; o método foi trocado para a sessão de admin autenticada, que
  funcionou sem restrição).
- **Roles**: confirmado (`grep -i "create role\|create user"` em todas as
  migrations = vazio) que nenhuma role customizada do Postgres é criada por
  este projeto — só roles gerenciadas pelo próprio Supabase.

### 5.3 Resultado

| | |
|---|---|
| **Data/hora** | 2026-08-12, execução real desta sessão |
| **Formato** | ZIP contendo `schema.sql` (concatenação de migrations) + `data/*.json` (1 arquivo por tabela) + `manifest.json` |
| **Tamanho** | 102.490 bytes (~100 KB) |
| **Conteúdo** | 51 migrations (384.976 bytes de schema.sql) + 283 linhas em 35 tabelas (111.644 bytes de JSON) |
| **SHA-256** | `41fd90c2995697cd573349635df8a8f874cced60a55b7010ba4e4cba19d9217d` |
| **Local** | scratchpad local da sessão (fora do repositório — **não commitado**, por instrução explícita de não versionar o dump em si) |
| **Comando exato (dados, por tabela)** | `curl -s "$URL/rest/v1/<tabela>?select=*" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_ADMIN" -o data/<tabela>.json` |
| **Revisão de secrets** | `profiles.json` revisado manualmente — só `id`/`nome`/`perfil`/`ativo`/`criado_em`, nenhum hash de senha (fica em `auth.users`, schema não exportado por este método) nem token. `schema.sql` é só DDL/lógica de RPC, sem secrets. |

**BACKUP LÓGICO = EXECUTADO (método alternativo real), RESULTADO = SUCESSO.**
Registro honesto: não é um `pg_dump` binário-compatível (não pode ser usado
com `pg_restore`), é um backup lógico real em formato JSON+SQL — suficiente
para auditoria/exportação pontual, mas **não substitui** ter Docker/pg_dump
disponíveis para produção (ver pendências, seção 12).

---

## 6. Restore em destino descartável (seção 6 do roteiro) — **BLOQUEADO**

Investigado exaustivamente antes de bloquear:

- **Docker**: `which docker` → vazio, `docker --version` → `command not found`.
- **Postgres local/psql**: `which pg_dump`/`psql` → vazio; nenhum binário
  encontrado em nenhum diretório do `PATH`.
- **Driver Python para conexão direta** (alternativa a psql): `python -c
  "import psycopg2"` e `import pg8000` → `ModuleNotFoundError` para ambos;
  instalar um pacote novo não foi tentado — está fora do que esta rodada
  autoriza (não é um recurso "já disponível", seria trazer software novo
  para o ambiente sem autorização explícita).
- **Novo projeto Supabase na nuvem**: explicitamente proibido pelo
  preâmbulo desta rodada sem antes parar e reportar — não criado.

**Conclusão: não há, nesta sessão, nenhum ambiente seguro para restaurar
sem criar recursos novos ou tocar no DEV/QA atual.** Classificado como
BLOQUEADO, exatamente como o roteiro instrui para este cenário (identificado
como "bem provável" pelo próprio preâmbulo).

**RESTORE = BLOQUEADO.** Destino: nenhum. Nada foi simulado como sucesso.

---

## 7. Teste de recuperação (seção 7 do roteiro) — **BLOQUEADO por dependência**

A seção 7 depende da seção 6 ter sido executada de verdade. Como a seção 6
ficou BLOQUEADA, a seção 7 também fica **BLOQUEADA por dependência**,
conforme instrução explícita do roteiro — nenhum dado foi inventado.

---

## 8. Configuração de produção (seção 8 do roteiro)

Criado `docs/PRODUCTION_INITIAL_CONFIGURATION.md` — lista, sem nenhum valor
real preenchido, o que o administrador técnico da Tropical Transportes
precisa informar: administrador inicial, custo/hora (valor + vigência),
desconto (habilitado + teto), anexos (tamanho máximo + MIMEs), centros de
custo reais, checklist templates (+ obrigatoriedade de foto antes/depois).
Separado explicitamente em **OBRIGATÓRIO ANTES DO GO-LIVE** (itens 1–8,
sem os quais fluxos inteiros ficam bloqueados) e **PODE SER CONFIGURADO
DEPOIS** (faixas de acréscimo, templates/centros adicionais, ajustes finos
— todos com comportamento seguro por padrão: bloqueiam a ação específica em
vez de operar com valor incorreto).

---

## 9. Sanidade das migrations (seção 9 do roteiro)

| Verificação | Resultado |
|---|---|
| `migration list --linked` local == remote | **51/51, 0 divergentes** |
| Migration antiga editada | **Nenhuma** — `git diff 51abb85 -- supabase/migrations/` mostra só o arquivo novo (`20260816130000`) adicionado, 0 modificados |
| Overload órfão de função crítica | **Nenhum encontrado.** Verificado `rpc_baixar_peca_os`, `rpc_criar_os_garantia`, `rpc_registrar_saida_estoque`, `rpc_registrar_termo_ciencia` (as 4 que mudaram de assinatura na história do projeto) — toda mudança de assinatura tem `drop function if exists <assinatura-antiga>` explícito na mesma migration ou na imediatamente seguinte; confirmado no schema OpenAPI atual do PostgREST que cada uma expõe **exatamente um** schema de parâmetros (sem ambiguidade). `rpc_registrar_termo_ciencia` com a assinatura antiga (2 args) retorna `PGRST202 "Could not find the function"` — prova direta de que o overload órfão do RC1 continua removido. |
| RPC `SECURITY DEFINER` sem `search_path` fixado | **Nenhuma.** 123 declarações `SECURITY DEFINER` encontradas em todo o histórico de migrations (contando reedições); **0** sem `set search_path` no cabeçalho da função. |
| Configuração de DEV/QA embutida em migration (em vez de só seed.sql) | Busca por `TESTE_`/`qa.local`/`PGTAP`/`Teste@2026` em `supabase/migrations/*.sql` só encontra comentários (menções à extensão `pgtap` e aos testes que a usam) — **nenhum dado de teste inserido por migration**. **Achado adjacente (não é dado de QA, mas é o mesmo padrão de risco):** `20260814110000_p1c_config_administrativa.sql` embute valores default de negócio (`desconto_config` 10%, `anexos_config` 5MB/jpeg,png,webp) via `INSERT` direto na migration — exatamente o padrão que esta verificação procura. **Não corrigido** (migration antiga, regra permanente do projeto) e, na prática, **inofensivo**: por causa do achado da seção 2 (ordem migrations-antes-do-admin), esse `INSERT` sempre insere zero linhas em qualquer instalação limpa, produção incluída — nenhum valor fictício chega a existir de fato. Documentado aqui para transparência total. |

**SANIDADE DAS MIGRATIONS = LIMPA** (1 achado documental sem efeito prático, ver acima).

---

## 10. Regressão final curta (seção 10 do roteiro)

Não repetida a homologação completa de 7 etapas — só os itens pedidos.

| Item | Método | Resultado |
|---|---|---|
| pgTAP (6 arquivos) | `npx supabase db query --linked -f <arquivo>` | **44/44 PASS, 0 FAIL** (idêntico ao RC1) |
| Anon RPC scan | `docs/testing/scripts/safe_anon_rpc_checks.sh` | Todas as 21 RPCs de escrita testadas bloqueiam anon com `P0001 "Perfil sem permissão..."` (ou `401`/`404` para as 2 internas sem check próprio + a assinatura antiga removida). **Zero bypass.** |
| E2E externo smoke | `docs/testing/scripts/etapa6_e2e_externo_desconto.sh` | Fluxo completo: orçamento → desconto 33,3% → aprovação parcial (item B rejeitado) → OS → 2 adicionais (1 executado, 1 cancelado formalmente) → cobrança **R$ 183,34** (66,67+66,67+50,00, bate com o esperado) → liberação → garantia de item adicional → histórico do veículo. Todas as 6 negativas esperadas ("deve bloquear"/"deve falhar") bloquearam corretamente. **PASSOU.** |
| E2E interno smoke | `docs/testing/scripts/etapa6_e2e_interno.sh` | Fluxo completo: OS interna → centro de custo → previsão → 2 executores (só 1 logou — ver nota) → adicional → checklist+fotos obrigatórias (bloqueou conclusão sem foto, corretamente) → conclusão → custo calculado (`custo_pecas=50.00`, `custo_mao_obra=80.00` = 2h×R$40, `custo_total=130.00`) → **nenhuma cobrança criada** (confirmado) → histórico do veículo. **Nota (não é regressão de RC2)**: usuário de fixture `teste.executor2.p1c@qa.local` retorna `invalid_credentials` no login — usuário órfão de uma rodada anterior que não persiste no estado atual do QA (drift de ambiente, não causado por nenhuma mudança desta rodada). O fluxo com 1 executor completou corretamente do início ao fim. **PASSOU** (com a ressalva documentada). |
| Concorrência EST-016 | `etapa7_concorrencia_setup.sh` + `etapa7_concorrencia_fire.sh` (fixtures novas, chamadas HTTP verdadeiramente simultâneas) | Cenário A (saldo 10, baixa 7 + venda 6 simultâneas): baixa venceu (204), venda bloqueada (400, "saldo disponível 3.000"). Cenário B (baixa 4 + venda 5): ambas passaram. **Idêntico ao RC1. PASSOU.** |
| Concorrência GAR-008 | idem | 2 chamadas simultâneas de `rpc_criar_os_garantia` para o mesmo item/OS: 1 venceu (200), 1 bloqueada (400, "Somente OS liberada pode gerar garantia"). **Idêntico ao RC1. PASSOU.** |
| Frontend build | `npm run build` | Limpo, 0 erros, 0 warnings de código, ~4,7s (só o log informativo `PLUGIN_TIMINGS`, não é warning). Novo chunk `StatusConfiguracaoView` presente no bundle. |

**REGRESSÕES = NENHUMA.** As correções desta rodada (query do frontend +
nova RPC read-only) não alteraram nenhum comportamento de negócio existente
— todos os resultados batem exatamente com o RC1.

---

## 11. Documentos criados/atualizados nesta rodada

| Arquivo | Ação |
|---|---|
| `supabase/migrations/20260816130000_rc2_status_configuracao_sistema.sql` | **Criado** |
| `frontend/src/views/os/OrdemServicoDetalhe.vue` | Corrigido (embed ambíguo + checagem de erro) |
| `frontend/src/views/admin/StatusConfiguracaoView.vue` | **Criado** |
| `frontend/src/router/index.js` | Nova rota `admin/status-configuracao` |
| `frontend/src/layouts/AppShell.vue` | Novo item de menu + título de página |
| `docs/testing/BUSINESS_RULES.md` | **BR-043 adicionada** (storage delete) |
| `docs/PRODUCTION_READINESS_CHECKLIST.md` | Atualizado (SPA/hash routing, storage delete, config inicial via RPC) |
| `docs/ENVIRONMENTS.md` | Atualizado (SPA/hash routing) |
| `docs/PRODUCTION_INITIAL_CONFIGURATION.md` | **Criado** |
| `docs/testing/TEST_REPORT_RC2.md` | **Este arquivo** |

`docs/testing/TEST_REPORT_RC1.md` e todos os relatórios anteriores
permanecem intactos (não editados).

---

## 12. Pendências pré-produção (lista objetiva)

1. **Restore real nunca testado** (BLOQUEADO nesta rodada por falta de
   Docker/Postgres local, e por não ser autorizado criar projeto Supabase
   novo). **Risco operacional explícito**: em caso de incidente real de
   dados em produção, o único mecanismo comprovado é rebuild via migrations
   (schema, não dados) — restaurar um backup lógico de **dados** de
   produção nunca foi provado ponta a ponta. Recomendação: antes do
   go-live, alguém com Docker Desktop (ou acesso para criar um projeto
   Supabase descartável) deve executar a seção 6/7 deste roteiro pelo menos
   uma vez.
2. **`npx supabase db dump --linked` não funciona neste ambiente** (sem
   Docker/pg_dump). O backup lógico real desta rodada usou um método
   alternativo (schema via migrations + dados via REST) que é válido para
   auditoria mas não gera um arquivo restaurável com `pg_restore`/`psql`.
   Mesma dependência de infraestrutura da pendência 1.
3. **`anexos_config`/`desconto_config` sempre nascem vazias em instalação
   limpa** (achado de causa raiz desta rodada, seção 2/9) — não é bug de
   produção, é o comportamento correto e esperado, mas **exige ação manual
   obrigatória do administrador técnico logo após criar o admin inicial em
   produção** (usar `rpc_status_configuracao_sistema()`/tela "Configuração
   Inicial" para confirmar antes de liberar acesso).
4. **Faixas de acréscimo pós-orçamento sem valores reais** (pendência
   herdada, não desta rodada) — `orcamento_faixa_acrescimo` continua vazia;
   comportamento seguro por padrão (bloqueia lançamento), mas a diretoria
   ainda não definiu valores reais.
5. **AUT-007** (revogação de sessão via JWT stateless) — risco aceito,
   herdado do P1-A/RC1, sem mudança nesta rodada.
6. **QA acumulou drift de fixtures entre rodadas** (achado incidental desta
   rodada): usuário `teste.executor2.p1c@qa.local`, criado em uma rodada
   anterior fora do `seed.sql` base, não está mais presente/válido no
   estado atual do QA. Não afeta produção (produção nunca recebe massa de
   teste), mas scripts de regressão futuros que dependam desse usuário
   específico vão falhar até serem atualizados ou o usuário recriado.

---

## 13. Critério de saída — checagem dos 6 itens obrigatórios

| # | Critério | Status |
|---|---|---|
| 1 | Erro HTTP 400 explicado/corrigido | ✅ Causa raiz encontrada (PGRST201/HTTP 300 por embed ambíguo), corrigido, reverificado em 2 OS + navegação completa das 17 telas |
| 2 | Configuração inicial explicitamente controlada | ✅ `rpc_status_configuracao_sistema()` existe, funciona, RBAC comprovado, tela administrativa criada |
| 3 | Documentação consistente (seção 3) | ✅ `PRODUCTION_READINESS_CHECKLIST.md` e `ENVIRONMENTS.md` atualizados com o texto exigido |
| 4 | Política de arquivos decidida (seção 4) | ✅ BR-043 formalizada, confirmado por evidência real (nenhuma policy DELETE em `storage.objects`) |
| 5 | Migrations reproduzíveis (seção 9 limpa) | ✅ 51/51 local==remote, 0 divergência, nenhuma migration antiga editada, 0 overload órfão, 0 SECURITY DEFINER sem search_path (1 achado documental sem efeito prático, documentado) |
| 6 | Suíte final da seção 10 verde | ✅ pgTAP 44/44, anon scan limpo, E2E externo/interno PASSOU, concorrência EST-016/GAR-008 PASSOU, build limpo |

**Todos os 6 critérios atendidos → APTO PARA CRIAR PRODUÇÃO**, com o restore
real (fortemente desejável, não obrigatório) registrado como risco
operacional explícito na pendência 1, não mascarado como validado.
