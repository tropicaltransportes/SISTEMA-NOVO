# ERP Oficina — Tropical Transportes (Petrolina-PE)

## Contexto

A Tropical Transportes opera frota própria (90+ veículos) e atende clientes externos eventuais na sua oficina. Hoje o controle de manutenção passa por um dashboard PCM em Google Sheets/Apps Script, que **não será substituído**. Este projeto cria um ERP web independente para controlar o ciclo completo de manutenção: solicitação → orçamento → OS → execução → estoque → venda avulsa → cobrança → garantia → indicadores. O objetivo é dar rastreabilidade, controle de estoque sem ruptura/negativação, e visibilidade financeira/operacional à diretoria, com custo de infraestrutura zero e manutenção sustentável por um único desenvolvedor.

Decisões já confirmadas com o usuário antes deste plano:
- **Acréscimos pós-aprovação de orçamento**: faixas/percentuais reais não existem ainda. Modelo como tabela configurável (`orcamento_faixa_acrescimo`) com exemplo estrutural fictício — **pendência real para a diretoria definir os valores**.
- **Escopo fiscal**: o sistema controla cobranças e venda avulsa apenas internamente (não fiscal). Emissão de NF-e/NFC-e real, se necessária, permanece em sistema fiscal/contábil externo já usado pela empresa. Isso mantém o projeto dentro do escopo "custo zero" sem certificado digital/SEFAZ.
- **Migração de dados**: haverá importação inicial única (via planilha CSV) de veículos da frota própria e clientes existentes, na Fase 1 (Fundação). Sem integração contínua com o PCM.

---

## 1. Decisões Arquiteturais

### 1.1 Frontend: Vue 3 + Vite (SPA), sem SSR

Justificativa nos três critérios exigidos:

- **(a) Menor curva de aprendizado para um único dev**: Vue usa Single-File Components com template HTML quase puro + `<script setup>` reativo (`ref`/`computed`), sem a sobrecarga conceitual de Server Components, hooks encadeados ou runtimes duais (server/client) que o Next.js exige. Não há necessidade de aprender renderização no servidor: como o ERP é uma aplicação interna autenticada (sem requisito de SEO), a aplicação é uma SPA pura consumindo o Supabase JS SDK diretamente do navegador — a "camada backend-API" já é o próprio Supabase (PostgREST + RPC), então o dev não precisa escrever nem operar uma API própria.
- **(b) Documentação madura e extensa**: a documentação oficial do Vue é reconhecida como uma das mais completas e didáticas do ecossistema front-end, com guia progressivo (iniciante → avançado) e exemplos interativos. Supabase mantém quickstart oficial para Vue.
- **(c) Sem infraestrutura de build complexa**: Vite (base do Vue 3) tem configuração mínima (zero-config na maioria dos casos), build rápido, e o resultado final é um conjunto de arquivos estáticos (`dist/`) — sem necessidade de runtime Node no servidor de hospedagem.

Descartados:
- **Next.js**: exige entender App Router, Server Components, Server Actions e edge runtime — complexidade desnecessária aqui, já que não há necessidade de SSR/SEO e o "backend" já é o Supabase. Adicionaria uma camada de servidor Node só para não ser usada.
- **SvelteKit**: sintaxe mais enxuta, mas ecossistema de componentes prontos para telas densas de ERP (data grids, formulários complexos, máscaras) é menor que o de Vue (PrimeVue, Vuetify), o que pesa mais para este projeto (muitas telas de listagem/filtro/formulário) do que a curva de aprendizado ligeiramente menor.

Biblioteca de componentes sugerida: **PrimeVue** (DataTable com paginação/filtro server-side, formulários, upload) — reduz código repetitivo nas ~10 telas de listagem do sistema.

### 1.2 Hospedagem: Vercel (ou Netlify) — plano gratuito, hospedagem estática

Como o frontend é uma SPA compilada para arquivos estáticos (sem servidor Node em runtime), tanto Vercel quanto Netlify servem o `dist/` via CDN sem processo de servidor "dormindo" — **não há cold start**, ao contrário de serviços que mantêm um processo web ativo (ex: Render free web service, explicitamente evitado). Recomendo Vercel pelo deploy automático via Git e preview deployments por PR, mas Netlify é equivalente para este caso de uso.

### 1.3 Backend/Banco: Supabase Free Tier

- PostgreSQL com Row Level Security em todas as tabelas de negócio.
- Supabase Auth (e-mail/senha) para os 5 perfis; convite manual de usuários (sem cadastro público).
- Tabela `profiles` (1:1 com `auth.users`) carrega o perfil (`role`) usado pelas políticas RLS.
- Supabase Storage para anexos (comprovantes de autorização, fotos de diagnóstico, termos assinados).
- RPCs (funções `SECURITY DEFINER` em PL/pgSQL) para as operações que exigem atomicidade: baixa de estoque, cálculo de custo médio ponderado móvel, geração de cobrança a partir de OS/venda avulsa.
- Migrations versionadas via Supabase CLI (`supabase/migrations/*.sql`) em repositório Git.

### 1.4 Segurança e Backup — riscos de free tier a declarar

- **Pausa por inatividade**: projetos Supabase gratuitos são pausados após um período sem requisições (atualmente ~7 dias) e a retomada não é automática na primeira requisição — exige reativação manual no painel. Mitigação: um job agendado leve (ex: GitHub Actions `schedule`, 1x/dia) fazendo uma consulta trivial autenticada para manter o projeto ativo. **Declarado como risco explícito**, já que uso "baixo volume" pode ter janelas de inatividade (feriados prolongados).
- **Backup**: o free tier não inclui Point-in-Time Recovery (recurso pago). Mitigação: `pg_dump` lógico agendado (ex: GitHub Actions diário) salvando o dump em um repositório privado ou bucket gratuito, com retenção rotativa (ex: últimos 14 dias).
- **Storage**: limite de 1GB no free tier — fotos de diagnóstico e comprovantes devem ter compressão/redimensionamento no upload para não esgotar a cota rapidamente. Risco a monitorar conforme volume de uso cresce.
- RLS é a única linha de defesa de autorização (não há camada de API própria) — toda regra de negócio de acesso deve estar em política SQL, nunca só no frontend.

---

## 2. Modelo de Dados Relacional (visão por módulo)

Convenções: todas as PKs são `uuid default gen_random_uuid()`; timestamps `timestamptz`; exclusão lógica via `deleted_at timestamptz null` onde aplicável (nunca `DELETE` físico em entidades com histórico).

### 2.1 Identidade e Perfis

```sql
create type perfil_usuario as enum ('executor','encarregado','suporte_administrativo','diretoria','administrador_tecnico');

create table profiles (
  id uuid primary key references auth.users(id),
  nome text not null,
  perfil perfil_usuario not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
```

### 2.2 Clientes e Veículos

```sql
create type tipo_cliente as enum ('interno','externo');

create table clientes (
  id uuid primary key default gen_random_uuid(),
  tipo tipo_cliente not null,
  nome text not null,
  documento text, -- CPF/CNPJ, null para o registro interno da frota própria
  telefone text,
  email text,
  deleted_at timestamptz
);
-- Linha única tipo='interno' representa a própria Tropical Transportes (frota própria).

create table veiculos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  placa text not null,
  prefixo text, -- identificador interno da frota, ex: "CM-045"
  modelo text,
  ano int,
  deleted_at timestamptz,
  unique (placa)
);
create index idx_veiculos_placa on veiculos (placa) where deleted_at is null;
create index idx_veiculos_prefixo on veiculos (prefixo) where deleted_at is null;
```

### 2.3 Solicitações de Serviço

```sql
create type status_solicitacao as enum ('aberta','em_analise','convertida_orcamento','convertida_os','cancelada');

create table solicitacoes_servico (
  id uuid primary key default gen_random_uuid(),
  veiculo_id uuid not null references veiculos(id),
  descricao text not null,
  status status_solicitacao not null default 'aberta',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
```

### 2.4 Orçamentos (imutáveis, versionados)

```sql
create type status_orcamento as enum ('rascunho','enviado','aprovado','rejeitado','substituido');

create table orcamentos (
  id uuid primary key default gen_random_uuid(),
  solicitacao_id uuid references solicitacoes_servico(id),
  veiculo_id uuid not null references veiculos(id),
  cliente_id uuid not null references clientes(id),
  orcamento_raiz_id uuid references orcamentos(id), -- aponta para a V1; null na própria V1
  versao int not null default 1,
  status status_orcamento not null default 'rascunho',
  valor_total numeric(12,2) not null default 0,
  autorizado_por_nome text, -- obrigatório para cliente externo antes de aprovado
  autorizado_em timestamptz,
  comprovante_path text, -- Supabase Storage, obrigatório para cliente externo
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
-- Regra de imutabilidade: após status IN ('enviado','aprovado'), nenhuma coluna de conteúdo
-- pode ser alterada via UPDATE comum — apenas via trigger que bloqueia e orienta criar nova versão.

create table orcamento_itens (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references orcamentos(id),
  peca_id uuid references pecas(id), -- null se for item de mão de obra
  descricao text not null,
  quantidade numeric(10,3) not null,
  valor_unitario numeric(12,2) not null,
  valor_total numeric(12,2) generated always as (quantidade * valor_unitario) stored
);

-- Faixas de acréscimo pós-aprovação — CONFIGURÁVEL, valores abaixo são PLACEHOLDER FICTÍCIO.
create table orcamento_faixa_acrescimo (
  id uuid primary key default gen_random_uuid(),
  valor_min numeric(12,2) not null,
  valor_max numeric(12,2), -- null = sem limite superior na faixa
  percentual_max numeric(5,2) not null, -- ex: 10.00 = 10%
  ativo boolean not null default true
);
-- Exemplo estrutural (NÃO usar como valor real de negócio):
-- ('0.00', '1000.00', 15.00)  -- ilustrativo
-- ('1000.01', '5000.00', 10.00) -- ilustrativo
-- Teto absoluto fixo de R$ 5.000,00 aplicado independentemente da faixa (regra já confirmada).

create table orcamento_acrescimos (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references orcamentos(id),
  valor_acrescimo numeric(12,2) not null,
  justificativa text not null,
  aprovado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
  -- CHECK/trigger valida contra orcamento_faixa_acrescimo e teto de R$ 5.000,00
);
```

### 2.5 Ordens de Serviço e Execução

```sql
create type status_os as enum (
  'aberta','em_diagnostico','aguardando_aprovacao','em_execucao',
  'aguardando_teste','concluida','liberada','reaberta_garantia','cancelada'
);
create type tipo_os as enum ('interna','externa');
create type etapa_execucao as enum ('diagnostico','execucao','teste','revisao');

create table ordens_servico (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid references orcamentos(id), -- obrigatório se tipo='externa'
  veiculo_id uuid not null references veiculos(id),
  cliente_id uuid not null references clientes(id),
  tipo tipo_os not null,
  status status_os not null default 'aberta',
  os_origem_id uuid references ordens_servico(id), -- preenchido só em retorno de garantia
  data_abertura timestamptz not null default now(),
  data_liberacao timestamptz,
  criado_por uuid not null references profiles(id)
);

create table os_executores (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  usuario_id uuid not null references profiles(id),
  etapa etapa_execucao not null,
  inicio timestamptz not null,
  fim timestamptz,
  observacao text
);

create table checklist_templates (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  ativo boolean not null default true
);
create table checklist_template_itens (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references checklist_templates(id),
  descricao text not null,
  obrigatorio boolean not null default true
);
create table os_checklist_respostas (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  template_item_id uuid not null references checklist_template_itens(id),
  ok boolean not null default false,
  respondido_por uuid references profiles(id),
  respondido_em timestamptz
);
-- Liberação técnica (status -> 'concluida') condicionada: todos os itens obrigatórios com ok=true.
```

### 2.6 Estoque (Custo Médio Ponderado Móvel, sem negativação)

```sql
create table pecas (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  descricao text not null,
  unidade text not null default 'UN',
  saldo_atual numeric(12,3) not null default 0,
  custo_medio numeric(12,4) not null default 0,
  estoque_minimo numeric(12,3) not null default 0,
  deleted_at timestamptz,
  constraint saldo_nao_negativo check (saldo_atual >= 0)
);

create type tipo_movimento_estoque as enum ('entrada','saida','estorno_entrada','estorno_saida');
create type origem_movimento as enum ('nf_entrada','os','venda_avulsa','estorno');

create table estoque_movimentos (
  id uuid primary key default gen_random_uuid(),
  peca_id uuid not null references pecas(id),
  tipo tipo_movimento_estoque not null,
  origem_tipo origem_movimento not null,
  origem_id uuid not null, -- id da NF, OS, venda avulsa ou movimento estornado
  quantidade numeric(12,3) not null,
  custo_unitario numeric(12,4) not null,
  saldo_resultante numeric(12,3) not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
-- Ledger append-only: correções somente via novo registro tipo 'estorno_*', nunca UPDATE/DELETE.

create type status_nf as enum ('rascunho','confirmada','estornada');

create table notas_fiscais_entrada (
  id uuid primary key default gen_random_uuid(),
  numero text not null,
  fornecedor text not null,
  status status_nf not null default 'rascunho',
  data_emissao date not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
create table nf_entrada_itens (
  id uuid primary key default gen_random_uuid(),
  nf_id uuid not null references notas_fiscais_entrada(id),
  peca_id uuid not null references pecas(id),
  quantidade numeric(12,3) not null,
  valor_unitario numeric(12,4) not null
);
```

**Concorrência**: toda baixa/entrada de estoque passa por uma RPC (`SECURITY DEFINER`) que executa `SELECT saldo_atual FROM pecas WHERE id = $1 FOR UPDATE` dentro de uma transação, valida `saldo_atual - quantidade >= 0`, recalcula o custo médio ponderado móvel, grava o movimento e atualiza `pecas`. A validação de saldo nunca ocorre só no frontend. Isolamento `READ COMMITTED` com `FOR UPDATE` é suficiente aqui (lock de linha serializa as duas OS concorrentes na mesma peça); `SERIALIZABLE` é alternativa se o padrão de acesso crescer para transações multi-tabela conflitantes.

### 2.7 Venda Avulsa de Peças

```sql
create table vendas_avulsas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  status text not null default 'concluida',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
create table venda_avulsa_itens (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references vendas_avulsas(id),
  peca_id uuid not null references pecas(id),
  quantidade numeric(12,3) not null,
  valor_unitario numeric(12,2) not null
);
```

### 2.8 Financeiro (Cobranças, Parcelas, Recebimentos)

```sql
create type status_cobranca as enum ('aberta','parcial','quitada','vencida','cancelada');

create table cobrancas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  valor_total numeric(12,2) not null,
  status status_cobranca not null default 'aberta',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);
-- Uma cobrança nasce só de OS concluída (tipo='externa') e/ou venda avulsa; N:N via origem.
create table cobranca_origens (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id),
  os_id uuid references ordens_servico(id),
  venda_avulsa_id uuid references vendas_avulsas(id),
  check (num_nonnulls(os_id, venda_avulsa_id) = 1)
);

create type status_parcela as enum ('pendente','paga','atrasada','cancelada');
create table parcelas (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id),
  numero_parcela int not null,
  valor numeric(12,2) not null,
  vencimento date not null,
  status status_parcela not null default 'pendente'
);
create table recebimentos (
  id uuid primary key default gen_random_uuid(),
  parcela_id uuid not null references parcelas(id),
  valor_recebido numeric(12,2) not null,
  forma_pagamento text not null,
  data_recebimento date not null,
  criado_por uuid not null references profiles(id)
);
create table termos_ciencia_debito (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id),
  arquivo_path text not null,
  assinado_em timestamptz not null default now()
);
-- Liberação física do veículo (ordens_servico.data_liberacao) exige, quando tipo='externa':
-- cobranca.status = 'quitada' OU parcelas formalizadas OU termo de ciência registrado.
```

### 2.9 Garantia

```sql
-- Modelada via ordens_servico.os_origem_id (2.5). Regra de negócio:
-- nova OS de garantia: tipo = mesmo da original, valor cliente R$ 0,00 (itens com valor_unitario
-- travado em 0 na cobrança, mas custo real registrado nos movimentos de estoque/apontamento
-- para apuração interna). Prazo: data_liberacao da OS original + 90 dias, validado antes de
-- permitir criação da OS de garantia vinculada.
```

---

## 3. Máquinas de Estado

| Entidade | Estados Possíveis | Transições Válidas | Gatilhos |
|---|---|---|---|
| Orçamento | Rascunho, Enviado, Aprovado, Rejeitado, Substituído | Rascunho→Enviado; Enviado→Aprovado; Enviado→Rejeitado; Aprovado→Substituído (nova versão criada) | Enviado: encarregado envia ao cliente. Aprovado: registro de autorização (nome + comprovante, se externo). Substituído: criação de nova versão (V2+) referenciando `orcamento_raiz_id` |
| Ordem de Serviço | Aberta, Em Diagnóstico, Aguardando Aprovação, Em Execução, Aguardando Teste, Concluída, Liberada, Reaberta (Garantia), Cancelada | Aberta→Em Diagnóstico; Em Diagnóstico→Aguardando Aprovação (se orçamento adicional necessário) ou →Em Execução; Aguardando Aprovação→Em Execução; Em Execução→Aguardando Teste; Aguardando Teste→Concluída; Concluída→Liberada; Liberada→Reaberta (Garantia, nova OS vinculada); qualquer estado anterior a Em Execução→Cancelada | Em Diagnóstico: executor inicia apontamento. Aguardando Aprovação: acréscimo detectado. Concluída: checklist obrigatório 100% ok. Liberada: condição financeira satisfeita (interna: sempre liberável; externa: quitação/parcelamento/termo). Reaberta: defeito relatado dentro de 90 dias |
| Cobrança | Aberta, Parcial, Quitada, Vencida, Cancelada | Aberta→Parcial (recebimento parcial); Parcial→Quitada (soma recebimentos = valor_total); Aberta/Parcial→Vencida (parcela com vencimento < hoje e status pendente); Aberta→Cancelada | Parcial/Quitada: inserção de `recebimentos`. Vencida: job/verificação de data em relação a `parcelas.vencimento` |
| Nota Fiscal de Entrada | Rascunho, Confirmada, Estornada | Rascunho→Confirmada (gera `estoque_movimentos` tipo 'entrada'); Confirmada→Estornada (gera `estoque_movimentos` tipo 'estorno_entrada') | Confirmada: suporte administrativo valida itens e confirma. Estornada: erro identificado pós-confirmação — nunca edição direta dos itens já confirmados |
| Movimento de Estoque (ledger) | Entrada, Saída, Estorno de Entrada, Estorno de Saída | Criado uma única vez por RPC; nunca transiciona — correções são um novo registro de estorno referenciando o original | Entrada: NF confirmada. Saída: OS ou Venda Avulsa concluída. Estorno: erro operacional identificado |

---

## 4. Matriz de Permissões RBAC/RLS

| Perfil | Solicitações | Orçamentos | OS | Estoque | Financeiro | Garantia | Dashboard | Usuários/Config |
|---|---|---|---|---|---|---|---|---|
| Executor | Ler, Criar | Ler | Ler, Apontar horas, Responder checklist | Ler (saldo) | - | Ler (OS vinculada) | - | - |
| Encarregado | Ler, Criar, Aprovar | Ler, Criar, Aprovar, Versionar, Registrar acréscimo | Ler, Aprovar técnica, Reabrir, Liberar (técnico) | Ler | Ler | Ler, Criar (OS de garantia) | Ler (operacional) | - |
| Suporte Administrativo | Ler, Criar | Ler, Anexar comprovante/autorização | Ler | Ler, Criar/Confirmar/Estornar NF, Baixar (venda avulsa) | Ler, Criar cobrança, Registrar recebimento, Emitir Termo de Ciência | Ler | Ler (financeiro/estoque) | - |
| Diretoria | Ler | Ler | Ler | Ler | Ler | Ler | Ler (todos os indicadores, com filtros) | - |
| Administrador Técnico | Ler | Ler | Ler | Ler | Ler | Ler | Ler | Ler, Criar, Editar, Gerenciar políticas RLS |

Regra transversal: Diretoria não possui nenhuma política de `INSERT`/`UPDATE`/`DELETE` em nenhuma tabela — apenas `SELECT`. Ausência de política para uma operação em uma tabela = negação implícita (comportamento padrão do RLS do Postgres).

### 4.1 Exemplos de políticas RLS (Supabase / Postgres)

```sql
alter table ordens_servico enable row level security;
alter table os_executores enable row level security;
alter table orcamentos enable row level security;

-- SELECT: Diretoria lê tudo, sem exceção, sem write
create policy "diretoria_select_os" on ordens_servico
  for select
  using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.perfil = 'diretoria'
    )
  );

-- INSERT: Executor só registra apontamento de horas para si mesmo
create policy "executor_insert_apontamento" on os_executores
  for insert
  with check (
    usuario_id = auth.uid()
    and exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.perfil = 'executor'
    )
  );

-- UPDATE: Encarregado aprova/reabre OS (mas não qualquer campo — só via RPC de transição de status)
create policy "encarregado_update_os" on ordens_servico
  for update
  using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.perfil = 'encarregado'
    )
  )
  with check (
    exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.perfil = 'encarregado'
    )
  );

-- Exemplo com auth.jwt(): restringir suporte administrativo a operações de estoque
-- quando o claim customizado 'perfil' (setado via Auth Hook) já vier no JWT, evitando
-- a subconsulta em profiles a cada linha:
create policy "suporte_confirma_nf" on notas_fiscais_entrada
  for update
  using ( (auth.jwt() -> 'app_metadata' ->> 'perfil') = 'suporte_administrativo' )
  with check ( (auth.jwt() -> 'app_metadata' ->> 'perfil') = 'suporte_administrativo' );
```

---

## 5. Dashboard Executivo — estratégia de performance

- Índices em todas as colunas usadas em filtro/junção do dashboard: `ordens_servico(status, data_abertura)`, `parcelas(status, vencimento)`, `estoque_movimentos(peca_id, criado_em)`, `pecas(saldo_atual, estoque_minimo)`.
- Views materializadas para agregados pesados (ex: `mv_os_por_status_periodo`, `mv_financeiro_resumo_mensal`, `mv_estoque_ruptura`), atualizadas via `REFRESH MATERIALIZED VIEW CONCURRENTLY` disparado por trigger/cron leve (ex: a cada inserção relevante ou em lote a cada poucos minutos — a decidir conforme volume real).
- Diretoria consulta exclusivamente as views/tabelas via `SELECT` com filtros de data/status/categoria aplicados como cláusulas `WHERE` no frontend (Vue) — sem exportação manual, sempre online.
- Indicadores: OS por status/atraso/tempo médio (a partir de `ordens_servico` + `os_executores`), Financeiro a receber/vencido/margens (a partir de `cobrancas`/`parcelas`/`orcamento_itens` vs `estoque_movimentos.custo_unitario`), Estoque ruptura/abaixo do mínimo (`pecas.saldo_atual < estoque_minimo`).

---

## 6. Plano de Implementação (fases por valor de entrega)

1. **Fundação**: projeto Supabase + Auth + `profiles` + RLS base; cadastro de Clientes/Veículos (soft delete); importação inicial via planilha (frota própria + clientes existentes); módulo de Estoque (peças, NF de entrada, custo médio, movimentos, RPC anti-negativação); shell da aplicação Vue (login, navegação, perfis).
2. **OS/Estoque operacional**: Solicitações de Serviço; Orçamentos com versionamento e tabela configurável de acréscimo; Ordens de Serviço completas (múltiplos executores, apontamento por etapa, checklist configurável, liberação técnica); baixa de estoque vinculada a OS; Venda Avulsa de Peças.
3. **Financeiro**: Cobranças (a partir de OS concluída/venda avulsa, agrupamento N:N), parcelas, recebimentos, Termo de Ciência de Débito, regra de liberação física condicionada.
4. **Garantia + Dashboard Executivo**: fluxo de retorno de garantia (OS vinculada, valor zero ao cliente, apuração interna de custo); índices e views materializadas; telas de indicadores (Serviços, Financeiro, Estoque) com filtros para a Diretoria.

---

## 7. Suposições, Riscos e Pendências

**Pendências que exigem validação humana antes de codificar:**
- Valores reais das faixas de valor e percentuais de `orcamento_faixa_acrescimo` — hoje só placeholder estrutural fictício. **Bloqueante para uso em produção da regra de acréscimo**, não bloqueante para o restante do desenho.
- Itens reais do(s) checklist(s) de liberação técnica — modelados como tabela configurável genérica (`checklist_templates`/`checklist_template_itens`), sem itens de exemplo reais definidos.
- Layout/campos exatos exigidos no "Termo de Ciência de Débito" (documento jurídico) — hoje tratado como upload de arquivo assinado, sem geração automática de texto.

**Suposições assumidas (decorrentes das respostas do usuário) — revisão recomendada:**
- Sistema não emite documento fiscal real (NF-e/NFC-e); cobrança e venda avulsa são controles internos. Se a Tropical Transportes precisar futuramente emitir nota fiscal real a partir daqui, será um módulo adicional fora do escopo "custo zero" atual (exige certificado digital A1 e provedor de emissão).
- Migração de veículos/clientes é única, via planilha CSV, sem sincronização contínua com o PCM existente.
- Autenticação por convite manual (sem cadastro público de usuários).

**Riscos de infraestrutura (free tier) a monitorar:**
- Projetos Supabase gratuitos pausam após período de inatividade e não retomam automaticamente na primeira requisição — mitigar com ping agendado; ainda assim, feriados prolongados podem exigir reativação manual eventual.
- Sem backup gerenciado (PITR) no free tier — mitigar com dump lógico agendado para armazenamento externo gratuito.
- Cota de 1GB no Supabase Storage — fotos e comprovantes devem ser comprimidos no upload; monitorar consumo conforme adoção cresce.

---

## Verificação (quando a implementação começar)

- Migrations aplicadas via `supabase db push`/CLI, testadas localmente com Supabase local (Docker) antes de subir.
- Testar cada política RLS autenticando como cada um dos 5 perfis (via usuários de teste) e confirmando que operações fora da matriz da Seção 4 retornam vazio/erro de permissão.
- Testar concorrência de baixa de estoque simulando duas chamadas simultâneas da RPC de saída para a mesma peça com saldo insuficiente para ambas — confirmar que uma falha com saldo protegido (nunca negativo).
- Rodar o dashboard com massa de dados sintética (~100 mil registros) para validar tempo de resposta &lt; 2s nas views materializadas.
