-- ETAPA 6 (P1-C) — item 3: obrigatoriedade de foto integrada à conclusão da
-- OS. Estende rpc_concluir_os (P1-B, 20260813100400) sem alterar nenhuma
-- das checagens já existentes (checklist técnico, itens de orçamento
-- aprovados, adicionais aprovados, adicional aguardando decisão) — só
-- adiciona a checagem de foto antes/depois quando o checklist_template da
-- OS exige.
create or replace function rpc_concluir_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_template record;
  v_pendente boolean;
  v_itens_pendentes boolean;
  v_adicional_itens_pendentes boolean;
  v_adicional_aguardando boolean;
  v_tem_foto_antes boolean;
  v_tem_foto_depois boolean;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para concluir OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'aguardando_teste' then
    raise exception 'Somente OS em Aguardando Teste podem ser concluídas';
  end if;
  if v_os.checklist_template_id is null then
    raise exception 'OS sem checklist técnico definido — associe um checklist antes de concluir';
  end if;

  select foto_antes_obrigatoria, foto_depois_obrigatoria into v_template
    from checklist_templates where id = v_os.checklist_template_id;

  select exists (
    select 1 from checklist_template_itens cti
    where cti.template_id = v_os.checklist_template_id
      and cti.obrigatorio
      and not exists (
        select 1 from os_checklist_respostas r
        where r.template_item_id = cti.id and r.os_id = p_os_id and r.ok = true
      )
  ) into v_pendente;

  if v_pendente then
    raise exception 'Existem itens obrigatórios do checklist pendentes';
  end if;

  -- Decisão 6 / item 3: só bloqueia se o tipo de serviço (checklist)
  -- desta OS exige — nunca obrigatoriedade global.
  if v_template.foto_antes_obrigatoria then
    select exists (select 1 from os_fotos where os_id = p_os_id and tipo = 'antes') into v_tem_foto_antes;
    if not v_tem_foto_antes then
      raise exception 'Este tipo de serviço exige foto ANTES da execução — anexe ao menos uma foto do tipo antes antes de concluir';
    end if;
  end if;
  if v_template.foto_depois_obrigatoria then
    select exists (select 1 from os_fotos where os_id = p_os_id and tipo = 'depois') into v_tem_foto_depois;
    if not v_tem_foto_depois then
      raise exception 'Este tipo de serviço exige foto DEPOIS da execução — anexe ao menos uma foto do tipo depois antes de concluir';
    end if;
  end if;

  if v_os.orcamento_id is not null then
    select exists (
      select 1 from orcamento_itens
      where orcamento_id = v_os.orcamento_id
        and status_aprovacao = 'aprovado'
        and execucao_status in ('pendente', 'parcial')
    ) into v_itens_pendentes;

    if v_itens_pendentes then
      raise exception 'Existem itens aprovados do orçamento pendentes ou parcialmente executados — baixe as peças aprovadas ou marque a execução (rpc_marcar_item_orcamento_execucao) antes de concluir';
    end if;
  end if;

  select exists (
    select 1 from os_adicionais a
    where a.os_id = p_os_id and a.status = 'aguardando_aprovacao'
  ) into v_adicional_aguardando;
  if v_adicional_aguardando then
    raise exception 'Existe adicional aguardando decisão do cliente — resolva a aprovação (ADC-003/004) antes de concluir';
  end if;

  select exists (
    select 1 from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    where a.os_id = p_os_id
      and oai.status_aprovacao = 'aprovado'
      and oai.execucao_status in ('pendente', 'parcial')
  ) into v_adicional_itens_pendentes;
  if v_adicional_itens_pendentes then
    raise exception 'Existem itens aprovados de adicional pendentes ou parcialmente executados — baixe as peças aprovadas ou marque a execução (rpc_marcar_item_os_adicional_execucao) antes de concluir';
  end if;

  update ordens_servico set status = 'concluida' where id = p_os_id;

  -- Decisão 1/2 (item 10): OS interna calcula e SNAPSHOTA o custo (peças +
  -- mão de obra) no momento da conclusão — nunca recalculado depois, mesmo
  -- que custo/hora ou custo médio de peça mudem no futuro.
  if v_os.tipo = 'interna' then
    perform calcular_e_snapshot_custo_interno_os(p_os_id);
  end if;
end;
$$;
