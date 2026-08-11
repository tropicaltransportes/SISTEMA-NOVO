-- ETAPA 5 (P1-B) — item 7/8: bloqueio de execução para item não aprovado
-- (orçamento OU adicional) e baixa de estoque identificando claramente a
-- origem (item original vs item adicional). Estende EST-004 (P1-A) sem
-- reescrever a decisão técnica já tomada (baixa continua ocorrendo na
-- execução, nunca na conversão/aprovação).

-- ============================================================
-- sincronizar_execucao_item_adicional: espelha
-- sincronizar_execucao_item_orcamento (P1-A) para os_adicional_itens —
-- cota própria por (item adicional + OS), a partir do ledger real de
-- estoque_movimentos.
-- ============================================================
create or replace function sincronizar_execucao_item_adicional(p_os_adicional_item_id uuid, p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qtd_aprovada numeric(12,3);
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_liquido numeric(12,3);
  v_status_atual text;
begin
  select quantidade, execucao_status into v_qtd_aprovada, v_status_atual
    from os_adicional_itens where id = p_os_adicional_item_id;
  if v_qtd_aprovada is null then
    return;
  end if;

  if v_status_atual = 'cancelado' then
    return;
  end if;

  select coalesce(sum(quantidade), 0) into v_ja_baixado
    from estoque_movimentos
    where os_adicional_item_id = p_os_adicional_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida';
  select coalesce(sum(em2.quantidade), 0) into v_estornado
    from estoque_movimentos em2
    where em2.tipo = 'estorno_saida'
      and em2.estornado_de in (
        select id from estoque_movimentos
        where os_adicional_item_id = p_os_adicional_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida'
      );
  v_liquido := v_ja_baixado - v_estornado;

  update os_adicional_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_aprovada then 'executado'
      else 'parcial'
    end
    where id = p_os_adicional_item_id;
end;
$$;

revoke execute on function sincronizar_execucao_item_adicional(uuid, uuid) from public, anon, authenticated;

-- ============================================================
-- rpc_baixar_peca_os: ganha o parâmetro p_os_adicional_item_id (mutuamente
-- exclusivo com p_orcamento_item_id) e passa a EXIGIR, em ambos os casos,
-- que o item esteja com status_aprovacao = 'aprovado' — item pendente ou
-- rejeitado nunca baixa peça, independente de origem (item 7 do pedido).
-- ============================================================
drop function if exists rpc_baixar_peca_os(uuid, uuid, numeric, uuid, uuid);

create or replace function rpc_baixar_peca_os(
  p_os_id uuid,
  p_peca_id uuid,
  p_quantidade numeric,
  p_idempotency_key uuid default null,
  p_orcamento_item_id uuid default null,
  p_os_adicional_item_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_orcamento_id uuid;
  v_item record;
  v_adic_item record;
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_disponivel numeric(12,3);
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  if p_orcamento_item_id is not null and p_os_adicional_item_id is not null then
    raise exception 'Informe apenas um vínculo: item de orçamento OU item de adicional, nunca os dois';
  end if;

  select status, orcamento_id into v_status, v_orcamento_id from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  -- ------------------------------------------------------------
  -- Ramo 1: peça de item ADICIONAL (ADC-002/K: item não aprovado nunca baixa)
  -- ------------------------------------------------------------
  if p_os_adicional_item_id is not null then
    select oai.id, oai.peca_id, oai.quantidade, oai.status_aprovacao, a.os_id into v_adic_item
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      where oai.id = p_os_adicional_item_id;
    if v_adic_item.id is null then
      raise exception 'Item de adicional informado não encontrado';
    end if;
    if v_adic_item.os_id <> p_os_id then
      raise exception 'Item de adicional não pertence a esta OS';
    end if;
    if v_adic_item.status_aprovacao <> 'aprovado' then
      raise exception 'Item de adicional não está aprovado (status atual: %) — baixa bloqueada até decisão do cliente', v_adic_item.status_aprovacao;
    end if;
    if v_adic_item.peca_id is null or v_adic_item.peca_id <> p_peca_id then
      raise exception 'Peça informada não corresponde ao item aprovado do adicional';
    end if;

    select coalesce(sum(quantidade), 0) into v_ja_baixado
      from estoque_movimentos
      where os_adicional_item_id = p_os_adicional_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida';
    select coalesce(sum(em2.quantidade), 0) into v_estornado
      from estoque_movimentos em2
      where em2.tipo = 'estorno_saida'
        and em2.estornado_de in (
          select id from estoque_movimentos
          where os_adicional_item_id = p_os_adicional_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida'
        );
    v_disponivel := v_adic_item.quantidade - (v_ja_baixado - v_estornado);

    if p_quantidade > v_disponivel then
      raise exception 'Quantidade solicitada (%) excede o saldo aprovado do item de adicional (aprovado %, já executado %)', p_quantidade, v_adic_item.quantidade, (v_ja_baixado - v_estornado);
    end if;

  -- ------------------------------------------------------------
  -- Ramo 2: peça de item do ORÇAMENTO original (EST-004, agora também
  -- checando status_aprovacao — item rejeitado nunca baixa: item E/APR-002)
  -- ------------------------------------------------------------
  elsif v_orcamento_id is not null then
    if p_orcamento_item_id is null then
      raise exception 'OS originada de orçamento: informe o item do orçamento (p_orcamento_item_id) ou de um adicional (p_os_adicional_item_id) ao baixar peça — baixa avulsa sem vínculo não é permitida nesta OS';
    end if;

    select id, peca_id, quantidade, status_aprovacao into v_item
      from orcamento_itens where id = p_orcamento_item_id and orcamento_id = v_orcamento_id;
    if v_item.id is null then
      raise exception 'Item de orçamento informado não pertence ao orçamento desta OS';
    end if;
    if v_item.status_aprovacao <> 'aprovado' then
      raise exception 'Item de orçamento não está aprovado (status atual: %) — baixa bloqueada', v_item.status_aprovacao;
    end if;
    if v_item.peca_id is null or v_item.peca_id <> p_peca_id then
      raise exception 'Peça informada não corresponde ao item aprovado do orçamento — peça fora do escopo aprovado exige fluxo de Adicional; baixa bloqueada';
    end if;

    select coalesce(sum(quantidade), 0) into v_ja_baixado
      from estoque_movimentos
      where orcamento_item_id = p_orcamento_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida';
    select coalesce(sum(em2.quantidade), 0) into v_estornado
      from estoque_movimentos em2
      where em2.tipo = 'estorno_saida'
        and em2.estornado_de in (
          select id from estoque_movimentos
          where orcamento_item_id = p_orcamento_item_id and origem_tipo = 'os' and origem_id = p_os_id and tipo = 'saida'
        );
    v_disponivel := v_item.quantidade - (v_ja_baixado - v_estornado);

    if p_quantidade > v_disponivel then
      raise exception 'Quantidade solicitada (%) excede o saldo aprovado do item no orçamento (aprovado %, já executado %) — necessário adicional', p_quantidade, v_item.quantidade, (v_ja_baixado - v_estornado);
    end if;
  end if;

  -- Fallback best-effort de dedup por janela de 5s (EST-009, ETAPA 3): só
  -- entra em ação quando o caller NÃO informou idempotency_key.
  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  perform rpc_registrar_saida_estoque_completa(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key, p_orcamento_item_id, p_os_adicional_item_id);

  if p_orcamento_item_id is not null then
    perform sincronizar_execucao_item_orcamento(p_orcamento_item_id, p_os_id);
  elsif p_os_adicional_item_id is not null then
    perform sincronizar_execucao_item_adicional(p_os_adicional_item_id, p_os_id);
  end if;
end;
$$;

-- ============================================================
-- rpc_registrar_saida_estoque_completa: mesma lógica de
-- rpc_registrar_saida_estoque (P1-A), com o parâmetro adicional
-- p_os_adicional_item_id gravado no ledger — sem alterar a assinatura já
-- usada por rpc_criar_venda_avulsa (que continua chamando a versão de 5
-- parâmetros).
-- ============================================================
create or replace function rpc_registrar_saida_estoque_completa(
  p_peca_id uuid,
  p_quantidade numeric,
  p_origem_tipo origem_movimento,
  p_origem_id uuid,
  p_idempotency_key uuid default null,
  p_orcamento_item_id uuid default null,
  p_os_adicional_item_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
begin
  if p_quantidade <= 0 then
    raise exception 'Quantidade de saída deve ser positiva';
  end if;

  select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
    from pecas where id = p_peca_id for update;

  if v_saldo_atual is null then
    raise exception 'Peça % não encontrada', p_peca_id;
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = p_origem_tipo and origem_id = p_origem_id
      and peca_id = p_peca_id and tipo = 'saida' and idempotency_key = p_idempotency_key
  ) then
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end if;

  v_novo_saldo := v_saldo_atual - p_quantidade;
  if v_novo_saldo < 0 then
    raise exception 'Estoque insuficiente para a peça % (saldo disponível %, quantidade solicitada %)', p_peca_id, v_saldo_atual, p_quantidade;
  end if;

  update pecas set saldo_atual = v_novo_saldo where id = p_peca_id;

  begin
    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por, idempotency_key, orcamento_item_id, os_adicional_item_id)
    values
      (p_peca_id, 'saida', p_origem_tipo, p_origem_id, p_quantidade, v_custo_medio, v_novo_saldo, auth.uid(), p_idempotency_key, p_orcamento_item_id, p_os_adicional_item_id);
  exception when unique_violation then
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end;
end;
$$;

revoke execute on function rpc_registrar_saida_estoque_completa(uuid, numeric, origem_movimento, uuid, uuid, uuid, uuid) from public, anon, authenticated;

-- ============================================================
-- estornar_saida_estoque_interno: passa também a re-sincronizar o item de
-- ADICIONAL quando o movimento estornado estava vinculado a um (mesmo
-- motivo do P1-A para orcamento_item_id).
-- ============================================================
create or replace function estornar_saida_estoque_interno(p_movimento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mov record;
  v_saldo numeric(12,3);
  v_novo_saldo numeric(12,3);
begin
  select * into v_mov from estoque_movimentos where id = p_movimento_id and tipo = 'saida' for update;
  if v_mov.id is null then
    raise exception 'Movimento de saída % não encontrado', p_movimento_id;
  end if;

  if exists (select 1 from estoque_movimentos where estornado_de = p_movimento_id) then
    raise exception 'Movimento % já foi estornado anteriormente', p_movimento_id;
  end if;

  select saldo_atual into v_saldo from pecas where id = v_mov.peca_id for update;
  v_novo_saldo := v_saldo + v_mov.quantidade;

  update pecas set saldo_atual = v_novo_saldo where id = v_mov.peca_id;

  insert into estoque_movimentos
    (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por, estornado_de)
  values
    (v_mov.peca_id, 'estorno_saida', v_mov.origem_tipo, v_mov.origem_id, v_mov.quantidade, v_mov.custo_unitario, v_novo_saldo, auth.uid(), p_movimento_id);

  if v_mov.orcamento_item_id is not null and v_mov.origem_tipo = 'os' then
    perform sincronizar_execucao_item_orcamento(v_mov.orcamento_item_id, v_mov.origem_id);
  end if;
  if v_mov.os_adicional_item_id is not null and v_mov.origem_tipo = 'os' then
    perform sincronizar_execucao_item_adicional(v_mov.os_adicional_item_id, v_mov.origem_id);
  end if;
end;
$$;

revoke execute on function estornar_saida_estoque_interno(uuid) from public, anon, authenticated;

-- ============================================================
-- rpc_marcar_item_orcamento_execucao: passa a exigir status_aprovacao =
-- 'aprovado' — item pendente/rejeitado nunca pode ser marcado
-- executado/parcial/cancelado (mão de obra sem peça, mesmo bloqueio do
-- ramo de peça).
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

-- ============================================================
-- rpc_marcar_item_os_adicional_execucao: equivalente para item de mão de
-- obra do adicional (sem peça, sem sinal automático de baixa).
-- ============================================================
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
