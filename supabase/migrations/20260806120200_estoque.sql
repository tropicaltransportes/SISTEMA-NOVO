-- Fase 1: estoque (peças, entrada por NF, custo médio ponderado móvel,
-- ledger de movimentos e RPCs de baixa/entrada anti-negativação)

create type tipo_movimento_estoque as enum ('entrada', 'saida', 'estorno_entrada', 'estorno_saida');
create type origem_movimento as enum ('nf_entrada', 'os', 'venda_avulsa', 'estorno');
create type status_nf as enum ('rascunho', 'confirmada', 'estornada');

create table pecas (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  descricao text not null,
  unidade text not null default 'UN',
  saldo_atual numeric(12,3) not null default 0,
  custo_medio numeric(12,4) not null default 0,
  estoque_minimo numeric(12,3) not null default 0,
  deleted_at timestamptz,
  criado_em timestamptz not null default now(),
  constraint saldo_nao_negativo check (saldo_atual >= 0)
);

create index idx_pecas_sku on pecas (sku) where deleted_at is null;
create index idx_pecas_ruptura on pecas (saldo_atual, estoque_minimo) where deleted_at is null;

-- Ledger append-only. Correções são sempre um novo registro (tipo estorno_*),
-- nunca UPDATE/DELETE de um movimento já gravado.
create table estoque_movimentos (
  id uuid primary key default gen_random_uuid(),
  peca_id uuid not null references pecas(id),
  tipo tipo_movimento_estoque not null,
  origem_tipo origem_movimento not null,
  origem_id uuid not null,
  quantidade numeric(12,3) not null,
  custo_unitario numeric(12,4) not null,
  saldo_resultante numeric(12,3) not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_estoque_mov_peca_data on estoque_movimentos (peca_id, criado_em);
create index idx_estoque_mov_origem on estoque_movimentos (origem_tipo, origem_id);

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
  nf_id uuid not null references notas_fiscais_entrada(id) on delete cascade,
  peca_id uuid not null references pecas(id),
  quantidade numeric(12,3) not null check (quantidade > 0),
  valor_unitario numeric(12,4) not null check (valor_unitario >= 0)
);

create index idx_nf_itens_nf on nf_entrada_itens (nf_id);

-- ============================================================
-- RLS
-- ============================================================
alter table pecas enable row level security;
alter table estoque_movimentos enable row level security;
alter table notas_fiscais_entrada enable row level security;
alter table nf_entrada_itens enable row level security;

-- pecas: leitura liberada; escrita restrita a suporte administrativo/admin,
-- e mesmo assim só nas colunas de cadastro — saldo_atual/custo_medio nunca
-- são graváveis diretamente pelo cliente, apenas pelas RPCs abaixo (que
-- rodam como dono da função, com privilégio pleno sobre a tabela).
create policy "pecas_select_autenticado" on pecas
  for select
  using (auth.uid() is not null);

create policy "pecas_insert_cadastro" on pecas
  for insert
  with check (current_perfil() in ('suporte_administrativo', 'administrador_tecnico'));

create policy "pecas_update_cadastro" on pecas
  for update
  using (current_perfil() in ('suporte_administrativo', 'administrador_tecnico'))
  with check (current_perfil() in ('suporte_administrativo', 'administrador_tecnico'));

revoke update on pecas from authenticated;
grant update (descricao, unidade, estoque_minimo, deleted_at) on pecas to authenticated;

-- estoque_movimentos: leitura liberada; escrita exclusivamente via RPC
-- (nenhuma policy nem grant de insert/update/delete para o cliente).
create policy "estoque_movimentos_select_autenticado" on estoque_movimentos
  for select
  using (auth.uid() is not null);

revoke insert, update, delete on estoque_movimentos from authenticated;

-- notas_fiscais_entrada: leitura liberada; suporte administrativo cria e
-- edita cabeçalho enquanto rascunho. A coluna status só muda via RPC.
create policy "nf_select_autenticado" on notas_fiscais_entrada
  for select
  using (auth.uid() is not null);

create policy "nf_insert_rascunho" on notas_fiscais_entrada
  for insert
  with check (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and status = 'rascunho'
  );

create policy "nf_update_rascunho" on notas_fiscais_entrada
  for update
  using (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and status = 'rascunho'
  )
  with check (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and status = 'rascunho'
  );

revoke update on notas_fiscais_entrada from authenticated;
grant update (numero, fornecedor, data_emissao) on notas_fiscais_entrada to authenticated;

-- nf_entrada_itens: editável só enquanto a NF pai está em rascunho.
create policy "nf_itens_select_autenticado" on nf_entrada_itens
  for select
  using (auth.uid() is not null);

create policy "nf_itens_insert_rascunho" on nf_entrada_itens
  for insert
  with check (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and exists (
      select 1 from notas_fiscais_entrada nf
      where nf.id = nf_entrada_itens.nf_id and nf.status = 'rascunho'
    )
  );

create policy "nf_itens_update_rascunho" on nf_entrada_itens
  for update
  using (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and exists (
      select 1 from notas_fiscais_entrada nf
      where nf.id = nf_entrada_itens.nf_id and nf.status = 'rascunho'
    )
  )
  with check (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and exists (
      select 1 from notas_fiscais_entrada nf
      where nf.id = nf_entrada_itens.nf_id and nf.status = 'rascunho'
    )
  );

create policy "nf_itens_delete_rascunho" on nf_entrada_itens
  for delete
  using (
    current_perfil() in ('suporte_administrativo', 'administrador_tecnico')
    and exists (
      select 1 from notas_fiscais_entrada nf
      where nf.id = nf_entrada_itens.nf_id and nf.status = 'rascunho'
    )
  );

-- ============================================================
-- RPCs: única via de escrita em saldo/custo médio/movimentos
-- ============================================================

-- Confirma uma NF em rascunho: para cada item, trava a linha da peça
-- (FOR UPDATE), soma a quantidade, recalcula o custo médio ponderado móvel
-- e grava o movimento de entrada. Tudo em uma única transação.
create or replace function rpc_confirmar_nf_entrada(p_nf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_nf;
  v_item record;
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
  v_novo_custo numeric(12,4);
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para confirmar nota fiscal';
  end if;

  select status into v_status from notas_fiscais_entrada where id = p_nf_id for update;
  if v_status is null then
    raise exception 'Nota fiscal não encontrada';
  end if;
  if v_status <> 'rascunho' then
    raise exception 'Somente notas em rascunho podem ser confirmadas';
  end if;

  for v_item in
    select peca_id, quantidade, valor_unitario from nf_entrada_itens where nf_id = p_nf_id
  loop
    select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
      from pecas where id = v_item.peca_id for update;

    if v_saldo_atual is null then
      raise exception 'Peça % não encontrada', v_item.peca_id;
    end if;

    v_novo_saldo := v_saldo_atual + v_item.quantidade;
    v_novo_custo := ((v_saldo_atual * v_custo_medio) + (v_item.quantidade * v_item.valor_unitario)) / v_novo_saldo;

    update pecas
      set saldo_atual = v_novo_saldo, custo_medio = v_novo_custo
      where id = v_item.peca_id;

    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
    values
      (v_item.peca_id, 'entrada', 'nf_entrada', p_nf_id, v_item.quantidade, v_item.valor_unitario, v_novo_saldo, auth.uid());
  end loop;

  update notas_fiscais_entrada set status = 'confirmada' where id = p_nf_id;
end;
$$;

-- Estorna uma NF confirmada: reverte a quantidade de cada item e recalcula
-- o custo médio removendo o valor que esta entrada havia agregado ao pool.
-- Bloqueia se a peça já não tiver saldo suficiente (unidades já consumidas
-- por outra movimentação após a entrada original).
create or replace function rpc_estornar_nf_entrada(p_nf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_nf;
  v_item record;
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
  v_valor_total_atual numeric(18,4);
  v_novo_custo numeric(12,4);
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para estornar nota fiscal';
  end if;

  select status into v_status from notas_fiscais_entrada where id = p_nf_id for update;
  if v_status is null then
    raise exception 'Nota fiscal não encontrada';
  end if;
  if v_status <> 'confirmada' then
    raise exception 'Somente notas confirmadas podem ser estornadas';
  end if;

  for v_item in
    select peca_id, quantidade, valor_unitario from nf_entrada_itens where nf_id = p_nf_id
  loop
    select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
      from pecas where id = v_item.peca_id for update;

    v_novo_saldo := v_saldo_atual - v_item.quantidade;
    if v_novo_saldo < 0 then
      raise exception 'Estorno bloqueado: saldo atual da peça % é insuficiente (já consumido por outra movimentação)', v_item.peca_id;
    end if;

    v_valor_total_atual := (v_saldo_atual * v_custo_medio) - (v_item.quantidade * v_item.valor_unitario);
    if v_novo_saldo > 0 then
      v_novo_custo := v_valor_total_atual / v_novo_saldo;
    else
      v_novo_custo := 0;
    end if;

    update pecas
      set saldo_atual = v_novo_saldo, custo_medio = v_novo_custo
      where id = v_item.peca_id;

    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
    values
      (v_item.peca_id, 'estorno_entrada', 'estorno', p_nf_id, v_item.quantidade, v_item.valor_unitario, v_novo_saldo, auth.uid());
  end loop;

  update notas_fiscais_entrada set status = 'estornada' where id = p_nf_id;
end;
$$;

-- Baixa de estoque genérica anti-negativação, reaproveitada pelos módulos de
-- OS e Venda Avulsa (Fase 2). Trava a linha da peça, valida saldo suficiente
-- dentro da própria transação (nunca confia só na checagem do frontend) e
-- grava o movimento de saída.
create or replace function rpc_registrar_saida_estoque(
  p_peca_id uuid,
  p_quantidade numeric,
  p_origem_tipo origem_movimento,
  p_origem_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
begin
  if p_quantidade <= 0 then
    raise exception 'Quantidade de saída deve ser positiva';
  end if;

  select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
    from pecas where id = p_peca_id for update;

  if v_saldo_atual is null then
    raise exception 'Peça % não encontrada', p_peca_id;
  end if;

  v_novo_saldo := v_saldo_atual - p_quantidade;
  if v_novo_saldo < 0 then
    raise exception 'Estoque insuficiente para a peça % (saldo % , solicitado %)', p_peca_id, v_saldo_atual, p_quantidade;
  end if;

  update pecas set saldo_atual = v_novo_saldo where id = p_peca_id;

  insert into estoque_movimentos
    (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
  values
    (p_peca_id, 'saida', p_origem_tipo, p_origem_id, p_quantidade, v_custo_medio, v_novo_saldo, auth.uid());
end;
$$;
