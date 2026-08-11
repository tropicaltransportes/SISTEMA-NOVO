-- ETAPA 6 (P1-C) — Decisão 1 (cliente interno / OS interna, resolve
-- FIN-010/PEN-001/PEN-002) + Decisão 2 (custo/hora) + item 10/16.
--
-- OS interna NUNCA gera cobrança financeira (já garantido estruturalmente:
-- rpc_criar_cobranca só aceita os.tipo = 'externa' — nenhuma mudança
-- necessária ali, é uma invariante que já existia). O que faltava era
-- CALCULAR e SNAPSHOTAR o custo interno (peças efetivamente consumidas +
-- mão de obra apontada × custo/hora vigente no momento da conclusão).

alter table ordens_servico add column if not exists centro_custo_id uuid references centro_custo(id);
alter table ordens_servico add column if not exists custo_pecas numeric(12,2);
alter table ordens_servico add column if not exists custo_mao_obra numeric(12,2);
alter table ordens_servico add column if not exists custo_total numeric(12,2);
alter table ordens_servico add column if not exists custo_hora_aplicado numeric(12,2);
alter table ordens_servico add column if not exists horas_apontadas_total numeric(10,2);
alter table ordens_servico add column if not exists custo_calculado_em timestamptz;

create or replace function rpc_definir_centro_custo_os(p_os_id uuid, p_centro_custo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para definir centro de custo da OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — centro de custo não pode mais ser alterado';
  end if;
  if p_centro_custo_id is not null and not exists (select 1 from centro_custo where id = p_centro_custo_id and ativo) then
    raise exception 'Centro de custo não encontrado ou inativo';
  end if;

  update ordens_servico set centro_custo_id = p_centro_custo_id where id = p_os_id;
  perform registrar_auditoria('ordens_servico', p_os_id, 'definir_centro_custo', null,
    jsonb_build_object('centro_custo_id', p_centro_custo_id), null);
end;
$$;

-- ============================================================
-- calcular_e_snapshot_custo_interno_os: chamada internamente por
-- rpc_concluir_os quando tipo = 'interna' (20260814110400). Não é exposta
-- como RPC pública — o cálculo só acontece automaticamente na conclusão,
-- exatamente uma vez (idempotente: se custo_calculado_em já estiver
-- preenchido, não recalcula — protege contra reentrância acidental).
--
-- CUSTO_PEÇAS = soma real do custo unitário registrado no ledger
-- (estoque_movimentos.custo_unitario, já é o custo médio no momento exato
-- da baixa — não o custo médio atual da peça, que pode ter mudado depois)
-- para toda saída vinculada a esta OS, líquida de estornos.
-- CUSTO_MÃO_DE_OBRA = horas apontadas (os_executores.inicio/fim, só
-- apontamentos fechados) × custo/hora vigente no momento da conclusão
-- (custo_hora_vigente(now())) — o valor aplicado fica GRAVADO
-- (custo_hora_aplicado), então uma mudança futura no custo/hora nunca
-- recalcula esta OS retroativamente (Decisão 2, explícito).
-- ============================================================
create or replace function calcular_e_snapshot_custo_interno_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ja_calculado timestamptz;
  v_custo_pecas numeric(12,2);
  v_horas numeric(10,2);
  v_custo_hora numeric(12,2);
  v_custo_mao_obra numeric(12,2);
begin
  select custo_calculado_em into v_ja_calculado from ordens_servico where id = p_os_id for update;
  if v_ja_calculado is not null then
    return; -- já encerrado/calculado — nunca recalcula (snapshot imutável)
  end if;

  select coalesce(sum(
      case when tipo = 'saida' then custo_unitario * quantidade
           when tipo = 'estorno_saida' then -1 * custo_unitario * quantidade
           else 0 end
    ), 0)
    into v_custo_pecas
    from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id;

  select coalesce(sum(extract(epoch from (fim - inicio)) / 3600.0), 0) into v_horas
    from os_executores
    where os_id = p_os_id and fim is not null;

  v_custo_hora := coalesce(custo_hora_vigente(now()), 0);
  v_custo_mao_obra := round(v_horas * v_custo_hora, 2);

  update ordens_servico
    set custo_pecas = v_custo_pecas,
        horas_apontadas_total = v_horas,
        custo_hora_aplicado = v_custo_hora,
        custo_mao_obra = v_custo_mao_obra,
        custo_total = v_custo_pecas + v_custo_mao_obra,
        custo_calculado_em = now()
    where id = p_os_id;

  perform registrar_auditoria('ordens_servico', p_os_id, 'calcular_custo_interno', null,
    jsonb_build_object('custo_pecas', v_custo_pecas, 'custo_mao_obra', v_custo_mao_obra,
      'custo_total', v_custo_pecas + v_custo_mao_obra, 'custo_hora_aplicado', v_custo_hora, 'horas', v_horas),
    null);
end;
$$;

revoke execute on function calcular_e_snapshot_custo_interno_os(uuid) from public, anon, authenticated;

-- Defesa em profundidade: nenhuma cobrança pode ser criada para OS interna
-- (já impedido por rpc_criar_cobranca exigir tipo='externa' desde a Fase 3
-- — mantido aqui só como documentação executável, não uma regra nova).
comment on function rpc_criar_cobranca(uuid, uuid[], uuid[]) is
  'Só aceita OS tipo=externa e concluída (checagem existente desde a Fase 3) — OS interna estruturalmente nunca gera cobrança (Decisão 1, ETAPA 6/P1-C, BUSINESS_RULES.md).';
