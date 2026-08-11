-- ETAPA 5 (P1-B) — item 9 (conclusão da OS considerando adicionais) e item
-- 10 (financeiro: cobrança = itens originais aprovados + adicionais
-- aprovados). Estende CON-002 (P1-A) e rpc_criar_cobranca (Fase 3) sem
-- reescrever a decisão técnica já tomada em nenhum dos dois.

-- ============================================================
-- rpc_concluir_os: além do checklist técnico e dos itens do orçamento
-- original (P1-A), agora também bloqueia quando:
--   - existe item do orçamento APROVADO em execucao_status
--     pendente/parcial (igual ao P1-A, mas agora filtrando por
--     status_aprovacao — item rejeitado nunca bloqueia conclusão);
--   - existe item de ADICIONAL aprovado em execucao_status
--     pendente/parcial;
--   - existe adicional ainda 'aguardando_aprovacao' (decisão do cliente
--     ainda em aberto) — não é possível concluir a OS "como se estivesse
--     resolvido" enquanto o cliente não decidiu.
-- ============================================================
create or replace function rpc_concluir_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_pendente boolean;
  v_itens_pendentes boolean;
  v_adicional_itens_pendentes boolean;
  v_adicional_aguardando boolean;
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
end;
$$;

-- ============================================================
-- rpc_criar_cobranca: o valor da OS deixa de ser orcamentos.valor_total
-- (soma de TODOS os itens, aprovados ou não) e passa a ser a soma dos itens
-- efetivamente APROVADOS — orçamento original + adicionais — mais os
-- acréscimos pós-aprovação já existentes (mecanismo independente, fora do
-- escopo desta etapa). Item rejeitado, pendente ou de adicional não
-- aprovado NUNCA entra na cobrança (item 10 do pedido, exemplo obrigatório:
-- orçamento R$1.000, aprovado R$700, adicional R$400, aprovado do
-- adicional R$250 -> cobrança final R$950).
-- ============================================================
create or replace function rpc_criar_cobranca(p_cliente_id uuid, p_os_ids uuid[], p_venda_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os_id uuid;
  v_venda_id uuid;
  v_os record;
  v_venda record;
  v_valor_total numeric(12,2) := 0;
  v_valor_itens_aprovados numeric(12,2);
  v_valor_adicionais_aprovados numeric(12,2);
  v_valor_acrescimos numeric(12,2);
  v_valor_venda numeric(12,2);
  v_cobranca_id uuid;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para gerar cobrança';
  end if;

  if coalesce(array_length(p_os_ids, 1), 0) = 0 and coalesce(array_length(p_venda_ids, 1), 0) = 0 then
    raise exception 'Selecione ao menos uma OS ou venda avulsa para gerar a cobrança';
  end if;

  foreach v_os_id in array coalesce(p_os_ids, array[]::uuid[])
  loop
    select os.id, os.cliente_id, os.tipo, os.status, os.orcamento_id into v_os
      from ordens_servico os where os.id = v_os_id for update;
    if v_os.id is null then
      raise exception 'OS não encontrada';
    end if;
    if v_os.cliente_id <> p_cliente_id then
      raise exception 'OS não pertence ao cliente informado';
    end if;
    if v_os.tipo <> 'externa' or v_os.status <> 'concluida' then
      raise exception 'Somente OS externa e concluída pode gerar cobrança';
    end if;
    if exists (
      select 1 from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.os_id = v_os_id and c.status <> 'cancelada'
    ) then
      raise exception 'Esta OS já está vinculada a uma cobrança ativa';
    end if;

    select coalesce(sum(valor_total), 0) into v_valor_itens_aprovados
      from orcamento_itens
      where orcamento_id = v_os.orcamento_id and status_aprovacao = 'aprovado';

    select coalesce(sum(oai.valor_total), 0) into v_valor_adicionais_aprovados
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      where a.os_id = v_os_id and oai.status_aprovacao = 'aprovado';

    select coalesce(sum(a.valor_acrescimo), 0) into v_valor_acrescimos
      from orcamento_acrescimos a where a.orcamento_id = v_os.orcamento_id;

    v_valor_total := v_valor_total + v_valor_itens_aprovados + v_valor_adicionais_aprovados + v_valor_acrescimos;
  end loop;

  foreach v_venda_id in array coalesce(p_venda_ids, array[]::uuid[])
  loop
    select v.id, v.cliente_id into v_venda from vendas_avulsas v where v.id = v_venda_id for update;
    if v_venda.id is null then
      raise exception 'Venda avulsa não encontrada';
    end if;
    if v_venda.cliente_id <> p_cliente_id then
      raise exception 'Venda avulsa não pertence ao cliente informado';
    end if;
    if exists (
      select 1 from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.venda_avulsa_id = v_venda_id and c.status <> 'cancelada'
    ) then
      raise exception 'Esta venda avulsa já está vinculada a uma cobrança ativa';
    end if;

    select coalesce(sum(quantidade * valor_unitario), 0) into v_valor_venda
      from venda_avulsa_itens where venda_id = v_venda_id;
    v_valor_total := v_valor_total + v_valor_venda;
  end loop;

  insert into cobrancas (cliente_id, valor_total, criado_por)
  values (p_cliente_id, v_valor_total, auth.uid())
  returning id into v_cobranca_id;

  insert into cobranca_origens (cobranca_id, os_id)
    select v_cobranca_id, unnest(p_os_ids) where p_os_ids is not null;
  insert into cobranca_origens (cobranca_id, venda_avulsa_id)
    select v_cobranca_id, unnest(p_venda_ids) where p_venda_ids is not null;

  return v_cobranca_id;
end;
$$;
