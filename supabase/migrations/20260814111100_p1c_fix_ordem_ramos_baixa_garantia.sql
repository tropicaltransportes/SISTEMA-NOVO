-- ETAPA 6 (P1-C) — correção de bug real encontrado durante a execução do
-- E2E externo com desconto (item 17): a versão de rpc_baixar_peca_os criada
-- em 20260814110600_p1c_garantia_adicional_fix.sql checava
-- `if p_os_adicional_item_id is not null` (Ramo 1 — adicional da PRÓPRIA
-- OS) ANTES de checar `v_os_origem_id is not null` (Ramo 3 — OS de
-- garantia). Como a garantia de item de ADICIONAL também usa o parâmetro
-- `p_os_adicional_item_id` (o id do item de adicional da OS ORIGINAL), a
-- chamada caía sempre no Ramo 1, que exige `a.os_id = p_os_id` — e falhava
-- com "Item de adicional não pertence a esta OS", porque o item realmente
-- pertence à OS ORIGINAL, não à OS de garantia. Confirmado por execução
-- real (docs/testing/scripts/etapa6_e2e_externo_desconto.sh).
--
-- Correção: reordena os ramos — quando a OS é de GARANTIA
-- (`os_origem_id is not null`), esse ramo é resolvido primeiro,
-- independente de qual parâmetro (p_orcamento_item_id ou
-- p_os_adicional_item_id) foi informado. Os ramos 1 e 2 (adicional/
-- orçamento da PRÓPRIA OS) só entram em jogo quando a OS não é de
-- garantia — o que já era estruturalmente verdade antes (uma OS de
-- garantia nunca tem orcamento_id, e agora também nunca cai no ramo de
-- adicional próprio por engano).
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

  select status, orcamento_id, os_origem_id into v_status, v_orcamento_id, v_os_origem_id
    from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  -- ------------------------------------------------------------
  -- Ramo A: OS de GARANTIA (checado PRIMEIRO — ver comentário acima).
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
  -- Ramo B: peça de item ADICIONAL da própria OS (P1-B, ADC-002/K).
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
  -- Ramo C: peça de item do ORÇAMENTO ORIGINAL da própria OS (P1-A/EST-004,
  -- P1-B filtra status_aprovacao).
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
