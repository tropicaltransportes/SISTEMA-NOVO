-- ETAPA 4 (P1-A) — item I: DOC-005, não aceitar arquivo_path/comprovante_path
-- arbitrário sem validar que o objeto existe de fato no Storage. Antes,
-- rpc_registrar_autorizacao_orcamento/rpc_registrar_termo_ciencia só
-- checavam texto não-nulo/não-vazio — qualquer string era aceita, mesmo sem
-- nenhum arquivo real por trás (objeto inexistente, bucket errado, ou
-- removido entre o upload e o registro).
--
-- As duas RPCs são SECURITY DEFINER, então conseguem ler storage.objects
-- (protegida por RLS própria do Storage) independente da policy de leitura
-- do bucket para o chamador — validação acontece no servidor, não confia no
-- que o frontend diz que enviou.
create or replace function storage_objeto_existe(p_bucket text, p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from storage.objects where bucket_id = p_bucket and name = p_path
  )
$$;

comment on function storage_objeto_existe is
  'Confirma que um objeto existe de fato no bucket informado antes de aceitar o path como referência válida (DOC-005). Mitigação prática contra race condition entre upload/uso: checagem acontece no momento da gravação da referência, dentro da mesma RPC — não elimina 100% uma remoção concorrente entre o SELECT e o commit (Storage não é transacional com Postgres), mas fecha a lacuna de referência nunca validada que existia antes.';

revoke execute on function storage_objeto_existe(text, text) from public, anon, authenticated;

create or replace function rpc_registrar_autorizacao_orcamento(
  p_orcamento_id uuid,
  p_autorizado_por_nome text,
  p_comprovante_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar autorização';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'enviado' then
    raise exception 'Autorização só pode ser registrada em orçamento enviado';
  end if;

  if p_comprovante_path is not null and not storage_objeto_existe('comprovantes', p_comprovante_path) then
    raise exception 'Comprovante informado não foi encontrado no Storage (bucket comprovantes, path %) — envie o arquivo antes de registrar a autorização', p_comprovante_path;
  end if;

  update orcamentos
    set autorizado_por_nome = p_autorizado_por_nome,
        comprovante_path = p_comprovante_path,
        autorizado_em = now()
    where id = p_orcamento_id;
end;
$$;

create or replace function rpc_registrar_termo_ciencia(p_cobranca_id uuid, p_arquivo_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_cobranca;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar termo de ciência';
  end if;

  if p_arquivo_path is null or p_arquivo_path = '' then
    raise exception 'Arquivo do termo é obrigatório';
  end if;

  if not storage_objeto_existe('comprovantes', p_arquivo_path) then
    raise exception 'Arquivo do termo não foi encontrado no Storage (bucket comprovantes, path %) — envie o arquivo antes de registrar o termo', p_arquivo_path;
  end if;

  select status into v_status from cobrancas where id = p_cobranca_id for update;
  if v_status is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe termo de ciência';
  end if;

  insert into termos_ciencia_debito (cobranca_id, arquivo_path) values (p_cobranca_id, p_arquivo_path);
end;
$$;
