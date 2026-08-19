-- FEATURE-OS-CANCELAMENTO-01 (parte 3/3).
--
-- (a) OS-CONC-001: rpc_baixar_peca_os lia status/orcamento_id/os_origem_id
-- SEM lock (única RPC operacional relevante sem for update — rpc_concluir_os,
-- rpc_liberar_os, rpc_registrar_foto_os e rpc_criar_os_adicional já têm).
-- Sem isso, uma baixa de peça concorrente com rpc_cancelar_os (que agora
-- pode cancelar em em_diagnostico/em_execucao, exatamente onde baixa é o
-- caso normal) poderia gravar uma saída de estoque depois do lock de
-- cancelamento já ter sido liberado, sem ser incluída no estorno. Corpo
-- integralmente reproduzido de
-- 20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql — ÚNICA MUDANÇA:
-- "for update" na leitura de status/orcamento_id/os_origem_id.
--
-- (b) Bug pré-existente encontrado ao desenhar a reversão de garantia no
-- cancelamento (achado, não introduzido por esta feature): o estorno de
-- uma baixa de OS de GARANTIA sincroniza execucao_status do item
-- ORIGINAL (de outra OS/orçamento) usando o ledger da garantia —
-- rpc_baixar_peca_os já tinha essa consciência (pula o sync no ramo de
-- garantia, com comentário explicando por quê: "itens de OS de garantia
-- não têm execucao_status próprio a sincronizar"), mas o estorno nunca
-- ganhou a mesma guarda. Isso já é alcançável hoje (uma OS de garantia
-- pode chegar a em_diagnostico, baixar peça, e ser cancelada pela
-- rpc_transicionar_os atual); este plano amplia a superfície ao permitir
-- cancelar também em_execucao/aguardando_teste/concluida, exatamente onde
-- baixa de garantia é mais provável — por isso corrigido junto.

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
  v_os_origem_id uuid;
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

  -- ÚNICA MUDANÇA DESTA MIGRATION: "for update" (serializa contra o lock
  -- que rpc_cancelar_os já toma no início da própria transação).
  select status, orcamento_id, os_origem_id into v_status, v_orcamento_id, v_os_origem_id
    from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  -- ------------------------------------------------------------
  -- Ramo A: OS de GARANTIA (checado PRIMEIRO — ver comentário do arquivo
  -- fonte original, 20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql).
  -- ------------------------------------------------------------
  if v_os_origem_id is not null then
    if p_orcamento_item_id is null and p_os_adicional_item_id is null then
      raise exception 'OS de garantia: informe o item original (p_orcamento_item_id) ou o item de adicional (p_os_adicional_item_id) coberto pela garantia — lançar peça/serviço sem relação com o item original não é permitido';
    end if;

    if p_orcamento_item_id is not null then
      select oi.id, oi.peca_id, oi.quantidade into v_item
        from os_garantia_itens gi
        join orcamento_itens oi on oi.id = gi.orcamento_item_original_id
        where gi.os_garantia_id = p_os_id and oi.id = p_orcamento_item_id;
      if v_item.id is null then
        raise exception 'Item informado não está vinculado a esta OS de garantia — peça/serviço sem relação com o item original não é permitida';
      end if;
      if v_item.peca_id is null or v_item.peca_id <> p_peca_id then
        raise exception 'Peça informada não corresponde ao item original coberto pela garantia';
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
        raise exception 'Quantidade solicitada (%) excede o saldo coberto pela garantia (aprovado %, já executado nesta OS %)', p_quantidade, v_item.quantidade, (v_ja_baixado - v_estornado);
      end if;

    else
      select oai.id, oai.peca_id, oai.quantidade into v_adic_item
        from os_garantia_itens gi
        join os_adicional_itens oai on oai.id = gi.os_adicional_item_original_id
        where gi.os_garantia_id = p_os_id and oai.id = p_os_adicional_item_id;
      if v_adic_item.id is null then
        raise exception 'Item de adicional informado não está vinculado a esta OS de garantia — peça/serviço sem relação com o item original não é permitida';
      end if;
      if v_adic_item.peca_id is null or v_adic_item.peca_id <> p_peca_id then
        raise exception 'Peça informada não corresponde ao item de adicional coberto pela garantia';
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
        raise exception 'Quantidade solicitada (%) excede o saldo coberto pela garantia (aprovado %, já executado nesta OS %)', p_quantidade, v_adic_item.quantidade, (v_ja_baixado - v_estornado);
      end if;
    end if;

  -- ------------------------------------------------------------
  -- Ramo B: peça de item ADICIONAL da própria OS.
  -- ------------------------------------------------------------
  elsif p_os_adicional_item_id is not null then
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
  -- Ramo C: peça de item do ORÇAMENTO ORIGINAL da própria OS.
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

  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  if v_os_origem_id is not null and p_os_adicional_item_id is not null then
    perform rpc_registrar_saida_estoque_completa(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key, null, p_os_adicional_item_id);
  else
    perform rpc_registrar_saida_estoque_completa(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key, p_orcamento_item_id, p_os_adicional_item_id);
  end if;

  -- Sincronização de execucao_status só se aplica aos itens da PRÓPRIA OS
  -- (orçamento/adicional) — itens de OS de garantia não têm execucao_status
  -- próprio a sincronizar (o vínculo é com o item ORIGINAL de outra OS).
  if v_os_origem_id is null then
    if p_orcamento_item_id is not null then
      perform sincronizar_execucao_item_orcamento(p_orcamento_item_id, p_os_id);
    elsif p_os_adicional_item_id is not null then
      perform sincronizar_execucao_item_adicional(p_os_adicional_item_id, p_os_id);
    end if;
  end if;
end;
$$;

-- ============================================================
-- Correção do bug pré-existente (b): estorno de baixa de OS de garantia
-- não deve sincronizar o item ORIGINAL usando o ledger da garantia.
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
  v_origem_e_garantia boolean;
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

  -- Movimento de OS de garantia referencia orcamento_item_id/os_adicional_item_id
  -- do item ORIGINAL (de outra OS) só para rastreabilidade — nunca deve
  -- resincronizar o execucao_status desse item com o ledger da garantia.
  if v_mov.origem_tipo = 'os' then
    select exists (select 1 from ordens_servico where id = v_mov.origem_id and os_origem_id is not null)
      into v_origem_e_garantia;
  else
    v_origem_e_garantia := false;
  end if;

  if v_mov.orcamento_item_id is not null and v_mov.origem_tipo = 'os' and not v_origem_e_garantia then
    perform sincronizar_execucao_item_orcamento(v_mov.orcamento_item_id, v_mov.origem_id);
  end if;
  if v_mov.os_adicional_item_id is not null and v_mov.origem_tipo = 'os' and not v_origem_e_garantia then
    perform sincronizar_execucao_item_adicional(v_mov.os_adicional_item_id, v_mov.origem_id);
  end if;
end;
$$;
