-- ETAPA OS-ESCOPO-04 (fix) — rpc_editar_item_escopo_os e
-- rpc_remover_item_escopo_os (20260821150000_p4_os_escopo04.sql) checavam
-- só execucao_status do item, nunca o status da OS dona — um item ainda
-- 'pendente' (nunca utilizado) numa OS já 'concluida'/'liberada'/'cancelada'
-- podia ser editado/removido livremente pelas duas RPCs. Achado ao testar
-- ao vivo em DEV/QA numa OS real já concluída. Mesmo padrão de guarda que
-- rpc_marcar_item_orcamento_execucao/rpc_marcar_item_os_adicional_execucao
-- já usam ("OS já concluída/liberada — use uma correção formal auditada").

create or replace function rpc_editar_item_escopo_os(
  p_escopo_item_id uuid,
  p_quantidade numeric default null,
  p_descricao text default null,
  p_peca_id uuid default null,
  p_valor_unitario numeric default null,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_escopo record;
  v_os_status status_os;
  v_qtd_origem numeric(12,3);
  v_valor_origem numeric(12,2);
  v_antes jsonb;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para editar item do escopo da OS';
  end if;

  select * into v_escopo from os_escopo_itens where id = p_escopo_item_id for update;
  if v_escopo.id is null then
    raise exception 'Item de escopo não encontrado';
  end if;

  select status into v_os_status from ordens_servico where id = v_escopo.os_id;
  if v_os_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada (%) — escopo operacional não pode mais ser editado', v_os_status;
  end if;

  if v_escopo.execucao_status in ('executado', 'parcial') then
    raise exception 'Item já tem utilização/execução registrada (%) — não pode mais ser editado; use o fluxo formal de estorno se precisar corrigir', v_escopo.execucao_status;
  end if;
  if v_escopo.execucao_status = 'cancelado' then
    raise exception 'Item já foi removido do escopo desta OS';
  end if;

  if v_escopo.origem_tipo = 'orcamento' then
    select quantidade, valor_unitario into v_qtd_origem, v_valor_origem
      from orcamento_itens where id = v_escopo.orcamento_item_id;
  else
    select quantidade, valor_unitario into v_qtd_origem, v_valor_origem
      from os_adicional_itens where id = v_escopo.os_adicional_item_id;
  end if;

  if p_quantidade is not null and p_quantidade > v_qtd_origem then
    raise exception 'Quantidade solicitada (%) excede o aprovado na origem (%) — aumento de escopo exige Adicional, não edição direta', p_quantidade, v_qtd_origem;
  end if;
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'Quantidade deve ser positiva';
  end if;
  if p_valor_unitario is not null and p_valor_unitario > v_valor_origem then
    raise exception 'Valor unitário solicitado (%) excede o aprovado na origem (%) — aumento de valor exige Adicional, não edição direta', p_valor_unitario, v_valor_origem;
  end if;
  if p_valor_unitario is not null and p_valor_unitario < 0 then
    raise exception 'Valor unitário inválido';
  end if;
  if p_peca_id is not null and not exists (select 1 from pecas where id = p_peca_id) then
    raise exception 'Peça não encontrada';
  end if;

  v_antes := jsonb_build_object(
    'quantidade_escopo', v_escopo.quantidade_escopo,
    'descricao_override', v_escopo.descricao_override,
    'peca_id_override', v_escopo.peca_id_override,
    'valor_unitario_override', v_escopo.valor_unitario_override
  );

  update os_escopo_itens set
    quantidade_escopo = coalesce(p_quantidade, quantidade_escopo),
    descricao_override = coalesce(p_descricao, descricao_override),
    peca_id_override = coalesce(p_peca_id, peca_id_override),
    valor_unitario_override = coalesce(p_valor_unitario, valor_unitario_override),
    editado_em = now(),
    editado_por = auth.uid()
    where id = p_escopo_item_id;

  perform registrar_auditoria('os_escopo_itens', p_escopo_item_id, 'os_item_editado', v_antes,
    jsonb_build_object(
      'quantidade_escopo', coalesce(p_quantidade, v_escopo.quantidade_escopo),
      'descricao_override', coalesce(p_descricao, v_escopo.descricao_override),
      'peca_id_override', coalesce(p_peca_id, v_escopo.peca_id_override),
      'valor_unitario_override', coalesce(p_valor_unitario, v_escopo.valor_unitario_override)
    ), p_motivo);
end;
$$;

create or replace function rpc_remover_item_escopo_os(
  p_escopo_item_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_escopo record;
  v_os_status status_os;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para remover item do escopo da OS';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Remover um item do escopo exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select * into v_escopo from os_escopo_itens where id = p_escopo_item_id for update;
  if v_escopo.id is null then
    raise exception 'Item de escopo não encontrado';
  end if;

  select status into v_os_status from ordens_servico where id = v_escopo.os_id;
  if v_os_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada (%) — escopo operacional não pode mais ser alterado', v_os_status;
  end if;

  if v_escopo.execucao_status in ('executado', 'parcial') then
    raise exception 'Item já tem utilização/execução registrada (%) — não pode ser removido; use o fluxo formal de estorno se precisar corrigir', v_escopo.execucao_status;
  end if;
  if v_escopo.execucao_status = 'cancelado' then
    return; -- já removido, idempotente
  end if;

  update os_escopo_itens set
    execucao_status = 'cancelado',
    removido_em = now(),
    removido_por = auth.uid(),
    motivo_remocao = p_motivo
    where id = p_escopo_item_id;

  perform registrar_auditoria('os_escopo_itens', p_escopo_item_id, 'os_item_removido',
    jsonb_build_object('execucao_status', v_escopo.execucao_status),
    jsonb_build_object('execucao_status', 'cancelado'), p_motivo);
end;
$$;
