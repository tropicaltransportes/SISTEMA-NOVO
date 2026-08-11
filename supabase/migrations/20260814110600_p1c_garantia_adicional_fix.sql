-- ETAPA 6 (P1-C) — item 6 (GAR-007 support): estende os_garantia_itens para
-- aceitar item do orçamento ORIGINAL **ou** item de ADICIONAL aprovado,
-- nunca os dois no mesmo registro (CHECK dedicado). Também CORRIGE uma
-- REGRESSÃO real encontrada nesta rodada: a reescrita de rpc_baixar_peca_os
-- feita no P1-B (20260813100300_p1b_estoque_execucao_adicional.sql), para
-- adicionar o ramo de item ADICIONAL, comparou a assinatura antiga (5
-- parâmetros, do P1-A/GAR-005) e a substituiu — mas o P1-B nunca leu
-- 20260812096000_p1a_gar005_vinculo_garantia.sql, então o ramo de GARANTIA
-- (baseado em os_origem_id) foi silenciosamente perdido nessa reescrita:
-- desde o P1-B, baixar peça em uma OS de garantia falha, porque a função
-- nem sequer volta a selecionar os_origem_id. Esta migration reintroduz o
-- ramo de garantia (agora cobrindo também item de adicional), preservando
-- os dois ramos que o P1-B introduziu (orçamento original e adicional da
-- própria OS).

-- ============================================================
-- os_garantia_itens: aceita item original OU item de adicional aprovado.
-- ============================================================
alter table os_garantia_itens alter column orcamento_item_original_id drop not null;
alter table os_garantia_itens add column if not exists os_adicional_item_original_id uuid references os_adicional_itens(id);

alter table os_garantia_itens drop constraint if exists os_garantia_itens_os_garantia_id_orcamento_item_original_id_key;
alter table os_garantia_itens add constraint os_garantia_itens_um_vinculo_check
  check (num_nonnulls(orcamento_item_original_id, os_adicional_item_original_id) = 1);

create unique index if not exists ux_os_garantia_itens_orcamento on os_garantia_itens (os_garantia_id, orcamento_item_original_id)
  where orcamento_item_original_id is not null;
create unique index if not exists ux_os_garantia_itens_adicional on os_garantia_itens (os_garantia_id, os_adicional_item_original_id)
  where os_adicional_item_original_id is not null;

-- ============================================================
-- rpc_criar_os_garantia: ganha p_itens_adicionais_originais uuid[] — itens
-- de ADICIONAL aprovado da OS original também podem motivar a garantia.
-- Item rejeitado de adicional nunca pode gerar garantia (mesma checagem que
-- já existia para item de orçamento original — só que aqui era implícita
-- via orcamento_itens, que não tem noção de aprovação de adicional).
-- ============================================================
drop function if exists rpc_criar_os_garantia(uuid, uuid[]);

create or replace function rpc_criar_os_garantia(
  p_os_origem_id uuid,
  p_itens_originais uuid[] default null,
  p_itens_adicionais_originais uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig record;
  v_novo_id uuid;
  v_item_id uuid;
  v_qtd_itens_validos int;
  v_qtd_adicionais_validos int;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para abrir OS de garantia';
  end if;

  select * into v_orig from ordens_servico where id = p_os_origem_id for update;
  if v_orig.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_orig.status <> 'liberada' then
    raise exception 'Somente OS liberada pode gerar garantia';
  end if;
  if v_orig.os_origem_id is not null then
    raise exception 'Não é possível abrir garantia a partir de outra OS de garantia';
  end if;
  if v_orig.data_liberacao is null or now() > v_orig.data_liberacao + interval '90 days' then
    raise exception 'Prazo de garantia (90 dias da liberação) expirado';
  end if;

  if v_orig.orcamento_id is not null then
    if (p_itens_originais is null or array_length(p_itens_originais, 1) is null or array_length(p_itens_originais, 1) = 0)
       and (p_itens_adicionais_originais is null or array_length(p_itens_adicionais_originais, 1) is null or array_length(p_itens_adicionais_originais, 1) = 0) then
      raise exception 'Informe ao menos um item (original ou de adicional) da OS original — garantia sem vínculo com item/serviço original não é permitida';
    end if;
  end if;

  if p_itens_originais is not null and array_length(p_itens_originais, 1) > 0 then
    select count(*) into v_qtd_itens_validos
      from orcamento_itens
      where id = any(p_itens_originais) and orcamento_id = v_orig.orcamento_id and status_aprovacao = 'aprovado';
    if v_qtd_itens_validos <> array_length(p_itens_originais, 1) then
      raise exception 'Um ou mais itens informados não pertencem ao orçamento da OS original ou não estão aprovados — item rejeitado não gera garantia';
    end if;
  end if;

  if p_itens_adicionais_originais is not null and array_length(p_itens_adicionais_originais, 1) > 0 then
    select count(*) into v_qtd_adicionais_validos
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      where oai.id = any(p_itens_adicionais_originais) and a.os_id = p_os_origem_id and oai.status_aprovacao = 'aprovado';
    if v_qtd_adicionais_validos <> array_length(p_itens_adicionais_originais, 1) then
      raise exception 'Um ou mais itens de adicional informados não pertencem a esta OS ou não estão aprovados — item rejeitado não gera garantia';
    end if;
  end if;

  insert into ordens_servico (veiculo_id, cliente_id, tipo, checklist_template_id, os_origem_id, criado_por)
  values (v_orig.veiculo_id, v_orig.cliente_id, v_orig.tipo, v_orig.checklist_template_id, p_os_origem_id, auth.uid())
  returning id into v_novo_id;

  if p_itens_originais is not null then
    foreach v_item_id in array p_itens_originais loop
      insert into os_garantia_itens (os_garantia_id, orcamento_item_original_id, motivo, criado_por)
      values (v_novo_id, v_item_id, 'Retorno em garantia (90 dias) do item original da OS ' || p_os_origem_id, auth.uid());
    end loop;
  end if;
  if p_itens_adicionais_originais is not null then
    foreach v_item_id in array p_itens_adicionais_originais loop
      insert into os_garantia_itens (os_garantia_id, os_adicional_item_original_id, motivo, criado_por)
      values (v_novo_id, v_item_id, 'Retorno em garantia (90 dias) do item de adicional da OS ' || p_os_origem_id, auth.uid());
    end loop;
  end if;

  update ordens_servico set status = 'reaberta_garantia' where id = p_os_origem_id;

  return v_novo_id;
end;
$$;

-- ============================================================
-- rpc_baixar_peca_os: reintroduz o ramo de GARANTIA (perdido no P1-B —
-- regressão corrigida aqui), agora cobrindo item original E item de
-- adicional, ao lado dos dois ramos já existentes do P1-B (adicional da
-- própria OS, orçamento original da própria OS). Mesma assinatura de 6
-- parâmetros do P1-B (nenhum chamador quebra).
-- ============================================================
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
  v_gi record;
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
  -- Ramo 1: peça de item ADICIONAL da própria OS (P1-B, ADC-002/K).
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
  -- Ramo 2: peça de item do ORÇAMENTO ORIGINAL da própria OS (P1-A/EST-004,
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

  -- ------------------------------------------------------------
  -- Ramo 3: OS de GARANTIA (os_origem_id preenchido, orcamento_id sempre
  -- NULL nesse caso). Item precisa estar vinculado via os_garantia_itens —
  -- ORIGINAL (orcamento_itens da OS de origem) OU ADICIONAL (os_adicional_itens
  -- da OS de origem). REGRESSÃO CORRIGIDA nesta migration: este ramo
  -- inteiro havia sido perdido na reescrita do P1-B.
  -- ------------------------------------------------------------
  elsif v_os_origem_id is not null then
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
  end if;

  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  -- Ramo de garantia por item ORIGINAL grava no ledger como
  -- orcamento_item_id (mesma coluna do ramo 2, reaproveitada); por item de
  -- ADICIONAL grava como os_adicional_item_id (mesma coluna do ramo 1).
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
