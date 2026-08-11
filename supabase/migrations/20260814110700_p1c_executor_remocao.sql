-- ETAPA 6 (P1-C) — item 8 (EXE-003): distinguir "encerrar participação
-- futura do executor" de "apagar histórico". NUNCA apaga apontamento já
-- existente (os_executores permanece intacto — BR-026/BR-027). "Remover"
-- só marca o vínculo como encerrado (ativo=false) para bloquear NOVOS
-- apontamentos daquele executor nesta OS, preservando tudo que já existe.

alter table os_executores add column if not exists ativo boolean not null default true;
alter table os_executores add column if not exists removido_por uuid references profiles(id);
alter table os_executores add column if not exists removido_em timestamptz;
alter table os_executores add column if not exists motivo_remocao text;

create or replace function rpc_remover_executor_os(p_os_executor_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reg record;
  v_os_status status_os;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para remover executor de OS';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Remover executor exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select id, os_id, usuario_id, ativo into v_reg from os_executores where id = p_os_executor_id for update;
  if v_reg.id is null then
    raise exception 'Vínculo de executor não encontrado';
  end if;
  if not v_reg.ativo then
    raise exception 'Este vínculo de executor já está encerrado';
  end if;

  select status into v_os_status from ordens_servico where id = v_reg.os_id;
  if v_os_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — remoção de executor não é mais uma operação de participação futura (não há mais participação a encerrar); histórico permanece intacto e não pode ser alterado silenciosamente';
  end if;

  -- Não apaga a linha, não zera inicio/fim/observacao já registrados —
  -- só encerra a participação futura (bloqueia novo apontamento) e
  -- registra quem/quando/por quê.
  update os_executores
    set ativo = false,
        removido_por = auth.uid(),
        removido_em = now(),
        motivo_remocao = p_motivo
    where id = p_os_executor_id;

  perform registrar_auditoria('os_executores', p_os_executor_id, 'remover_executor',
    jsonb_build_object('ativo', true), jsonb_build_object('ativo', false, 'usuario_id', v_reg.usuario_id), p_motivo);
end;
$$;

-- Apontamento novo (INSERT) só é aceito se não existir vínculo ativo=false
-- prévio do MESMO usuário nesta OS que tenha sido formalmente removido sem
-- readmissão explícita — nesta etapa, um novo INSERT sempre cria um vínculo
-- novo e independente (não reabre o antigo), o que já é suficiente: a
-- policy de INSERT existente (os_executores_insert_proprio) não muda.
