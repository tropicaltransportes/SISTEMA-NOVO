-- ETAPA 4 (P1-A) — item F: CON-007, apontamento de execução (os_executores)
-- não pode mais ser editado livremente depois que a OS está
-- concluída/liberada/cancelada. Achado original (rodada 1, código): a
-- policy "os_executores_update_proprio" só checava `usuario_id = auth.uid()`
-- — nenhum perfil, nenhum status de OS. Qualquer executor podia alterar seu
-- próprio apontamento (inclusive `fim`, `observacao`) a qualquer momento,
-- mesmo anos depois da OS encerrada.
drop policy if exists "os_executores_update_proprio" on os_executores;

create policy "os_executores_update_proprio" on os_executores
  for update
  using (
    usuario_id = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (
      select 1 from ordens_servico os
      where os.id = os_executores.os_id and os.status not in ('concluida', 'liberada', 'cancelada')
    )
  )
  with check (
    usuario_id = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
  );

comment on policy "os_executores_update_proprio" on os_executores is
  'CON-007: só o próprio executor edita seu apontamento, e só enquanto a OS não está concluída/liberada/cancelada. Correção depois do encerramento passa obrigatoriamente por rpc_corrigir_apontamento (auditada), nunca por UPDATE direto.';

-- Correção formal e auditada, para quando um apontamento precisa ser
-- ajustado DEPOIS da OS já ter sido encerrada (ex.: executor esqueceu de
-- encerrar o apontamento antes da OS ser concluída). Só encarregado/admin
-- técnico, sempre com motivo, sempre deixando rastro em auditoria_eventos.
create or replace function rpc_corrigir_apontamento(
  p_execucao_id uuid,
  p_novo_fim timestamptz default null,
  p_nova_observacao text default null,
  p_motivo text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exec record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para corrigir apontamento';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Correção de apontamento exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select * into v_exec from os_executores where id = p_execucao_id for update;
  if v_exec.id is null then
    raise exception 'Apontamento não encontrado';
  end if;

  update os_executores
    set fim = coalesce(p_novo_fim, fim),
        observacao = coalesce(p_nova_observacao, observacao)
    where id = p_execucao_id;

  perform registrar_auditoria('os_executores', p_execucao_id, 'correcao_apontamento',
    jsonb_build_object('fim', v_exec.fim, 'observacao', v_exec.observacao),
    jsonb_build_object('fim', coalesce(p_novo_fim, v_exec.fim), 'observacao', coalesce(p_nova_observacao, v_exec.observacao)),
    p_motivo);
end;
$$;
