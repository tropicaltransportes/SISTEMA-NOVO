-- ETAPA 6 (P1-C) — Decisão 8 (PEN-008): estrutura formal do Termo de
-- Ciência de Débito. A tabela existia desde a Fase 3 só com
-- (cobranca_id, arquivo_path, assinado_em) — insuficiente para o registro
-- mínimo exigido (cliente, OS relacionada(s), valor reconhecido,
-- responsável do cliente, documento, quem registrou, observação).

alter table termos_ciencia_debito add column if not exists cliente_id uuid references clientes(id);
alter table termos_ciencia_debito add column if not exists valor_reconhecido numeric(12,2);
alter table termos_ciencia_debito add column if not exists responsavel_nome text;
alter table termos_ciencia_debito add column if not exists responsavel_documento text;
alter table termos_ciencia_debito add column if not exists registrado_por uuid references profiles(id);
alter table termos_ciencia_debito add column if not exists observacao text;
alter table termos_ciencia_debito add column if not exists criado_em timestamptz not null default now();

-- Backfill de registros pré-existentes (se houver): cliente_id/valor
-- reconstituídos a partir da cobrança vinculada — não há dado de
-- responsável/documento retroativo (nunca existiu no schema antigo), fica
-- null (histórico preservado, não inventado).
update termos_ciencia_debito t
  set cliente_id = c.cliente_id, valor_reconhecido = c.valor_total
  from cobrancas c
  where t.cobranca_id = c.id and t.cliente_id is null;

-- rpc_registrar_termo_ciencia: reusa storage_objeto_existe (DOC-005, mesma
-- proteção já implementada no P1-A) e passa a exigir os campos mínimos da
-- Decisão 8. cobranca_id continua sendo a origem financeira; as OS
-- relacionadas são derivadas de cobranca_origens (N:N já existente) — não
-- duplicamos esse vínculo numa coluna nova.
create or replace function rpc_registrar_termo_ciencia(
  p_cobranca_id uuid,
  p_arquivo_path text,
  p_responsavel_nome text,
  p_responsavel_documento text default null,
  p_observacao text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cobranca record;
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar termo de ciência';
  end if;

  if p_arquivo_path is null or p_arquivo_path = '' then
    raise exception 'Arquivo do termo é obrigatório';
  end if;
  if p_responsavel_nome is null or length(trim(p_responsavel_nome)) < 2 then
    raise exception 'Nome do responsável pelo cliente é obrigatório';
  end if;

  if not storage_objeto_existe('comprovantes', p_arquivo_path) then
    raise exception 'Arquivo do termo não foi encontrado no Storage (bucket comprovantes, path %) — envie o arquivo antes de registrar o termo', p_arquivo_path;
  end if;

  select * into v_cobranca from cobrancas where id = p_cobranca_id for update;
  if v_cobranca.id is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_cobranca.status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe termo de ciência';
  end if;

  insert into termos_ciencia_debito
    (cobranca_id, arquivo_path, cliente_id, valor_reconhecido, responsavel_nome, responsavel_documento, registrado_por, observacao)
  values
    (p_cobranca_id, p_arquivo_path, v_cobranca.cliente_id, v_cobranca.valor_total, p_responsavel_nome, p_responsavel_documento, auth.uid(), p_observacao)
  returning id into v_novo_id;

  perform registrar_auditoria('termos_ciencia_debito', v_novo_id, 'registrar_termo_ciencia', null,
    jsonb_build_object('cobranca_id', p_cobranca_id, 'valor_reconhecido', v_cobranca.valor_total, 'responsavel_nome', p_responsavel_nome), p_observacao);

  return v_novo_id;
end;
$$;
