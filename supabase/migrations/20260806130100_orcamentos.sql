-- Fase 2: orçamentos imutáveis e versionados, com acréscimo pós-aprovação
-- controlado por faixa configurável + teto absoluto.

create type status_orcamento as enum ('rascunho', 'enviado', 'aprovado', 'rejeitado', 'substituido');

create table orcamentos (
  id uuid primary key default gen_random_uuid(),
  solicitacao_id uuid references solicitacoes_servico(id),
  veiculo_id uuid not null references veiculos(id),
  cliente_id uuid not null references clientes(id),
  orcamento_raiz_id uuid references orcamentos(id), -- aponta para a V1; null na própria V1
  versao int not null default 1,
  status status_orcamento not null default 'rascunho',
  valor_total numeric(12,2) not null default 0,
  autorizado_por_nome text, -- obrigatório para cliente externo antes de aprovar
  autorizado_em timestamptz,
  comprovante_path text, -- Supabase Storage, obrigatório para cliente externo
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_orcamentos_raiz on orcamentos (orcamento_raiz_id);
create index idx_orcamentos_status on orcamentos (status);
create index idx_orcamentos_veiculo on orcamentos (veiculo_id);
create index idx_orcamentos_solicitacao on orcamentos (solicitacao_id);

create table orcamento_itens (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references orcamentos(id) on delete cascade,
  peca_id uuid references pecas(id), -- null se for item de mão de obra
  descricao text not null,
  quantidade numeric(10,3) not null check (quantidade > 0),
  valor_unitario numeric(12,2) not null check (valor_unitario >= 0),
  valor_total numeric(12,2) generated always as (quantidade * valor_unitario) stored
);

create index idx_orcamento_itens_orcamento on orcamento_itens (orcamento_id);

-- Faixas de acréscimo pós-aprovação — CONFIGURÁVEL. Nenhuma linha inserida por
-- esta migration: os valores reais são pendência da diretoria (ver
-- docs/plano-arquitetura.md, seção 7). Enquanto vazia/inativa, qualquer
-- tentativa de acréscimo é bloqueada pela RPC abaixo — comportamento seguro
-- por padrão, nunca aplica percentual "de exemplo" a um orçamento real.
create table orcamento_faixa_acrescimo (
  id uuid primary key default gen_random_uuid(),
  valor_min numeric(12,2) not null,
  valor_max numeric(12,2), -- null = sem limite superior na faixa
  percentual_max numeric(5,2) not null,
  ativo boolean not null default true
);

create table orcamento_acrescimos (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references orcamentos(id),
  valor_acrescimo numeric(12,2) not null check (valor_acrescimo > 0),
  justificativa text not null,
  aprovado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_orcamento_acrescimos_orcamento on orcamento_acrescimos (orcamento_id);

-- Mantém orcamentos.valor_total = soma dos itens automaticamente. Como os itens
-- só podem ser gravados enquanto o orçamento está em rascunho (RLS abaixo),
-- valor_total nunca muda depois do envio.
create or replace function recalc_valor_total_orcamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update orcamentos
    set valor_total = (
      select coalesce(sum(valor_total), 0) from orcamento_itens
      where orcamento_id = coalesce(new.orcamento_id, old.orcamento_id)
    )
    where id = coalesce(new.orcamento_id, old.orcamento_id);
  return null;
end;
$$;

create trigger trg_recalc_valor_total_orcamento
  after insert or update or delete on orcamento_itens
  for each row execute function recalc_valor_total_orcamento();

-- ============================================================
-- RLS
-- ============================================================
alter table orcamentos enable row level security;
alter table orcamento_itens enable row level security;
alter table orcamento_faixa_acrescimo enable row level security;
alter table orcamento_acrescimos enable row level security;

create policy "orcamentos_select_autenticado" on orcamentos
  for select
  using (auth.uid() is not null);

-- INSERT direto só cria V1 (raiz null, versão 1); novas versões nascem
-- exclusivamente via rpc_criar_versao_orcamento (SECURITY DEFINER).
create policy "orcamentos_insert_v1" on orcamentos
  for insert
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and criado_por = auth.uid()
    and status = 'rascunho'
    and versao = 1
    and orcamento_raiz_id is null
  );

-- Único UPDATE direto permitido ao cliente: corrigir veiculo/cliente enquanto
-- rascunho. Toda transição de status e os campos de autorização passam pelas
-- RPCs abaixo (SECURITY DEFINER, ignoram estes grants).
create policy "orcamentos_update_rascunho" on orcamentos
  for update
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and status = 'rascunho'
  )
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and status = 'rascunho'
  );

revoke update on orcamentos from authenticated;
grant update (veiculo_id, cliente_id, solicitacao_id) on orcamentos to authenticated;

-- orcamento_itens: só editáveis enquanto o orçamento pai está em rascunho.
create policy "orcamento_itens_select_autenticado" on orcamento_itens
  for select
  using (auth.uid() is not null);

create policy "orcamento_itens_insert_rascunho" on orcamento_itens
  for insert
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (select 1 from orcamentos o where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho')
  );

create policy "orcamento_itens_update_rascunho" on orcamento_itens
  for update
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (select 1 from orcamentos o where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho')
  )
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (select 1 from orcamentos o where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho')
  );

create policy "orcamento_itens_delete_rascunho" on orcamento_itens
  for delete
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (select 1 from orcamentos o where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho')
  );

-- orcamento_faixa_acrescimo: configuração de sistema, gerida pelo administrador
-- técnico (diretoria define os valores reais fora do sistema/por pedido, mas
-- só o admin técnico tem escrita, igual às demais tabelas de configuração).
create policy "faixa_acrescimo_select_autenticado" on orcamento_faixa_acrescimo
  for select
  using (auth.uid() is not null);

create policy "faixa_acrescimo_insert_admin" on orcamento_faixa_acrescimo
  for insert
  with check (current_perfil() = 'administrador_tecnico');

create policy "faixa_acrescimo_update_admin" on orcamento_faixa_acrescimo
  for update
  using (current_perfil() = 'administrador_tecnico')
  with check (current_perfil() = 'administrador_tecnico');

-- orcamento_acrescimos: leitura liberada; escrita exclusivamente via RPC.
create policy "orcamento_acrescimos_select_autenticado" on orcamento_acrescimos
  for select
  using (auth.uid() is not null);

revoke insert, update, delete on orcamento_acrescimos from authenticated;

-- ============================================================
-- RPCs: transições de status e acréscimo (única via de escrita)
-- ============================================================

create or replace function rpc_enviar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
  v_qtd_itens int;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para enviar orçamento';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'rascunho' then
    raise exception 'Somente orçamentos em rascunho podem ser enviados';
  end if;

  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  if v_qtd_itens = 0 then
    raise exception 'Orçamento precisa de ao menos um item para ser enviado';
  end if;

  update orcamentos set status = 'enviado' where id = p_orcamento_id;
end;
$$;

-- Registra a autorização do cliente (nome de quem autorizou + comprovante
-- anexado no Storage). Etapa separada da aprovação: aqui é o suporte
-- administrativo/encarregado coletando a autorização; rpc_aprovar_orcamento
-- é quem efetivamente muda o status, e exige estes campos para cliente externo.
create or replace function rpc_registrar_autorizacao_orcamento(
  p_orcamento_id uuid,
  p_autorizado_por_nome text,
  p_comprovante_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
begin
  if current_perfil() not in ('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar autorização';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'enviado' then
    raise exception 'Autorização só pode ser registrada em orçamento enviado';
  end if;

  update orcamentos
    set autorizado_por_nome = p_autorizado_por_nome,
        comprovante_path = p_comprovante_path,
        autorizado_em = now()
    where id = p_orcamento_id;
end;
$$;

create or replace function rpc_aprovar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_tipo_cliente tipo_cliente;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para aprovar orçamento';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.status <> 'enviado' then
    raise exception 'Somente orçamentos enviados podem ser aprovados';
  end if;

  select tipo into v_tipo_cliente from clientes where id = v_orc.cliente_id;
  if v_tipo_cliente = 'externo' and (v_orc.autorizado_por_nome is null or v_orc.comprovante_path is null) then
    raise exception 'Cliente externo exige autorização (nome + comprovante) antes de aprovar';
  end if;

  update orcamentos set status = 'aprovado' where id = p_orcamento_id;

  if v_orc.solicitacao_id is not null then
    perform marcar_solicitacao_convertida(v_orc.solicitacao_id, 'convertida_orcamento');
  end if;
end;
$$;

create or replace function rpc_rejeitar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para rejeitar orçamento';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'enviado' then
    raise exception 'Somente orçamentos enviados podem ser rejeitados';
  end if;

  update orcamentos set status = 'rejeitado' where id = p_orcamento_id;
end;
$$;

-- Cria uma nova versão (V2+) a partir de um orçamento enviado/aprovado/rejeitado,
-- copiando os itens atuais como ponto de partida e marcando o original como
-- 'substituido'. A nova versão nasce em rascunho, livre para edição.
create or replace function rpc_criar_versao_orcamento(p_orcamento_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig record;
  v_raiz_id uuid;
  v_nova_versao int;
  v_novo_id uuid;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para versionar orçamento';
  end if;

  select * into v_orig from orcamentos where id = p_orcamento_id for update;
  if v_orig.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orig.status not in ('enviado', 'aprovado', 'rejeitado') then
    raise exception 'Só é possível versionar orçamento enviado, aprovado ou rejeitado';
  end if;

  v_raiz_id := coalesce(v_orig.orcamento_raiz_id, v_orig.id);
  select coalesce(max(versao), 0) + 1 into v_nova_versao
    from orcamentos where id = v_raiz_id or orcamento_raiz_id = v_raiz_id;

  insert into orcamentos (solicitacao_id, veiculo_id, cliente_id, orcamento_raiz_id, versao, status, criado_por)
  values (v_orig.solicitacao_id, v_orig.veiculo_id, v_orig.cliente_id, v_raiz_id, v_nova_versao, 'rascunho', auth.uid())
  returning id into v_novo_id;

  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
  select v_novo_id, peca_id, descricao, quantidade, valor_unitario
    from orcamento_itens where orcamento_id = p_orcamento_id;

  update orcamentos set status = 'substituido' where id = p_orcamento_id;

  return v_novo_id;
end;
$$;

-- Registra acréscimo pós-aprovação, validado contra a faixa configurável
-- (percentual sobre o valor_total original) e contra o teto absoluto de
-- R$ 5.000,00 (regra fixa, independente de faixa). Bloqueia por padrão se
-- nenhuma faixa ativa cobrir o valor do orçamento.
create or replace function rpc_registrar_acrescimo(
  p_orcamento_id uuid,
  p_valor_acrescimo numeric,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_percentual numeric(5,2);
  v_limite_percentual numeric(12,2);
  v_acumulado numeric(12,2);
  v_teto_absoluto constant numeric(12,2) := 5000.00;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar acréscimo';
  end if;

  if p_valor_acrescimo <= 0 then
    raise exception 'Valor de acréscimo deve ser positivo';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.status <> 'aprovado' then
    raise exception 'Acréscimo só pode ser registrado em orçamento aprovado';
  end if;

  select percentual_max into v_percentual
    from orcamento_faixa_acrescimo
    where ativo and v_orc.valor_total >= valor_min and (valor_max is null or v_orc.valor_total <= valor_max)
    order by valor_min desc
    limit 1;

  if v_percentual is null then
    raise exception 'Nenhuma faixa de acréscimo configurada para orçamentos de valor R$ %', v_orc.valor_total;
  end if;

  v_limite_percentual := round(v_orc.valor_total * v_percentual / 100, 2);

  select coalesce(sum(valor_acrescimo), 0) into v_acumulado
    from orcamento_acrescimos where orcamento_id = p_orcamento_id;
  v_acumulado := v_acumulado + p_valor_acrescimo;

  if v_acumulado > v_limite_percentual then
    raise exception 'Acréscimo acumulado (R$ %) excede o limite da faixa (% %% de R$ % = R$ %)',
      v_acumulado, v_percentual, v_orc.valor_total, v_limite_percentual;
  end if;

  if v_acumulado > v_teto_absoluto then
    raise exception 'Acréscimo acumulado (R$ %) excede o teto absoluto de R$ %', v_acumulado, v_teto_absoluto;
  end if;

  insert into orcamento_acrescimos (orcamento_id, valor_acrescimo, justificativa, aprovado_por)
  values (p_orcamento_id, p_valor_acrescimo, p_justificativa, auth.uid());
end;
$$;
