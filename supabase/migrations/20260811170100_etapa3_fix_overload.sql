-- Corrige um erro introduzido pela migration anterior desta mesma rodada
-- (20260811170000_etapa3_correcoes.sql), descoberto por execução real
-- imediatamente após aplicá-la (ver docs/testing/_etapa3_posfix_p0_output.txt,
-- HTTP 300 / PGRST203 "Could not choose the best candidate function").
--
-- Causa: adicionar o parâmetro p_idempotency_key com DEFAULT NULL a
-- rpc_baixar_peca_os/rpc_registrar_saida_estoque via CREATE OR REPLACE só
-- substitui a função quando a ASSINATURA (tipos de parâmetro) é idêntica.
-- Como a assinatura mudou (parâmetro a mais), o Postgres criou uma SEGUNDA
-- função sobrecarregada em vez de substituir a original — as duas (3 e 4
-- argumentos / 4 e 5 argumentos) passaram a coexistir, e o PostgREST não
-- consegue decidir qual chamar quando o cliente manda só os parâmetros
-- antigos (ambas batem, já que o novo parâmetro tem default).
--
-- Correção: remove explicitamente as assinaturas antigas antes de recriar,
-- para sobrar só uma função por nome.
drop function if exists rpc_baixar_peca_os(uuid, uuid, numeric);
drop function if exists rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid);

create or replace function rpc_registrar_saida_estoque(
  p_peca_id uuid,
  p_quantidade numeric,
  p_origem_tipo origem_movimento,
  p_origem_id uuid,
  p_idempotency_key uuid default null
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

  if p_idempotency_key is not null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = p_origem_tipo and origem_id = p_origem_id
      and peca_id = p_peca_id and tipo = 'saida' and idempotency_key = p_idempotency_key
  ) then
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end if;

  v_novo_saldo := v_saldo_atual - p_quantidade;
  if v_novo_saldo < 0 then
    raise exception 'Estoque insuficiente para a peça % (saldo % , solicitado %)', p_peca_id, v_saldo_atual, p_quantidade;
  end if;

  update pecas set saldo_atual = v_novo_saldo where id = p_peca_id;

  begin
    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por, idempotency_key)
    values
      (p_peca_id, 'saida', p_origem_tipo, p_origem_id, p_quantidade, v_custo_medio, v_novo_saldo, auth.uid(), p_idempotency_key);
  exception when unique_violation then
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end;
end;
$$;

revoke execute on function rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid, uuid) from public, anon, authenticated;

create or replace function rpc_baixar_peca_os(
  p_os_id uuid,
  p_peca_id uuid,
  p_quantidade numeric,
  p_idempotency_key uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key);
end;
$$;
