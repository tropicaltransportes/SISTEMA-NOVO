-- ETAPA 6 (P1-C) — Decisão 2 (custo/hora interno), Decisão 7 (teto de
-- desconto) e suporte a Decisão 1/item 10 (centro de custo). Todas as três
-- configurações seguem o MESMO padrão: tabela append-only (nunca UPDATE,
-- nunca apaga valor histórico — "histórico, alterado por, vigência"), o
-- valor vigente é sempre "a linha mais recente com vigente_desde <= now()".
-- Mudar o valor no futuro NUNCA recalcula OS já encerrada (snapshot — ver
-- 20260814110500_p1c_cliente_interno_custo.sql e BUSINESS_RULES.md Decisão 2).

-- ============================================================
-- custo_hora_config — Decisão 2. Só administrador_tecnico configura
-- (instrução seção 12, RBAC: "Administrador técnico: configurações, custo/
-- hora, teto de desconto" — mais específica que a decisão 2 genérica).
-- ============================================================
create table custo_hora_config (
  id uuid primary key default gen_random_uuid(),
  valor_hora numeric(12,2) not null check (valor_hora > 0),
  vigente_desde timestamptz not null default now(),
  alterado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_custo_hora_config_vigencia on custo_hora_config (vigente_desde desc);

alter table custo_hora_config enable row level security;

-- Executor não vê custo/hora administrativo (instrução seção 12, explícito).
create policy "custo_hora_config_select_nao_executor" on custo_hora_config
  for select
  using (current_perfil() <> 'executor' and current_user_ativo());

revoke insert, update, delete on custo_hora_config from authenticated, anon;

create or replace function custo_hora_vigente(p_data timestamptz default now())
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select valor_hora from custo_hora_config
    where vigente_desde <= p_data
    order by vigente_desde desc
    limit 1;
$$;

revoke execute on function custo_hora_vigente(timestamptz) from public, anon, authenticated;

create or replace function rpc_definir_custo_hora(p_valor_hora numeric)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior numeric;
  v_novo_id uuid;
begin
  if not tem_perfil('administrador_tecnico') then
    raise exception 'Perfil sem permissão para configurar custo/hora interno';
  end if;
  if p_valor_hora is null or p_valor_hora <= 0 then
    raise exception 'Valor da hora interna deve ser positivo';
  end if;

  select custo_hora_vigente() into v_anterior;

  insert into custo_hora_config (valor_hora, alterado_por)
  values (p_valor_hora, auth.uid())
  returning id into v_novo_id;

  perform registrar_auditoria('custo_hora_config', v_novo_id, 'definir_custo_hora',
    jsonb_build_object('valor_hora', v_anterior), jsonb_build_object('valor_hora', p_valor_hora), null);

  return v_novo_id;
end;
$$;

-- ============================================================
-- desconto_config — Decisão 7 (teto de desconto). Mesmo padrão: só
-- administrador_tecnico configura o teto (instrução seção 12).
-- ============================================================
create table desconto_config (
  id uuid primary key default gen_random_uuid(),
  habilitado boolean not null default true,
  percentual_maximo numeric(5,2) not null check (percentual_maximo >= 0 and percentual_maximo <= 100),
  alterado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_desconto_config_criado_em on desconto_config (criado_em desc);

alter table desconto_config enable row level security;

-- Encarregado precisa enxergar o teto vigente para saber seu limite ao
-- conceder desconto — leitura ampla (não-executor), igual custo/hora.
create policy "desconto_config_select_nao_executor" on desconto_config
  for select
  using (current_perfil() <> 'executor' and current_user_ativo());

revoke insert, update, delete on desconto_config from authenticated, anon;

create or replace function desconto_config_vigente()
returns desconto_config
language sql
stable
security definer
set search_path = public
as $$
  select * from desconto_config order by criado_em desc limit 1;
$$;

revoke execute on function desconto_config_vigente() from public, anon, authenticated;

create or replace function rpc_definir_teto_desconto(p_habilitado boolean, p_percentual_maximo numeric)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior desconto_config;
  v_novo_id uuid;
begin
  if not tem_perfil('administrador_tecnico') then
    raise exception 'Perfil sem permissão para configurar teto de desconto';
  end if;
  if p_percentual_maximo is null or p_percentual_maximo < 0 or p_percentual_maximo > 100 then
    raise exception 'Percentual máximo de desconto inválido (0 a 100)';
  end if;

  select * into v_anterior from desconto_config_vigente();

  insert into desconto_config (habilitado, percentual_maximo, alterado_por)
  values (coalesce(p_habilitado, true), p_percentual_maximo, auth.uid())
  returning id into v_novo_id;

  perform registrar_auditoria('desconto_config', v_novo_id, 'definir_teto_desconto',
    to_jsonb(v_anterior), jsonb_build_object('habilitado', p_habilitado, 'percentual_maximo', p_percentual_maximo), null);

  return v_novo_id;
end;
$$;

-- Seed inicial: sem isso, nenhum desconto pode ser concedido (nenhuma linha
-- vigente = tratado como desabilitado pela RPC de desconto). 10% como teto
-- operacional inicial, alterável pelo administrador_tecnico a qualquer
-- momento — não é um valor de negócio definitivo, só bootstrap seguro.
insert into desconto_config (habilitado, percentual_maximo, alterado_por)
select true, 10.00, id from profiles where perfil = 'administrador_tecnico' order by criado_em limit 1;

-- ============================================================
-- centro_custo — Decisão 1/item 10: estrutura simples e configurável, sem
-- hardcode de departamentos. Cadastro livre (mesma autoridade de cadastros
-- gerais — encarregado/suporte_administrativo/administrador_tecnico).
-- ============================================================
create table centro_custo (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ativo boolean not null default true,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

alter table centro_custo enable row level security;

create policy "centro_custo_select_autenticado" on centro_custo
  for select
  using (current_user_ativo());

revoke insert, update, delete on centro_custo from authenticated, anon;

create or replace function rpc_criar_centro_custo(p_nome text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cadastrar centro de custo';
  end if;
  if p_nome is null or length(trim(p_nome)) < 2 then
    raise exception 'Nome do centro de custo é obrigatório';
  end if;

  insert into centro_custo (nome, criado_por) values (trim(p_nome), auth.uid())
  returning id into v_novo_id;

  return v_novo_id;
end;
$$;

-- ============================================================
-- anexos_config — Decisão 6 / item 2: tamanho máximo e MIME permitidos para
-- fotos de OS, configurável (não hardcode "espalhado" no código — a RPC de
-- upload sempre lê a config vigente). Mesmo padrão de histórico.
-- ============================================================
create table anexos_config (
  id uuid primary key default gen_random_uuid(),
  tamanho_maximo_bytes bigint not null check (tamanho_maximo_bytes > 0),
  mime_permitidos text[] not null,
  alterado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

alter table anexos_config enable row level security;

create policy "anexos_config_select_autenticado" on anexos_config
  for select
  using (current_user_ativo());

revoke insert, update, delete on anexos_config from authenticated, anon;

create or replace function anexos_config_vigente()
returns anexos_config
language sql
stable
security definer
set search_path = public
as $$
  select * from anexos_config order by criado_em desc limit 1;
$$;

revoke execute on function anexos_config_vigente() from public, anon, authenticated;

create or replace function rpc_definir_anexos_config(p_tamanho_maximo_bytes bigint, p_mime_permitidos text[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_novo_id uuid;
begin
  if not tem_perfil('administrador_tecnico') then
    raise exception 'Perfil sem permissão para configurar limites de anexos';
  end if;
  if p_tamanho_maximo_bytes is null or p_tamanho_maximo_bytes <= 0 then
    raise exception 'Tamanho máximo inválido';
  end if;
  if p_mime_permitidos is null or array_length(p_mime_permitidos, 1) is null then
    raise exception 'Informe ao menos um tipo MIME permitido';
  end if;

  insert into anexos_config (tamanho_maximo_bytes, mime_permitidos, alterado_por)
  values (p_tamanho_maximo_bytes, p_mime_permitidos, auth.uid())
  returning id into v_novo_id;

  return v_novo_id;
end;
$$;

-- Seed inicial: 5MB, jpeg/png/webp — bootstrap operacional, alterável.
insert into anexos_config (tamanho_maximo_bytes, mime_permitidos, alterado_por)
select 5242880, array['image/jpeg', 'image/png', 'image/webp'], id
from profiles where perfil = 'administrador_tecnico' order by criado_em limit 1;
