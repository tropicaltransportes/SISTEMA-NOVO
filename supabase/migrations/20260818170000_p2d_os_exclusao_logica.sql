-- FEATURE-OS-CANCELAMENTO-01 (parte 1/3) — exclusão lógica de OS "virgem".
--
-- Só remove OS em status='aberta' sem NENHUM rastro operacional ainda
-- (apontamento, baixa de estoque, foto, adicional, resposta de checklist,
-- cobrança). Mesma convenção de soft delete já usada em
-- orcamentos/clientes/veiculos/pecas (deleted_at/deleted_by/deleted_reason).
-- DELETE físico nunca ocorre. Ver docs/testing/BUSINESS_RULES.md BR-048.

alter table ordens_servico
  add column deleted_at timestamptz,
  add column deleted_by uuid references profiles(id),
  add column deleted_reason text;

create index idx_os_deleted_at on ordens_servico (deleted_at) where deleted_at is not null;

-- RLS: esconder excluída é responsabilidade do banco, não do frontend —
-- mesmo padrão de BR-045 (orcamentos). Reproduz a using() atual
-- (current_user_ativo(), 20260812090000_p1a_aut004_bloqueio_total_inativo.sql:81-82)
-- + a nova condição de deleted_at. Só administrador_tecnico continua vendo
-- excluídas (para a tela de restauração).
alter policy "os_select_autenticado" on ordens_servico
  using (current_user_ativo() and (deleted_at is null or tem_perfil('administrador_tecnico')));

-- ============================================================
-- Guardas de deleted_at em policies/RPCs que só checavam status (a coluna
-- não existia antes desta migration) — sem isso, uma OS excluída
-- logicamente (status continua 'aberta') ainda aceitaria apontamento,
-- resposta de checklist, foto ou adicional por engano.
-- ============================================================

drop policy if exists "os_executores_insert_proprio" on os_executores;
create policy "os_executores_insert_proprio" on os_executores
  for insert
  with check (
    usuario_id = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (select 1 from ordens_servico os where os.id = os_executores.os_id and os.deleted_at is null)
  );

drop policy if exists "os_checklist_insert_resposta" on os_checklist_respostas;
create policy "os_checklist_insert_resposta" on os_checklist_respostas
  for insert
  with check (
    respondido_por = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (
      select 1 from ordens_servico os
      where os.id = os_checklist_respostas.os_id
        and os.status not in ('concluida', 'liberada', 'cancelada')
        and os.deleted_at is null
    )
  );

drop policy if exists "os_checklist_update_resposta" on os_checklist_respostas;
create policy "os_checklist_update_resposta" on os_checklist_respostas
  for update
  using (
    current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (
      select 1 from ordens_servico os
      where os.id = os_checklist_respostas.os_id
        and os.status not in ('concluida', 'liberada', 'cancelada')
        and os.deleted_at is null
    )
  )
  with check (
    respondido_por = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
  );

-- rpc_registrar_foto_os: corpo integral reproduzido de
-- 20260814110300_p1c_fotos_os.sql, só acrescentando a checagem de
-- deleted_at (select passa a trazer a coluna nova, guarda logo após a de
-- "não encontrada").
create or replace function rpc_registrar_foto_os(
  p_os_id uuid,
  p_tipo text,
  p_arquivo_path text,
  p_observacao text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_objeto record;
  v_config anexos_config;
  v_novo_id uuid;
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para anexar foto de OS';
  end if;

  if p_tipo not in ('antes', 'depois', 'outro') then
    raise exception 'Tipo de foto inválido: % (use antes, depois ou outro)', p_tipo;
  end if;
  if p_arquivo_path is null or trim(p_arquivo_path) = '' then
    raise exception 'Path do arquivo é obrigatório';
  end if;

  select id, status, deleted_at into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.deleted_at is not null then
    raise exception 'OS excluída não recebe novos anexos';
  end if;
  if v_os.status = 'cancelada' then
    raise exception 'OS cancelada não recebe novos anexos';
  end if;

  -- Executor só anexa foto da OS em que está de fato atuando.
  if current_perfil() = 'executor' and not exists (
    select 1 from os_executores where os_id = p_os_id and usuario_id = auth.uid()
  ) then
    raise exception 'Executor só pode anexar foto de OS em que esteja atuando';
  end if;

  -- Path precisa começar com o os_id informado — bloqueia vincular foto de
  -- outra OS (path de outra pasta) a este registro.
  if split_part(p_arquivo_path, '/', 1) <> p_os_id::text then
    raise exception 'Path do arquivo não pertence a esta OS — upload deve ir para a pasta %/', p_os_id;
  end if;

  select bucket_id, name, (metadata ->> 'mimetype') as mime, (metadata ->> 'size')::bigint as tamanho
    into v_objeto
    from storage.objects where bucket_id = 'os-fotos' and name = p_arquivo_path;
  if v_objeto.name is null then
    raise exception 'Arquivo não foi encontrado no Storage (bucket os-fotos, path %) — envie o arquivo antes de registrar', p_arquivo_path;
  end if;

  select * into v_config from anexos_config_vigente();
  if v_config.id is null then
    raise exception 'Configuração de anexos não definida — contate o administrador técnico';
  end if;
  if v_objeto.mime is null or not (v_objeto.mime = any(v_config.mime_permitidos)) then
    raise exception 'Tipo de arquivo não permitido (%) — permitidos: %', v_objeto.mime, v_config.mime_permitidos;
  end if;
  if v_objeto.tamanho is null or v_objeto.tamanho > v_config.tamanho_maximo_bytes then
    raise exception 'Arquivo excede o tamanho máximo permitido (% bytes, limite % bytes)', v_objeto.tamanho, v_config.tamanho_maximo_bytes;
  end if;

  insert into os_fotos (os_id, tipo, arquivo_path, mime_type, tamanho_bytes, enviado_por, observacao)
  values (p_os_id, p_tipo, p_arquivo_path, v_objeto.mime, v_objeto.tamanho, auth.uid(), p_observacao)
  returning id into v_novo_id;

  return v_novo_id;
end;
$$;

-- rpc_criar_os_adicional: corpo integral reproduzido de
-- 20260813100200_p1b_adc_tabelas.sql, só acrescentando a checagem de
-- deleted_at.
create or replace function rpc_criar_os_adicional(
  p_os_id uuid,
  p_motivo text,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_deleted_at timestamptz;
  v_numero int;
  v_novo_id uuid;
  v_existente uuid;
begin
  if not tem_perfil('executor', 'encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para identificar necessidade de adicional';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do adicional é obrigatório (mínimo de 5 caracteres)';
  end if;

  select status, deleted_at into v_status, v_deleted_at from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_deleted_at is not null then
    raise exception 'OS excluída — não é possível abrir adicional';
  end if;
  if v_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — não é possível abrir adicional';
  end if;

  if p_idempotency_key is not null then
    select id into v_existente from os_adicionais where os_id = p_os_id and idempotency_key = p_idempotency_key;
    if v_existente is not null then
      return v_existente; -- ADC-008: retry idempotente devolve o mesmo adicional já criado
    end if;
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero from os_adicionais where os_id = p_os_id;

  insert into os_adicionais (os_id, numero, motivo, idempotency_key, criado_por)
  values (p_os_id, v_numero, p_motivo, p_idempotency_key, auth.uid())
  returning id into v_novo_id;

  perform registrar_auditoria('os_adicionais', v_novo_id, 'criar_adicional', null,
    jsonb_build_object('os_id', p_os_id, 'numero', v_numero, 'motivo', p_motivo), null);

  return v_novo_id;
end;
$$;

-- ============================================================
-- rpc_excluir_os_rascunho — exclusão lógica de OS "aberta" e virgem.
--
-- Critério de "virgem" (BR-048): status='aberta' e ausência de qualquer
-- apontamento (os_executores — inicio é NOT NULL na tabela real, não
-- existe "atribuído sem iniciar" hoje), movimento de estoque, foto,
-- adicional (qualquer status), resposta de checklist real (checklist_
-- template_id sozinho na OS não bloqueia, é só seleção) ou cobrança
-- vinculada. OS de garantia nunca é excluída por este caminho — só
-- cancelada (rpc_cancelar_os já reverte a origem para 'liberada').
-- ============================================================
create or replace function rpc_excluir_os_rascunho(
  p_os_id uuid,
  p_motivo text
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
    raise exception 'Perfil sem permissão para excluir OS';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo da exclusão é obrigatório (mínimo de 5 caracteres)';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  if v_os.deleted_at is not null then
    raise exception 'Esta OS já foi excluída em %', v_os.deleted_at;
  end if;

  if v_os.status <> 'aberta' then
    raise exception 'Somente OS em aberta pode ser excluída — use Cancelar OS para as demais (atual: %)', v_os.status;
  end if;

  if v_os.os_origem_id is not null then
    raise exception 'OS de garantia não pode ser excluída — use Cancelar OS';
  end if;

  if exists (select 1 from os_executores where os_id = p_os_id) then
    raise exception 'Esta OS já tem apontamento registrado — não é mais uma OS virgem, use Cancelar OS';
  end if;

  if exists (select 1 from estoque_movimentos where origem_tipo = 'os' and origem_id = p_os_id) then
    raise exception 'Esta OS já tem movimentação de estoque registrada — use Cancelar OS';
  end if;

  if exists (select 1 from os_fotos where os_id = p_os_id) then
    raise exception 'Esta OS já tem foto anexada — use Cancelar OS';
  end if;

  if exists (select 1 from os_adicionais where os_id = p_os_id) then
    raise exception 'Esta OS já tem adicional registrado — use Cancelar OS';
  end if;

  if exists (select 1 from os_checklist_respostas where os_id = p_os_id) then
    raise exception 'Esta OS já tem resposta de checklist registrada — use Cancelar OS';
  end if;

  if exists (select 1 from cobranca_origens where os_id = p_os_id) then
    raise exception 'Esta OS já está vinculada a uma cobrança — use Cancelar OS';
  end if;

  update ordens_servico
    set deleted_at = now(), deleted_by = auth.uid(), deleted_reason = p_motivo
    where id = p_os_id;

  perform registrar_auditoria('ordens_servico', p_os_id, 'OS_EXCLUIDA',
    jsonb_build_object('deleted_at', null),
    jsonb_build_object('deleted_at', now(), 'deleted_by', auth.uid()),
    p_motivo);
end;
$$;

-- ============================================================
-- rpc_restaurar_os_excluida — reversão administrativa (BR-051). Só
-- administrador_tecnico — mais restrito que a própria exclusão, mesmo
-- padrão de BR-047 (orcamentos). Nunca restaura OS cancelada — cancelamento
-- é evento histórico, não "lixeira".
-- ============================================================
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

  -- Mesmo predicado de BR-008/BR-045: nunca reviver uma OS se o orçamento
  -- já foi reconvertido em outra OS ativa nesse meio-tempo.
  if v_os.orcamento_id is not null and exists (
    select 1 from ordens_servico os2
    where os2.orcamento_id = v_os.orcamento_id and os2.id <> p_os_id and os2.status <> 'cancelada'
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
