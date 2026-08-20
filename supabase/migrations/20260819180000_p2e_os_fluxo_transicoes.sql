-- ETAPA OS-FLOW-03 — corrige 2 lacunas reais na máquina de estados da OS,
-- confirmadas por auditoria do código atual (não documentação):
--
-- 1) Nenhuma RPC de transição verificava apontamento aberto
--    (os_executores.fim is null) antes de mudar de fase — uma OS podia
--    chegar em 'aguardando_teste' (ou ser concluída) com um apontamento de
--    execução ainda em andamento.
-- 2) rpc_transicionar_os só tinha transições pra frente — não havia
--    retorno controlado de fase quando, por exemplo, um problema é
--    encontrado durante o teste.
--
-- Ver docs/testing/BUSINESS_RULES.md BR-052/BR-053.
--
-- rpc_transicionar_os ganha um 3º parâmetro opcional (p_motivo default
-- null) — mesma RPC de sempre, sem quebrar nenhum chamador existente que
-- só passa (p_os_id, p_novo_status). Corpo reproduzido de
-- 20260818170100_p2d_os_cancelamento.sql:93-133, acrescentando:
--   a) 2 tuplas de retrocesso no v_permitido;
--   b) exigência de motivo (mín. 5 caracteres) só para essas 2 tuplas;
--   c) checagem de apontamento aberto pra QUALQUER transição (pra frente
--      ou pra trás) — o próprio fluxo pedido (Finalizar teste -> Retornar
--      para Execução) já espera o apontamento atual fechado antes;
--   d) auditoria explícita (com motivo) só no caminho de retrocesso — o
--      trigger genérico trg_audit_os_status já cobre toda transição com
--      um evento 'mudanca_status' sem motivo, igual sempre cobriu.
--
-- 'concluida -> teste/execução' foi avaliado e conscientemente NÃO
-- implementado nesta etapa (ver BR-053): uma OS concluida externa pode já
-- ter cobrança vinculada antes de liberada, e desfazer a conclusão sem
-- tratar essa cobrança é inseguro — o próprio pedido permite documentar em
-- vez de implementar quando o modelo atual tornar isso inseguro.
create or replace function rpc_transicionar_os(p_os_id uuid, p_novo_status status_os, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_permitido boolean := false;
  v_retrocesso boolean := false;
  v_apontamento_aberto boolean := false;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para transicionar OS';
  end if;

  if p_novo_status in ('concluida', 'liberada', 'reaberta_garantia') then
    raise exception 'Use a RPC específica para esta transição (rpc_concluir_os / rpc_liberar_os)';
  end if;
  if p_novo_status = 'cancelada' then
    raise exception 'Use rpc_cancelar_os para cancelar — exige motivo e trata apontamentos, adicionais, estoque e garantia';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  v_permitido := (v_status, p_novo_status) in (
    ('aberta', 'em_diagnostico'),
    ('em_diagnostico', 'aguardando_aprovacao'),
    ('em_diagnostico', 'em_execucao'),
    ('aguardando_aprovacao', 'em_execucao'),
    ('em_execucao', 'aguardando_teste'),
    ('aguardando_teste', 'em_execucao'),
    ('em_execucao', 'em_diagnostico')
  );

  if not v_permitido then
    raise exception 'Transição % -> % não é permitida', v_status, p_novo_status;
  end if;

  v_retrocesso := (v_status, p_novo_status) in (
    ('aguardando_teste', 'em_execucao'),
    ('em_execucao', 'em_diagnostico')
  );

  if v_retrocesso and (p_motivo is null or length(trim(p_motivo)) < 5) then
    raise exception 'Retornar de % para % exige motivo (mínimo 5 caracteres) — ação auditável', v_status, p_novo_status;
  end if;

  select exists (
    select 1 from os_executores
    where os_id = p_os_id and fim is null and coalesce(ativo, true)
  ) into v_apontamento_aberto;

  if v_apontamento_aberto then
    raise exception 'Finalize o apontamento em andamento antes de transicionar esta OS.';
  end if;

  update ordens_servico set status = p_novo_status where id = p_os_id;

  -- Apontamento novo (não reabre o antigo, BR-053): o executor que
  -- retomar o trabalho depois do retorno inicia um os_executores novo
  -- normalmente pela tela — nada a fazer aqui além de NÃO tocar em
  -- os_executores.
  if v_retrocesso then
    perform registrar_auditoria('ordens_servico', p_os_id,
      case p_novo_status when 'em_execucao' then 'OS_RETORNOU_PARA_EXECUCAO' else 'OS_RETORNOU_PARA_DIAGNOSTICO' end,
      jsonb_build_object('status', v_status), jsonb_build_object('status', p_novo_status), p_motivo);
  end if;
end;
$$;

-- rpc_concluir_os ganha a mesma checagem de apontamento aberto (item 11 do
-- pedido: "Não oferecer Concluir serviço enquanto existir qualquer
-- apontamento aberto"). Corpo idêntico ao de
-- 20260814110400_p1c_concluir_os_fotos.sql, só com a checagem nova logo
-- após confirmar que a OS está em 'aguardando_teste' — nenhuma das
-- checagens existentes (checklist, fotos, itens de orçamento/adicional,
-- snapshot de custo interno) foi alterada.
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
  v_apontamento_aberto boolean;
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

  select exists (
    select 1 from os_executores
    where os_id = p_os_id and fim is null and coalesce(ativo, true)
  ) into v_apontamento_aberto;
  if v_apontamento_aberto then
    raise exception 'Finalize o apontamento em andamento antes de concluir esta OS.';
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

  if v_os.tipo = 'interna' then
    perform calcular_e_snapshot_custo_interno_os(p_os_id);
  end if;
end;
$$;
