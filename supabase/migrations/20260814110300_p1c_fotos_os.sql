-- ETAPA 6 (P1-C) — Decisão 6 (PEN-006) / item 2 (EXE-005/006/007): fotos
-- antes/depois da OS. Bucket próprio (fotos são potencialmente muitas e
-- grandes; separar de 'comprovantes' evita misturar política de
-- retenção/tamanho de dois tipos de documento bem diferentes).
--
-- Convenção de path: '{os_id}/{tipo}/{uuid}-{nome_original}' — o os_id no
-- início do path é o que permite a policy de Storage (e a revalidação na
-- RPC) confirmarem que o objeto pertence à OS informada, sem precisar de
-- uma tabela auxiliar só para isso.

insert into storage.buckets (id, name, public)
values ('os-fotos', 'os-fotos', false)
on conflict (id) do nothing;

create policy "os_fotos_storage_select_autenticado" on storage.objects
  for select
  to authenticated
  using (bucket_id = 'os-fotos' and current_user_ativo());

-- Upload: encarregado/administrador_tecnico sempre; executor só na pasta da
-- OS em que está de fato atuando (os_executores) — mesmo espírito de
-- PODE_APONTAR_EXECUCAO. (storage.foldername(name))[1] é o primeiro
-- segmento do path = os_id.
create policy "os_fotos_storage_insert_autorizado" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'os-fotos'
    and (
      current_perfil() in ('encarregado', 'administrador_tecnico', 'suporte_administrativo')
      or (
        current_perfil() = 'executor'
        and exists (
          select 1 from os_executores oe
          where oe.usuario_id = auth.uid()
            and oe.os_id::text = (storage.foldername(name))[1]
        )
      )
    )
  );

create table os_fotos (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  tipo text not null constraint os_fotos_tipo_check check (tipo in ('antes', 'depois', 'outro')),
  arquivo_path text not null,
  mime_type text not null,
  tamanho_bytes bigint not null,
  enviado_por uuid not null references profiles(id),
  enviado_em timestamptz not null default now(),
  observacao text
);

create index idx_os_fotos_os on os_fotos (os_id, tipo);

alter table os_fotos enable row level security;

create policy "os_fotos_select_autenticado" on os_fotos
  for select
  using (current_user_ativo());

revoke insert, update, delete on os_fotos from authenticated, anon;

-- ============================================================
-- rpc_registrar_foto_os: valida (DOC-005, mesmo padrão de
-- storage_objeto_existe) que o objeto existe de fato, e usa os METADADOS
-- REAIS gravados pelo Storage no upload (mimetype/size, não o que o
-- cliente alegou) para validar MIME/tamanho — "não confiar somente no MIME
-- enviado pelo browser" (instrução item 2). Também confirma que o path
-- pertence à OS informada (bloqueia "vincular foto de outra OS").
-- ============================================================
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

  select id, status into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
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

-- ============================================================
-- Decisão 6 / item 3: obrigatoriedade de foto por tipo de serviço
-- (checklist_templates), nunca global. Configurável por
-- encarregado/administrador_tecnico (mesma autoridade de gerir checklist).
-- ============================================================
alter table checklist_templates add column if not exists foto_antes_obrigatoria boolean not null default false;
alter table checklist_templates add column if not exists foto_depois_obrigatoria boolean not null default false;

create or replace function rpc_definir_obrigatoriedade_fotos(
  p_template_id uuid,
  p_foto_antes_obrigatoria boolean,
  p_foto_depois_obrigatoria boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para configurar obrigatoriedade de fotos';
  end if;

  select foto_antes_obrigatoria, foto_depois_obrigatoria into v_anterior
    from checklist_templates where id = p_template_id for update;
  if not found then
    raise exception 'Checklist/tipo de serviço não encontrado';
  end if;

  update checklist_templates
    set foto_antes_obrigatoria = coalesce(p_foto_antes_obrigatoria, false),
        foto_depois_obrigatoria = coalesce(p_foto_depois_obrigatoria, false)
    where id = p_template_id;

  perform registrar_auditoria('checklist_templates', p_template_id, 'definir_obrigatoriedade_fotos',
    to_jsonb(v_anterior),
    jsonb_build_object('foto_antes_obrigatoria', p_foto_antes_obrigatoria, 'foto_depois_obrigatoria', p_foto_depois_obrigatoria),
    null);
end;
$$;
