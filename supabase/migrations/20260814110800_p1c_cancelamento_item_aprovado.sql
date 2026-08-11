-- ETAPA 6 (P1-C) — item 11: formaliza o cancelamento de item já APROVADO
-- (orçamento original ou adicional) ainda NÃO executado. Antes desta
-- migration, rpc_marcar_item_orcamento_execucao e
-- rpc_marcar_item_os_adicional_execucao (P1-A/P1-B) aceitavam qualquer
-- transição de execucao_status para 'cancelado', SEM checar o estado atual
-- — ou seja, um item já 'executado' podia ser marcado 'cancelado' livremente
-- (só pedindo motivo), o que na prática apagava da cobrança algo que já foi
-- fisicamente consumido/realizado. Esta migration:
--   1. bloqueia cancelar item cujo execucao_status já é 'executado' ou
--      'parcial' (parte já foi de fato executada — não é mais um
--      cancelamento simples, exigiria estorno formal de estoque, fora do
--      escopo desta correção pontual);
--   2. só permite cancelar a partir de 'pendente' (aprovado, mas nada
--      executado ainda) — item pendente de DECISÃO (status_aprovacao) já
--      podia ser rejeitado via rpc_decidir_item_orcamento/os_adicional
--      (isso não muda);
--   3. toda alteração continua auditada (já era);
--   4. rpc_criar_cobranca passa a excluir também item de ORÇAMENTO
--      cancelado (a exclusão de item de ADICIONAL cancelado já foi feita em
--      20260814110200_p1c_desconto_orcamento.sql, quando a mesma função foi
--      redefinida para o rateio de desconto — aqui só falta o lado do
--      orçamento original, para manter os dois simétricos).

-- ============================================================
-- Guarda: item já 'executado'/'parcial' nunca pode virar 'cancelado'.
-- ============================================================
create or replace function rpc_marcar_item_orcamento_execucao(
  p_orcamento_item_id uuid,
  p_status text,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_os_id uuid;
  v_status_anterior text;
begin
  if not tem_perfil('executor', 'encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para marcar execução de item do orçamento';
  end if;

  if p_status not in ('pendente', 'parcial', 'executado', 'cancelado') then
    raise exception 'Status de execução inválido: %', p_status;
  end if;

  if p_status = 'cancelado' and (p_motivo is null or length(trim(p_motivo)) < 5) then
    raise exception 'Cancelar um item aprovado exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select oi.id, oi.orcamento_id, oi.execucao_status, oi.status_aprovacao into v_item
    from orcamento_itens oi where oi.id = p_orcamento_item_id for update;
  if v_item.id is null then
    raise exception 'Item de orçamento não encontrado';
  end if;
  if v_item.status_aprovacao <> 'aprovado' then
    raise exception 'Item de orçamento não está aprovado (status atual: %) — não pode ser marcado como executado/cancelado', v_item.status_aprovacao;
  end if;

  -- item 11 (P1-C): item já executado (total ou parcialmente) nunca pode
  -- ser transformado em cancelado por este caminho — procedimento formal
  -- de estorno de estoque, fora desta correção.
  if p_status = 'cancelado' and v_item.execucao_status in ('executado', 'parcial') then
    raise exception 'Item já executado (%) não pode ser cancelado — cancelamento só é permitido para item aprovado ainda não executado (execucao_status pendente)', v_item.execucao_status;
  end if;

  v_status_anterior := v_item.execucao_status;

  select os.id into v_os_id from ordens_servico os where os.orcamento_id = v_item.orcamento_id and os.status <> 'cancelada' limit 1;
  if v_os_id is not null and exists (
    select 1 from ordens_servico where id = v_os_id and status in ('concluida', 'liberada')
  ) then
    raise exception 'OS já concluída/liberada — use uma correção formal auditada, não a marcação direta de execução';
  end if;

  update orcamento_itens set execucao_status = p_status where id = p_orcamento_item_id;

  perform registrar_auditoria('orcamento_itens', p_orcamento_item_id, 'marcar_execucao_item',
    jsonb_build_object('execucao_status', v_status_anterior), jsonb_build_object('execucao_status', p_status), p_motivo);
end;
$$;

create or replace function rpc_marcar_item_os_adicional_execucao(
  p_item_id uuid,
  p_status text,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_os_id uuid;
  v_os_status status_os;
  v_status_anterior text;
begin
  if not tem_perfil('executor', 'encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para marcar execução de item de adicional';
  end if;

  if p_status not in ('pendente', 'parcial', 'executado', 'cancelado') then
    raise exception 'Status de execução inválido: %', p_status;
  end if;
  if p_status = 'cancelado' and (p_motivo is null or length(trim(p_motivo)) < 5) then
    raise exception 'Cancelar um item aprovado exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select oai.id, a.os_id, oai.execucao_status, oai.status_aprovacao into v_item
    from os_adicional_itens oai join os_adicionais a on a.id = oai.adicional_id
    where oai.id = p_item_id for update;
  if v_item.id is null then
    raise exception 'Item de adicional não encontrado';
  end if;
  if v_item.status_aprovacao <> 'aprovado' then
    raise exception 'Item de adicional não está aprovado (status atual: %) — não pode ser marcado como executado/cancelado', v_item.status_aprovacao;
  end if;

  -- item 11 (P1-C): mesma guarda do lado do orçamento original.
  if p_status = 'cancelado' and v_item.execucao_status in ('executado', 'parcial') then
    raise exception 'Item de adicional já executado (%) não pode ser cancelado — cancelamento só é permitido para item aprovado ainda não executado (execucao_status pendente)', v_item.execucao_status;
  end if;

  v_status_anterior := v_item.execucao_status;

  select status into v_os_status from ordens_servico where id = v_item.os_id;
  if v_os_status in ('concluida', 'liberada') then
    raise exception 'OS já concluída/liberada — use uma correção formal auditada, não a marcação direta de execução';
  end if;

  update os_adicional_itens set execucao_status = p_status where id = p_item_id;

  perform registrar_auditoria('os_adicional_itens', p_item_id, 'marcar_execucao_item_adicional',
    jsonb_build_object('execucao_status', v_status_anterior), jsonb_build_object('execucao_status', p_status), p_motivo);
end;
$$;

-- ============================================================
-- rpc_criar_cobranca: item de ORÇAMENTO original com execucao_status
-- 'cancelado' também sai da cobrança (o lado do adicional já foi corrigido
-- em 20260814110200_p1c_desconto_orcamento.sql). Mantém a soma por
-- valor_liquido (desconto, mesma migration) — só adiciona o filtro que
-- faltava aqui.
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

    select coalesce(sum(valor_liquido), 0) into v_valor_itens_aprovados
      from orcamento_itens
      where orcamento_id = v_os.orcamento_id and status_aprovacao = 'aprovado' and execucao_status <> 'cancelado';

    select coalesce(sum(oai.valor_total), 0) into v_valor_adicionais_aprovados
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      where a.os_id = v_os_id and oai.status_aprovacao = 'aprovado' and oai.execucao_status <> 'cancelado';

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
