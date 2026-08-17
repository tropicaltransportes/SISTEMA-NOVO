-- FEATURE-ORCAMENTO-EXCLUSAO-01 (parte 1/3) — exclusão lógica de rascunho.
--
-- Hoje não existe forma operacional de remover um orçamento criado por
-- engano: rascunhos vazios, testes e duplicados se acumulam sem saída, e
-- DELETE físico nunca é seguro (quebraria rastreabilidade comercial e as
-- ligações com aprovação/OS/cobrança/auditoria/garantia — BR-026). Esta
-- migration adiciona soft delete a `orcamentos`, seguindo a mesma convenção
-- já usada em clientes/veiculos/pecas (deleted_at/deleted_by/deleted_reason).
--
-- Itens (orcamento_itens) NÃO ganham coluna própria de exclusão: continuam
-- fisicamente presentes e ficam ocultos apenas transitivamente, através da
-- RLS do orçamento pai — histórico nunca é apagado (BR-026/BR-043).
--
-- O cancelamento formal de orçamento pós-rascunho (novo status 'cancelado')
-- fica para as próximas duas migrations desta etapa (150100 e 150200),
-- porque ALTER TYPE ... ADD VALUE não pode ser usado na mesma transação que
-- código que lê o novo valor (mesma restrição já contornada em
-- 20260813100000_p1b_status_orcamento_enum.sql).

alter table orcamentos
  add column deleted_at timestamptz,
  add column deleted_by uuid references profiles(id),
  add column deleted_reason text;

create index idx_orcamentos_deleted_at on orcamentos (deleted_at) where deleted_at is not null;

-- ============================================================
-- RLS — esconder excluídos é responsabilidade do banco, não do frontend.
-- Mesmo que o client remova um filtro .is('deleted_at', null) da query, a
-- linha nunca volta para quem não é administrador_tecnico.
-- ============================================================

alter policy "orcamentos_select_autenticado" on orcamentos
  using (current_user_ativo() and (deleted_at is null or tem_perfil('administrador_tecnico')));

alter policy "orcamento_itens_select_autenticado" on orcamento_itens
  using (
    current_user_ativo()
    and exists (
      select 1 from orcamentos o
      where o.id = orcamento_itens.orcamento_id
        and (o.deleted_at is null or tem_perfil('administrador_tecnico'))
    )
  );

-- status='rascunho' e deleted_at são ortogonais: um rascunho excluído
-- continua com status='rascunho'. Todo caminho de escrita direta gated por
-- "status = 'rascunho'" precisa também exigir "deleted_at is null".

alter policy "orcamentos_update_rascunho" on orcamentos
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and status = 'rascunho'
    and deleted_at is null
  )
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and status = 'rascunho'
    and deleted_at is null
  );

alter policy "orcamento_itens_insert_rascunho" on orcamento_itens
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (
      select 1 from orcamentos o
      where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho' and o.deleted_at is null
    )
  );

alter policy "orcamento_itens_update_rascunho" on orcamento_itens
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (
      select 1 from orcamentos o
      where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho' and o.deleted_at is null
    )
  )
  with check (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (
      select 1 from orcamentos o
      where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho' and o.deleted_at is null
    )
  );

alter policy "orcamento_itens_delete_rascunho" on orcamento_itens
  using (
    current_perfil() in ('encarregado', 'administrador_tecnico')
    and exists (
      select 1 from orcamentos o
      where o.id = orcamento_itens.orcamento_id and o.status = 'rascunho' and o.deleted_at is null
    )
  );

-- ============================================================
-- rpc_enviar_orcamento / rpc_aplicar_desconto_orcamento — reproduzidas na
-- íntegra (create or replace) só para acrescentar a guarda de deleted_at.
-- Nenhuma outra RPC precisa mudar: todas as demais já são gated por status
-- que um rascunho excluído nunca atinge sozinho, exceto estas duas, que
-- aceitam diretamente status='rascunho'.
-- ============================================================

create or replace function rpc_enviar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_qtd_itens int;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para enviar orçamento';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.deleted_at is not null then
    raise exception 'Orçamento excluído não pode ser enviado';
  end if;
  if v_orc.status <> 'rascunho' then
    raise exception 'Somente orçamentos em rascunho podem ser enviados';
  end if;

  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  if v_qtd_itens = 0 then
    raise exception 'Orçamento precisa de ao menos um item para ser enviado';
  end if;

  update orcamentos set status = 'enviado' where id = p_orcamento_id;
end;
$$;

create or replace function rpc_aplicar_desconto_orcamento(
  p_orcamento_id uuid,
  p_percentual numeric default null,
  p_valor numeric default null,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_config desconto_config;
  v_bruto numeric(12,2);
  v_desconto numeric(12,2);
  v_percentual_efetivo numeric(7,4);
  v_item record;
  v_restante numeric(12,2);
  v_rateado numeric(12,2);
  v_qtd_itens int;
  v_i int := 0;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para conceder desconto';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do desconto é obrigatório (mínimo de 5 caracteres)';
  end if;
  if (p_percentual is not null and p_valor is not null) or (p_percentual is null and p_valor is null) then
    raise exception 'Informe percentual OU valor de desconto, nunca os dois nem nenhum';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.deleted_at is not null then
    raise exception 'Orçamento excluído não pode receber desconto';
  end if;
  if v_orc.status <> 'rascunho' then
    raise exception 'Desconto só pode ser aplicado com o orçamento em rascunho — orçamento já enviado/aprovado exige nova versão (rpc_criar_versao_orcamento) para alterar valor comercial já apresentado ao cliente';
  end if;

  select coalesce(sum(valor_total), 0) into v_bruto from orcamento_itens where orcamento_id = p_orcamento_id;
  if v_bruto <= 0 then
    raise exception 'Orçamento sem itens (ou valor bruto zerado) — nada para aplicar desconto';
  end if;

  if p_valor is not null then
    if p_valor < 0 then
      raise exception 'Valor de desconto inválido';
    end if;
    v_desconto := p_valor;
  else
    if p_percentual < 0 or p_percentual > 100 then
      raise exception 'Percentual de desconto inválido (0 a 100)';
    end if;
    v_desconto := round(v_bruto * p_percentual / 100, 2);
  end if;

  if v_desconto > v_bruto then
    raise exception 'Desconto (R$ %) não pode exceder o valor bruto do orçamento (R$ %) — valor final nunca pode ficar negativo', v_desconto, v_bruto;
  end if;

  select * into v_config from desconto_config_vigente();
  if v_desconto > 0 then
    if v_config.id is null or not v_config.habilitado then
      raise exception 'Desconto está desabilitado na configuração vigente';
    end if;
    v_percentual_efetivo := (v_desconto / v_bruto) * 100;
    if v_percentual_efetivo > v_config.percentual_maximo then
      raise exception 'Desconto solicitado (%.2f%%) excede o teto configurado (%.2f%%)', v_percentual_efetivo, v_config.percentual_maximo;
    end if;
  end if;

  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  v_restante := v_desconto;
  for v_item in select id, valor_total from orcamento_itens where orcamento_id = p_orcamento_id order by id
  loop
    v_i := v_i + 1;
    if v_i = v_qtd_itens then
      v_rateado := v_restante;
    else
      v_rateado := round(v_item.valor_total / v_bruto * v_desconto, 2);
    end if;
    v_restante := v_restante - v_rateado;
    update orcamento_itens set desconto_rateado = v_rateado where id = v_item.id;
  end loop;

  update orcamentos
    set valor_bruto = v_bruto,
        desconto_valor = v_desconto,
        desconto_percentual = round((v_desconto / v_bruto) * 100, 2),
        desconto_motivo = p_motivo,
        desconto_por = auth.uid(),
        desconto_em = now(),
        valor_liquido = v_bruto - v_desconto,
        valor_total = v_bruto - v_desconto
    where id = p_orcamento_id;

  perform registrar_auditoria('orcamentos', p_orcamento_id, 'aplicar_desconto',
    jsonb_build_object('desconto_valor', v_orc.desconto_valor),
    jsonb_build_object('desconto_valor', v_desconto, 'desconto_percentual', round((v_desconto / v_bruto) * 100, 2)),
    p_motivo);
end;
$$;

-- ============================================================
-- rpc_excluir_orcamento_rascunho — exclusão lógica (BR-045).
-- Só rascunho, sem OS ativa vinculada (mesmo predicado de BR-008/OS-004,
-- reutilizado verbatim de rpc_criar_os), motivo obrigatório, idempotente
-- (repetir a chamada nunca re-processa nem duplica auditoria).
-- ============================================================
create or replace function rpc_excluir_orcamento_rascunho(
  p_orcamento_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para excluir orçamento';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo da exclusão é obrigatório (mínimo de 5 caracteres)';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;

  if v_orc.deleted_at is not null then
    raise exception 'Este orçamento já foi excluído em %', v_orc.deleted_at;
  end if;

  if v_orc.status <> 'rascunho' then
    raise exception 'Somente orçamentos em rascunho podem ser excluídos — use Cancelar Orçamento para os demais status (atual: %)', v_orc.status;
  end if;

  if exists (
    select 1 from ordens_servico os
    where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada'
  ) then
    raise exception 'Este orçamento já foi convertido em uma OS ativa — não pode ser excluído';
  end if;

  update orcamentos
    set deleted_at = now(), deleted_by = auth.uid(), deleted_reason = p_motivo
    where id = p_orcamento_id;

  perform registrar_auditoria('orcamentos', p_orcamento_id, 'ORCAMENTO_EXCLUIDO',
    jsonb_build_object('deleted_at', null),
    jsonb_build_object('deleted_at', now(), 'deleted_by', auth.uid()),
    p_motivo);
end;
$$;

-- ============================================================
-- rpc_restaurar_orcamento_excluido — reversão administrativa (BR-047).
-- Mais restrito que a própria exclusão: só administrador_tecnico. Motivo
-- opcional (a exclusão original já está integralmente em auditoria_eventos).
-- ============================================================
create or replace function rpc_restaurar_orcamento_excluido(
  p_orcamento_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
begin
  if not tem_perfil('administrador_tecnico') then
    raise exception 'Perfil sem permissão para restaurar orçamento excluído';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;

  if v_orc.deleted_at is null then
    raise exception 'Este orçamento não está excluído — nada para restaurar';
  end if;

  update orcamentos
    set deleted_at = null, deleted_by = null, deleted_reason = null
    where id = p_orcamento_id;

  perform registrar_auditoria('orcamentos', p_orcamento_id, 'ORCAMENTO_RESTAURADO',
    jsonb_build_object('deleted_at', v_orc.deleted_at, 'deleted_by', v_orc.deleted_by, 'deleted_reason', v_orc.deleted_reason),
    jsonb_build_object('deleted_at', null),
    p_motivo);
end;
$$;
