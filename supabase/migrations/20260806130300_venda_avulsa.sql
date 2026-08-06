-- Fase 2: venda avulsa de peças (balcão, sem OS associada)

create table vendas_avulsas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  status text not null default 'concluida',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create table venda_avulsa_itens (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references vendas_avulsas(id) on delete cascade,
  peca_id uuid not null references pecas(id),
  quantidade numeric(12,3) not null check (quantidade > 0),
  valor_unitario numeric(12,2) not null check (valor_unitario >= 0)
);

create index idx_venda_itens_venda on venda_avulsa_itens (venda_id);
create index idx_vendas_avulsas_cliente on vendas_avulsas (cliente_id);

alter table vendas_avulsas enable row level security;
alter table venda_avulsa_itens enable row level security;

create policy "vendas_avulsas_select_autenticado" on vendas_avulsas
  for select
  using (auth.uid() is not null);

create policy "venda_itens_select_autenticado" on venda_avulsa_itens
  for select
  using (auth.uid() is not null);

-- Escrita exclusivamente via RPC (cria cabeçalho + itens + baixa de estoque
-- em uma única transação, sempre em conjunto — nunca um sem o outro).
revoke insert, update, delete on vendas_avulsas from authenticated;
revoke insert, update, delete on venda_avulsa_itens from authenticated;

create or replace function rpc_criar_venda_avulsa(p_cliente_id uuid, p_itens jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_venda_id uuid;
  v_item jsonb;
  v_peca_id uuid;
  v_quantidade numeric;
  v_valor_unitario numeric;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar venda avulsa';
  end if;

  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    raise exception 'Venda avulsa precisa de ao menos um item';
  end if;

  insert into vendas_avulsas (cliente_id, criado_por)
  values (p_cliente_id, auth.uid())
  returning id into v_venda_id;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    v_peca_id := (v_item ->> 'peca_id')::uuid;
    v_quantidade := (v_item ->> 'quantidade')::numeric;
    v_valor_unitario := (v_item ->> 'valor_unitario')::numeric;

    if v_peca_id is null or v_quantidade is null or v_quantidade <= 0 then
      raise exception 'Item de venda inválido: peça e quantidade (> 0) são obrigatórios';
    end if;

    insert into venda_avulsa_itens (venda_id, peca_id, quantidade, valor_unitario)
    values (v_venda_id, v_peca_id, v_quantidade, coalesce(v_valor_unitario, 0));

    perform rpc_registrar_saida_estoque(v_peca_id, v_quantidade, 'venda_avulsa', v_venda_id);
  end loop;

  return v_venda_id;
end;
$$;
