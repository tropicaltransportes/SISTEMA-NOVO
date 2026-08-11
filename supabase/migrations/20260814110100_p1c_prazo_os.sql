-- ETAPA 6 (P1-C) — Decisão 3 (PEN-003): prazo definido MANUALMENTE pelo
-- encarregado (sem faixas automáticas por valor nesta etapa). Campo
-- estruturado com histórico de alteração + motivo.

alter table ordens_servico add column if not exists previsao_conclusao timestamptz;
alter table ordens_servico add column if not exists previsao_definida_por uuid references profiles(id);
alter table ordens_servico add column if not exists previsao_definida_em timestamptz;

create table os_prazo_historico (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  previsao_conclusao timestamptz not null,
  motivo text,
  definido_por uuid not null references profiles(id),
  definido_em timestamptz not null default now()
);

create index idx_os_prazo_historico_os on os_prazo_historico (os_id, definido_em desc);

alter table os_prazo_historico enable row level security;

create policy "os_prazo_historico_select_autenticado" on os_prazo_historico
  for select
  using (current_user_ativo());

revoke insert, update, delete on os_prazo_historico from authenticated, anon;

-- rpc_definir_previsao_conclusao: encarregado/administrador_tecnico. Exige
-- motivo quando é uma ALTERAÇÃO (já havia prazo definido antes) — a 1ª
-- definição não exige motivo (não há o que "explicar a mudança de" ainda).
-- Permitida enquanto a OS estiver em andamento (não encerrada/cancelada).
create or replace function rpc_definir_previsao_conclusao(
  p_os_id uuid,
  p_previsao_conclusao timestamptz,
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
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para definir prazo da OS';
  end if;

  select id, status, previsao_conclusao into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — prazo não pode mais ser alterado';
  end if;
  if p_previsao_conclusao is null then
    raise exception 'Informe a data/hora prevista de conclusão';
  end if;

  if v_os.previsao_conclusao is not null and (p_motivo is null or length(trim(p_motivo)) < 5) then
    raise exception 'Alterar um prazo já definido exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  insert into os_prazo_historico (os_id, previsao_conclusao, motivo, definido_por)
  values (p_os_id, p_previsao_conclusao, p_motivo, auth.uid());

  update ordens_servico
    set previsao_conclusao = p_previsao_conclusao,
        previsao_definida_por = auth.uid(),
        previsao_definida_em = now()
    where id = p_os_id;

  perform registrar_auditoria('ordens_servico', p_os_id, 'definir_previsao_conclusao',
    jsonb_build_object('previsao_conclusao', v_os.previsao_conclusao),
    jsonb_build_object('previsao_conclusao', p_previsao_conclusao), p_motivo);
end;
$$;
