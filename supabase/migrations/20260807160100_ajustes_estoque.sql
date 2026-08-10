-- Fase 5: ajustes manuais de estoque — registra a justificativa de cada
-- correção que não passa por nota fiscal (material recebido sem NF, ou
-- correção de saldo após contagem física de inventário divergente).
--
-- Segue exatamente a mesma disciplina do restante do módulo de estoque:
-- pecas.saldo_atual/custo_medio e estoque_movimentos só mudam via RPC
-- SECURITY DEFINER, nunca por escrita direta do cliente.

create table ajustes_estoque (
  id uuid primary key default gen_random_uuid(),
  peca_id uuid not null references pecas(id),
  tipo tipo_movimento_estoque not null,
  quantidade numeric(12,3) not null check (quantidade > 0),
  custo_unitario numeric(12,4),
  motivo text not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now(),
  constraint ajuste_tipo_valido check (tipo in ('entrada', 'saida')),
  constraint ajuste_motivo_preenchido check (length(trim(motivo)) >= 5),
  constraint ajuste_custo_obrigatorio_na_entrada check (tipo <> 'entrada' or custo_unitario is not null)
);

create index idx_ajustes_estoque_peca on ajustes_estoque (peca_id, criado_em);

alter table ajustes_estoque enable row level security;

-- Leitura liberada (mesmo padrão de NF/movimentos); escrita exclusivamente
-- via RPC — nenhuma policy nem grant de insert/update/delete pro cliente.
create policy "ajustes_estoque_select_autenticado" on ajustes_estoque
  for select
  using (auth.uid() is not null);

revoke insert, update, delete on ajustes_estoque from authenticated;

-- ============================================================
-- RPCs
-- ============================================================

-- Entrada de estoque genérica anti-negativação (não se aplica aqui, entrada
-- só soma), simétrica a rpc_registrar_saida_estoque: trava a linha da peça,
-- recalcula o custo médio ponderado móvel e grava o movimento. Assim como a
-- de saída, não faz checagem de perfil própria — só é chamada internamente
-- por outra RPC já gated (ex.: rpc_registrar_ajuste_estoque abaixo), nunca
-- exposta direto pro cliente via PostgREST.
create or replace function rpc_registrar_entrada_estoque(
  p_peca_id uuid,
  p_quantidade numeric,
  p_custo_unitario numeric,
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
  v_novo_custo numeric(12,4);
begin
  if p_quantidade <= 0 then
    raise exception 'Quantidade de entrada deve ser positiva';
  end if;
  if p_custo_unitario is null or p_custo_unitario < 0 then
    raise exception 'Custo unitário inválido';
  end if;

  select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
    from pecas where id = p_peca_id for update;

  if v_saldo_atual is null then
    raise exception 'Peça % não encontrada', p_peca_id;
  end if;

  v_novo_saldo := v_saldo_atual + p_quantidade;
  v_novo_custo := ((v_saldo_atual * v_custo_medio) + (p_quantidade * p_custo_unitario)) / v_novo_saldo;

  update pecas
    set saldo_atual = v_novo_saldo, custo_medio = v_novo_custo
    where id = p_peca_id;

  insert into estoque_movimentos
    (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
  values
    (p_peca_id, 'entrada', p_origem_tipo, p_origem_id, p_quantidade, p_custo_unitario, v_novo_saldo, auth.uid());
end;
$$;

revoke execute on function rpc_registrar_entrada_estoque(uuid, numeric, numeric, origem_movimento, uuid) from public;

-- Ponto de entrada público do ajuste manual: valida perfil e motivo, grava o
-- registro em ajustes_estoque (o "porquê" auditável) e delega o efeito real
-- no saldo pra rpc_registrar_entrada_estoque ou rpc_registrar_saida_estoque
-- (reaproveitando a mesma trava/validação/ledger que todo o resto do
-- sistema já usa — nenhuma lógica de saldo duplicada aqui).
create or replace function rpc_registrar_ajuste_estoque(
  p_peca_id uuid,
  p_tipo text,
  p_quantidade numeric,
  p_custo_unitario numeric,
  p_motivo text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ajuste_id uuid;
begin
  if current_perfil() not in ('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para ajustar estoque';
  end if;

  if p_tipo not in ('entrada', 'saida') then
    raise exception 'Tipo de ajuste inválido: use entrada ou saida';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Informe o motivo do ajuste (mínimo de 5 caracteres)';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade deve ser positiva';
  end if;

  if p_tipo = 'entrada' and (p_custo_unitario is null or p_custo_unitario < 0) then
    raise exception 'Informe o custo unitário do material recebido';
  end if;

  insert into ajustes_estoque (peca_id, tipo, quantidade, custo_unitario, motivo, criado_por)
  values (
    p_peca_id,
    p_tipo::tipo_movimento_estoque,
    p_quantidade,
    case when p_tipo = 'entrada' then p_custo_unitario else null end,
    p_motivo,
    auth.uid()
  )
  returning id into v_ajuste_id;

  if p_tipo = 'entrada' then
    perform rpc_registrar_entrada_estoque(p_peca_id, p_quantidade, p_custo_unitario, 'ajuste_estoque', v_ajuste_id);
  else
    perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'ajuste_estoque', v_ajuste_id);
  end if;

  return v_ajuste_id;
end;
$$;
