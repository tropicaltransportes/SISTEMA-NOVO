-- FEATURE-OS-CANCELAMENTO-01 (parte 4/3 — achado ao escrever os testes de
-- restauração) — exclusão lógica não muda `status` (só `deleted_at`), mas
-- o predicado de bloqueio de reconversão de BR-008 (`rpc_criar_os`) e o
-- predicado espelho de `rpc_restaurar_os_excluida` (migration
-- 20260818170000) só olhavam `status <> 'cancelada'`, sem saber que
-- `deleted_at` existe agora. Efeito: excluir uma OS "por engano" NÃO
-- liberava o orçamento para nova conversão (a OS excluída, com
-- status='aberta' intacto, continuava contando como "OS ativa" para o
-- bloqueio) — contradizendo o propósito da própria exclusão lógica. Os dois
-- predicados agora ignoram OS soft-deleted, do mesmo jeito que a RLS de
-- SELECT já ignora.

create or replace function rpc_criar_os(
  p_veiculo_id uuid,
  p_tipo tipo_os,
  p_orcamento_id uuid default null,
  p_solicitacao_id uuid default null,
  p_checklist_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_veiculo record;
  v_cliente_tipo tipo_cliente;
  v_orc record;
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para criar ordem de serviço';
  end if;

  select v.id, v.cliente_id into v_veiculo from veiculos v where v.id = p_veiculo_id and v.deleted_at is null;
  if v_veiculo.id is null then
    raise exception 'Veículo não encontrado';
  end if;

  select tipo into v_cliente_tipo from clientes where id = v_veiculo.cliente_id;
  if p_tipo = 'interna' and v_cliente_tipo <> 'interno' then
    raise exception 'OS interna exige veículo da frota própria (cliente interno)';
  end if;
  if p_tipo = 'externa' and v_cliente_tipo <> 'externo' then
    raise exception 'OS externa exige veículo de cliente externo';
  end if;

  if p_tipo = 'externa' then
    if p_orcamento_id is null then
      raise exception 'OS externa exige orçamento aprovado';
    end if;
  end if;

  if p_orcamento_id is not null then
    select * into v_orc from orcamentos where id = p_orcamento_id for update;
    if v_orc.id is null then
      raise exception 'Orçamento não encontrado';
    end if;
    if v_orc.status <> 'aprovado' then
      raise exception 'Orçamento precisa estar aprovado para gerar OS';
    end if;
    if v_orc.veiculo_id <> p_veiculo_id then
      raise exception 'Orçamento não pertence ao veículo informado';
    end if;
    -- BR-008: nunca mais de uma OS NÃO CANCELADA e NÃO EXCLUÍDA por
    -- orçamento, independente do tipo. OS cancelada OU excluída libera o
    -- orçamento para nova conversão; histórico de todas as OS é preservado.
    if exists (
      select 1 from ordens_servico os
      where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada' and os.deleted_at is null
    ) then
      raise exception 'Este orçamento já foi convertido em uma OS ativa';
    end if;
  end if;

  insert into ordens_servico (orcamento_id, veiculo_id, cliente_id, tipo, checklist_template_id, criado_por)
  values (p_orcamento_id, p_veiculo_id, v_veiculo.cliente_id, p_tipo, p_checklist_template_id, auth.uid())
  returning id into v_novo_id;

  if p_solicitacao_id is not null then
    perform marcar_solicitacao_convertida(p_solicitacao_id, 'convertida_os');
  end if;

  return v_novo_id;
end;
$$;

create or replace function rpc_restaurar_os_excluida(
  p_os_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
begin
  if not tem_perfil('administrador_tecnico') then
    raise exception 'Perfil sem permissão para restaurar OS excluída';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  if v_os.deleted_at is null then
    raise exception 'Esta OS não está excluída — nada para restaurar';
  end if;

  if v_os.orcamento_id is not null and exists (
    select 1 from ordens_servico os2
    where os2.orcamento_id = v_os.orcamento_id and os2.id <> p_os_id
      and os2.status <> 'cancelada' and os2.deleted_at is null
  ) then
    raise exception 'O orçamento desta OS já foi convertido em outra OS ativa nesse meio-tempo — restauração bloqueada';
  end if;

  update ordens_servico
    set deleted_at = null, deleted_by = null, deleted_reason = null
    where id = p_os_id;

  perform registrar_auditoria('ordens_servico', p_os_id, 'OS_RESTAURADA',
    jsonb_build_object('deleted_at', v_os.deleted_at, 'deleted_by', v_os.deleted_by, 'deleted_reason', v_os.deleted_reason),
    jsonb_build_object('deleted_at', null),
    p_motivo);
end;
$$;
