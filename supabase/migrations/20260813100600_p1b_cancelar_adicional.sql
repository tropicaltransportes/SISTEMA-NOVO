-- ETAPA 5 (P1-B) — achado real durante execução do E2E principal
-- (docs/testing/_etapa5_e2e_full_output.txt): a regra nova do item 9
-- ("adicional ainda aguardando decisão bloqueia a conclusão da OS") não
-- tinha nenhum jeito formal de encerrar um adicional que deixou de fazer
-- sentido (ex.: identificado por engano, ADC-008 testado com header vazio,
-- ou o encarregado decide não seguir com nenhum item dele) — ficaria preso
-- em 'aguardando_aprovacao' para sempre, bloqueando a OS indefinidamente.
--
-- rpc_cancelar_os_adicional: só permitido enquanto o adicional ainda está
-- 'aguardando_aprovacao' (nenhum item aprovado dele já foi executado — se já
-- foi, não é mais "cancelamento", é uma situação diferente fora do escopo
-- desta etapa). Rejeita formalmente todos os itens ainda pendentes (motivo
-- obrigatório, auditado — item 9 "itens cancelados formalmente precisam
-- preservar motivo/auditoria"); itens que porventura já tenham sido
-- decididos individualmente permanecem com a decisão original intacta
-- (nunca reescreve histórico).
create or replace function rpc_cancelar_os_adicional(p_adicional_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adicional record;
  v_item record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar adicional';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Cancelar um adicional exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select id, os_id, status into v_adicional from os_adicionais where id = p_adicional_id for update;
  if v_adicional.id is null then
    raise exception 'Adicional não encontrado';
  end if;
  if v_adicional.status <> 'aguardando_aprovacao' then
    raise exception 'Só é possível cancelar um adicional ainda aguardando aprovação (status atual: %) — itens já decididos individualmente devem ser tratados item a item', v_adicional.status;
  end if;

  for v_item in select id from os_adicional_itens where adicional_id = p_adicional_id and status_aprovacao = 'pendente'
  loop
    update os_adicional_itens
      set status_aprovacao = 'rejeitado',
          meio_aprovacao = 'sistema',
          autorizado_por_nome = 'Cancelamento do adicional',
          autorizado_em = now(),
          registrado_por = auth.uid(),
          observacao = p_motivo
      where id = v_item.id;
    perform registrar_auditoria('os_adicional_itens', v_item.id, 'cancelar_item_adicional_por_cancelamento_cabecalho',
      jsonb_build_object('status_aprovacao', 'pendente'),
      jsonb_build_object('status_aprovacao', 'rejeitado'), p_motivo);
  end loop;

  perform registrar_auditoria('os_adicionais', p_adicional_id, 'cancelar_adicional', null,
    jsonb_build_object('os_id', v_adicional.os_id), p_motivo);

  -- Cancelamento sempre resolve o cabeçalho como 'rejeitado' — inclusive o
  -- caso de adicional SEM nenhum item (header vazio), que
  -- recalcular_status_os_adicional trataria como 'aguardando_aprovacao'
  -- (regra pensada para "ainda não decidido", não para "cancelado"); por
  -- isso aqui a transição é explícita, não delega ao recompute genérico.
  update os_adicionais set status = 'rejeitado' where id = p_adicional_id;
end;
$$;
