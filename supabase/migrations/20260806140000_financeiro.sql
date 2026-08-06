-- Fase 3 (Financeiro): cobrancas, parcelas, recebimentos e termo de ciencia
-- de debito. Uma cobranca nasce de uma ou mais OS concluidas (tipo externa)
-- e/ou vendas avulsas do mesmo cliente (N:N via cobranca_origens).

create type status_cobranca as enum ('aberta', 'parcial', 'quitada', 'vencida', 'cancelada');
create type status_parcela as enum ('pendente', 'paga', 'atrasada', 'cancelada');
-- 'vencida'/'atrasada' existem nos enums para fidelidade ao desenho original,
-- mas nenhuma RPC grava esses valores: o projeto não tem pg_cron (free tier,
-- custo zero), então atraso é calculado na leitura (vencimento < hoje) pelo
-- frontend, nunca persistido.

create table cobrancas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  valor_total numeric(12,2) not null,
  status status_cobranca not null default 'aberta',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_cobrancas_cliente on cobrancas (cliente_id);
create index idx_cobrancas_status on cobrancas (status);

create table cobranca_origens (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id) on delete cascade,
  os_id uuid references ordens_servico(id),
  venda_avulsa_id uuid references vendas_avulsas(id),
  check (num_nonnulls(os_id, venda_avulsa_id) = 1)
);

create index idx_cobranca_origens_cobranca on cobranca_origens (cobranca_id);
create index idx_cobranca_origens_os on cobranca_origens (os_id);
create index idx_cobranca_origens_venda on cobranca_origens (venda_avulsa_id);

create table parcelas (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id) on delete cascade,
  numero_parcela int not null,
  valor numeric(12,2) not null check (valor > 0),
  vencimento date not null,
  status status_parcela not null default 'pendente',
  unique (cobranca_id, numero_parcela)
);

create index idx_parcelas_cobranca on parcelas (cobranca_id);
create index idx_parcelas_status_vencimento on parcelas (status, vencimento);

create table recebimentos (
  id uuid primary key default gen_random_uuid(),
  parcela_id uuid not null references parcelas(id),
  valor_recebido numeric(12,2) not null check (valor_recebido > 0),
  forma_pagamento text not null,
  data_recebimento date not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_recebimentos_parcela on recebimentos (parcela_id);

create table termos_ciencia_debito (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references cobrancas(id),
  arquivo_path text not null,
  assinado_em timestamptz not null default now()
);

create index idx_termos_cobranca on termos_ciencia_debito (cobranca_id);

-- ============================================================
-- RLS
-- ============================================================
alter table cobrancas enable row level security;
alter table cobranca_origens enable row level security;
alter table parcelas enable row level security;
alter table recebimentos enable row level security;
alter table termos_ciencia_debito enable row level security;

-- Diferente das demais tabelas (select_autenticado = auth.uid() is not null),
-- Financeiro é o único módulo em que o Executor não tem nenhum acesso (matriz
-- RBAC, seção 4 do plano de arquitetura) — então o SELECT já checa perfil.
create policy "cobrancas_select_nao_executor" on cobrancas
  for select
  using (current_perfil() <> 'executor');

create policy "cobranca_origens_select_nao_executor" on cobranca_origens
  for select
  using (current_perfil() <> 'executor');

create policy "parcelas_select_nao_executor" on parcelas
  for select
  using (current_perfil() <> 'executor');

create policy "recebimentos_select_nao_executor" on recebimentos
  for select
  using (current_perfil() <> 'executor');

create policy "termos_ciencia_select_nao_executor" on termos_ciencia_debito
  for select
  using (current_perfil() <> 'executor');

-- Escrita exclusivamente via RPC (SECURITY DEFINER) abaixo.
revoke insert, update, delete on cobrancas from authenticated;
revoke insert, update, delete on cobranca_origens from authenticated;
revoke insert, update, delete on parcelas from authenticated;
revoke insert, update, delete on recebimentos from authenticated;
revoke insert, update, delete on termos_ciencia_debito from authenticated;

-- ============================================================
-- RPCs
-- ============================================================

-- Cria a cobranca a partir de uma ou mais OS concluidas (tipo externa) e/ou
-- vendas avulsas do mesmo cliente, ainda nao cobradas em nenhuma cobranca
-- ativa. valor_total = soma(orcamento.valor_total + acrescimos) por OS +
-- soma(quantidade * valor_unitario) por venda avulsa.
create or replace function rpc_criar_cobranca(p_cliente_id uuid, p_os_ids uuid[], p_venda_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os_id uuid;
  v_venda_id uuid;
  v_os record;
  v_venda record;
  v_valor_total numeric(12,2) := 0;
  v_valor_os numeric(12,2);
  v_valor_venda numeric(12,2);
  v_cobranca_id uuid;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para gerar cobrança';
  end if;

  if coalesce(array_length(p_os_ids, 1), 0) = 0 and coalesce(array_length(p_venda_ids, 1), 0) = 0 then
    raise exception 'Selecione ao menos uma OS ou venda avulsa para gerar a cobrança';
  end if;

  foreach v_os_id in array coalesce(p_os_ids, array[]::uuid[])
  loop
    select os.id, os.cliente_id, os.tipo, os.status, os.orcamento_id into v_os
      from ordens_servico os where os.id = v_os_id for update;
    if v_os.id is null then
      raise exception 'OS não encontrada';
    end if;
    if v_os.cliente_id <> p_cliente_id then
      raise exception 'OS não pertence ao cliente informado';
    end if;
    if v_os.tipo <> 'externa' or v_os.status <> 'concluida' then
      raise exception 'Somente OS externa e concluída pode gerar cobrança';
    end if;
    if exists (
      select 1 from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.os_id = v_os_id and c.status <> 'cancelada'
    ) then
      raise exception 'Esta OS já está vinculada a uma cobrança ativa';
    end if;

    select o.valor_total + coalesce((select sum(a.valor_acrescimo) from orcamento_acrescimos a where a.orcamento_id = o.id), 0)
      into v_valor_os
      from orcamentos o where o.id = v_os.orcamento_id;
    v_valor_total := v_valor_total + coalesce(v_valor_os, 0);
  end loop;

  foreach v_venda_id in array coalesce(p_venda_ids, array[]::uuid[])
  loop
    select v.id, v.cliente_id into v_venda from vendas_avulsas v where v.id = v_venda_id for update;
    if v_venda.id is null then
      raise exception 'Venda avulsa não encontrada';
    end if;
    if v_venda.cliente_id <> p_cliente_id then
      raise exception 'Venda avulsa não pertence ao cliente informado';
    end if;
    if exists (
      select 1 from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.venda_avulsa_id = v_venda_id and c.status <> 'cancelada'
    ) then
      raise exception 'Esta venda avulsa já está vinculada a uma cobrança ativa';
    end if;

    select coalesce(sum(quantidade * valor_unitario), 0) into v_valor_venda
      from venda_avulsa_itens where venda_id = v_venda_id;
    v_valor_total := v_valor_total + v_valor_venda;
  end loop;

  insert into cobrancas (cliente_id, valor_total, criado_por)
  values (p_cliente_id, v_valor_total, auth.uid())
  returning id into v_cobranca_id;

  insert into cobranca_origens (cobranca_id, os_id)
    select v_cobranca_id, unnest(p_os_ids) where p_os_ids is not null;
  insert into cobranca_origens (cobranca_id, venda_avulsa_id)
    select v_cobranca_id, unnest(p_venda_ids) where p_venda_ids is not null;

  return v_cobranca_id;
end;
$$;

-- Formaliza o parcelamento (1 parcela "à vista" ou N parcelas). Só permitido
-- uma vez, enquanto a cobranca ainda nao tem nenhuma parcela — sem
-- replanejamento em v1 (mesma filosofia de imutabilidade dos orçamentos
-- enviados). Essa formalização por si só já satisfaz a condição financeira
-- de liberação da OS externa, mesmo antes do 1º pagamento.
create or replace function rpc_parcelar_cobranca(p_cobranca_id uuid, p_parcelas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cobranca record;
  v_parcela jsonb;
  v_soma numeric(12,2) := 0;
  v_qtd_existentes int;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para parcelar cobrança';
  end if;

  select * into v_cobranca from cobrancas where id = p_cobranca_id for update;
  if v_cobranca.id is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_cobranca.status <> 'aberta' then
    raise exception 'Somente cobranças em aberto podem ser parceladas';
  end if;

  select count(*) into v_qtd_existentes from parcelas where cobranca_id = p_cobranca_id;
  if v_qtd_existentes > 0 then
    raise exception 'Cobrança já possui parcelamento formalizado';
  end if;

  if p_parcelas is null or jsonb_array_length(p_parcelas) = 0 then
    raise exception 'Informe ao menos uma parcela';
  end if;

  for v_parcela in select * from jsonb_array_elements(p_parcelas)
  loop
    if (v_parcela ->> 'valor')::numeric <= 0 then
      raise exception 'Valor de parcela inválido';
    end if;
    v_soma := v_soma + (v_parcela ->> 'valor')::numeric;
  end loop;

  if abs(v_soma - v_cobranca.valor_total) > 0.01 then
    raise exception 'Soma das parcelas (R$ %) não confere com o valor da cobrança (R$ %)', v_soma, v_cobranca.valor_total;
  end if;

  insert into parcelas (cobranca_id, numero_parcela, valor, vencimento)
  select p_cobranca_id, (v.item ->> 'numero_parcela')::int, (v.item ->> 'valor')::numeric, (v.item ->> 'vencimento')::date
  from jsonb_array_elements(p_parcelas) as v(item);
end;
$$;

-- Registra recebimento (parcial ou total) de uma parcela. Nunca ultrapassa o
-- valor da parcela; ao atingi-lo, marca a parcela como paga e recalcula o
-- status da cobrança (aberta -> parcial -> quitada).
create or replace function rpc_registrar_recebimento(
  p_parcela_id uuid,
  p_valor_recebido numeric,
  p_forma_pagamento text,
  p_data_recebimento date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parcela record;
  v_cobranca record;
  v_ja_recebido numeric(12,2);
  v_total_recebido numeric(12,2);
  v_novo_status status_cobranca;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar recebimento';
  end if;

  if p_valor_recebido <= 0 then
    raise exception 'Valor recebido deve ser positivo';
  end if;

  select * into v_parcela from parcelas where id = p_parcela_id for update;
  if v_parcela.id is null then
    raise exception 'Parcela não encontrada';
  end if;
  if v_parcela.status <> 'pendente' then
    raise exception 'Somente parcelas pendentes podem receber pagamento';
  end if;

  select * into v_cobranca from cobrancas where id = v_parcela.cobranca_id for update;
  if v_cobranca.status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe pagamento';
  end if;

  select coalesce(sum(valor_recebido), 0) into v_ja_recebido from recebimentos where parcela_id = p_parcela_id;
  if v_ja_recebido + p_valor_recebido > v_parcela.valor + 0.01 then
    raise exception 'Valor recebido (R$ %) excede o saldo da parcela (R$ %)', p_valor_recebido, v_parcela.valor - v_ja_recebido;
  end if;

  insert into recebimentos (parcela_id, valor_recebido, forma_pagamento, data_recebimento, criado_por)
  values (p_parcela_id, p_valor_recebido, p_forma_pagamento, p_data_recebimento, auth.uid());

  if v_ja_recebido + p_valor_recebido >= v_parcela.valor - 0.01 then
    update parcelas set status = 'paga' where id = p_parcela_id;
  end if;

  select coalesce(sum(r.valor_recebido), 0) into v_total_recebido
    from recebimentos r join parcelas p on p.id = r.parcela_id
    where p.cobranca_id = v_cobranca.id;

  if v_total_recebido >= v_cobranca.valor_total - 0.01 then
    v_novo_status := 'quitada';
  elsif v_total_recebido > 0 then
    v_novo_status := 'parcial';
  else
    v_novo_status := 'aberta';
  end if;

  update cobrancas set status = v_novo_status where id = v_cobranca.id;
end;
$$;

-- Registra o Termo de Ciência de Débito (arquivo assinado, upload feito no
-- Storage pelo frontend — mesmo bucket 'comprovantes' usado pela autorização
-- de orçamento). A existência de um termo, por si só, satisfaz a condição de
-- liberação financeira da OS externa.
create or replace function rpc_registrar_termo_ciencia(p_cobranca_id uuid, p_arquivo_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_cobranca;
begin
  if current_perfil() not in ('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar termo de ciência';
  end if;

  if p_arquivo_path is null or p_arquivo_path = '' then
    raise exception 'Arquivo do termo é obrigatório';
  end if;

  select status into v_status from cobrancas where id = p_cobranca_id for update;
  if v_status is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe termo de ciência';
  end if;

  insert into termos_ciencia_debito (cobranca_id, arquivo_path) values (p_cobranca_id, p_arquivo_path);
end;
$$;

-- Cancela uma cobranca ainda em aberto e sem nenhum recebimento — libera a(s)
-- OS/venda(s) de origem para entrar em uma nova cobrança (a checagem de
-- "já cobrada" em rpc_criar_cobranca ignora cobranças canceladas).
create or replace function rpc_cancelar_cobranca(p_cobranca_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cobranca record;
  v_tem_recebimento boolean;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar cobrança';
  end if;

  select * into v_cobranca from cobrancas where id = p_cobranca_id for update;
  if v_cobranca.id is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_cobranca.status <> 'aberta' then
    raise exception 'Somente cobranças em aberto podem ser canceladas';
  end if;

  select exists (
    select 1 from recebimentos r join parcelas p on p.id = r.parcela_id where p.cobranca_id = p_cobranca_id
  ) into v_tem_recebimento;
  if v_tem_recebimento then
    raise exception 'Cobrança com recebimento registrado não pode ser cancelada';
  end if;

  update parcelas set status = 'cancelada' where cobranca_id = p_cobranca_id and status = 'pendente';
  update cobrancas set status = 'cancelada' where id = p_cobranca_id;
end;
$$;
