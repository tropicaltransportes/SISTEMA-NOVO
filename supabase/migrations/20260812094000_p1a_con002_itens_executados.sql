-- ETAPA 4 (P1-A) — item E: CON-002, rpc_concluir_os passa a validar também
-- os itens aprovados da OS (além do checklist, que já era validado desde a
-- Fase 2). Usa orcamento_itens.execucao_status (criado no item D desta
-- rodada, sincronizado automaticamente pelas baixas de peça vinculadas).
--
-- Itens de mão de obra (peca_id is null) não têm sinal automático de
-- execução (não passam por baixa de estoque) — por isso esta RPC nova
-- permite marcar manualmente executado/parcial/cancelado, com motivo
-- obrigatório para 'cancelado' (auditável, ver item H desta rodada).
create or replace function rpc_marcar_item_orcamento_execucao(
  p_orcamento_item_id uuid,
  p_status text,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_os_id uuid;
  v_status_anterior text;
begin
  if not tem_perfil('executor', 'encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para marcar execução de item do orçamento';
  end if;

  if p_status not in ('pendente', 'parcial', 'executado', 'cancelado') then
    raise exception 'Status de execução inválido: %', p_status;
  end if;

  if p_status = 'cancelado' and (p_motivo is null or length(trim(p_motivo)) < 5) then
    raise exception 'Cancelar um item aprovado exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select oi.id, oi.orcamento_id, oi.execucao_status into v_item
    from orcamento_itens oi where oi.id = p_orcamento_item_id for update;
  if v_item.id is null then
    raise exception 'Item de orçamento não encontrado';
  end if;
  v_status_anterior := v_item.execucao_status;

  -- A OS que originou o item precisa existir e não estar encerrada — não faz
  -- sentido marcar execução de item de uma OS que nunca chegou a abrir, e
  -- CON-007 (item F desta rodada) já impede alterar execução depois de
  -- concluída/liberada/cancelada.
  select os.id into v_os_id from ordens_servico os where os.orcamento_id = v_item.orcamento_id and os.status <> 'cancelada' limit 1;
  if v_os_id is not null and exists (
    select 1 from ordens_servico where id = v_os_id and status in ('concluida', 'liberada')
  ) then
    raise exception 'OS já concluída/liberada — use uma correção formal auditada, não a marcação direta de execução';
  end if;

  update orcamento_itens set execucao_status = p_status where id = p_orcamento_item_id;

  perform registrar_auditoria('orcamento_itens', p_orcamento_item_id, 'marcar_execucao_item',
    jsonb_build_object('execucao_status', v_status_anterior), jsonb_build_object('execucao_status', p_status), p_motivo);
end;
$$;

-- ============================================================
-- rpc_concluir_os: além do checklist (já existia), agora também bloqueia se
-- houver item aprovado do orçamento em estado 'pendente' ou 'parcial'
-- (BR-021). 'cancelado' não bloqueia (foi formalmente dispensado, com
-- motivo). Só se aplica quando a OS tem orcamento_id — OS interna sem
-- orçamento continua exigindo só o checklist, como sempre foi.
-- ============================================================
create or replace function rpc_concluir_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_pendente boolean;
  v_itens_pendentes boolean;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para concluir OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'aguardando_teste' then
    raise exception 'Somente OS em Aguardando Teste podem ser concluídas';
  end if;
  if v_os.checklist_template_id is null then
    raise exception 'OS sem checklist técnico definido — associe um checklist antes de concluir';
  end if;

  select exists (
    select 1 from checklist_template_itens cti
    where cti.template_id = v_os.checklist_template_id
      and cti.obrigatorio
      and not exists (
        select 1 from os_checklist_respostas r
        where r.template_item_id = cti.id and r.os_id = p_os_id and r.ok = true
      )
  ) into v_pendente;

  if v_pendente then
    raise exception 'Existem itens obrigatórios do checklist pendentes';
  end if;

  if v_os.orcamento_id is not null then
    select exists (
      select 1 from orcamento_itens
      where orcamento_id = v_os.orcamento_id and execucao_status in ('pendente', 'parcial')
    ) into v_itens_pendentes;

    if v_itens_pendentes then
      raise exception 'Existem itens aprovados do orçamento pendentes ou parcialmente executados — baixe as peças aprovadas ou marque a execução (rpc_marcar_item_orcamento_execucao) antes de concluir';
    end if;
  end if;

  update ordens_servico set status = 'concluida' where id = p_os_id;
end;
$$;
