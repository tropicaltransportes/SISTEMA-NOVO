-- ETAPA 4 (P1-A) — corrige bug real introduzido por
-- 20260812096000_p1a_gar005_vinculo_garantia.sql, descoberto por execução
-- real da suíte de regressão pgTAP imediatamente após aplicar (mesma
-- disciplina do bug de overload corrigido em
-- 20260811170100_etapa3_fix_overload.sql — nunca reescreve a migration já
-- aplicada, corrige com uma nova).
--
-- Causa: `v_item` é `record`, nunca populado por nenhum SELECT INTO quando a
-- OS não tem orcamento_id nem os_origem_id (OS interna "livre", sem
-- orçamento — o caso mais comum de todos, coberto pelos testes pgTAP
-- 020_estoque.sql). Nesse caminho, o código chegava em
-- `if v_item.id is not null then` sem NUNCA ter atribuído v_item, e o
-- Postgres levanta erro ("record ... is not assigned yet") ao tentar ler
-- QUALQUER campo de um record não atribuído — diferente de um record
-- atribuído com campos NULL. `record` não serve para "pode ou não ter sido
-- preenchido"; a correção troca por uma variável boolean explícita
-- (v_tem_vinculo), sempre com valor conhecido.
--
-- Evidência do bug: docs/testing/_etapa4_regressao_bug_v_item_output.txt —
-- supabase/tests/020_estoque.sql (EST-002/007/008/009, que usam OS interna
-- sem orçamento) foi de 6/6 "ok" para 5 "not ok" + 1 "ok" logo depois da
-- migration 096000, antes desta correção.
drop function if exists rpc_baixar_peca_os(uuid, uuid, numeric, uuid, uuid);

create or replace function rpc_baixar_peca_os(
  p_os_id uuid,
  p_peca_id uuid,
  p_quantidade numeric,
  p_idempotency_key uuid default null,
  p_orcamento_item_id uuid default null
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
  v_tem_vinculo boolean := false;
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_disponivel numeric(12,3);
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  select status, orcamento_id, os_origem_id into v_status, v_orcamento_id, v_os_origem_id
    from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  if v_orcamento_id is not null then
    -- OS originada de orçamento (item D/EST-004).
    if p_orcamento_item_id is null then
      raise exception 'OS originada de orçamento: informe o item do orçamento (p_orcamento_item_id) ao baixar peça — baixa avulsa sem vínculo com o item aprovado não é permitida nesta OS';
    end if;

    select id, peca_id, quantidade into v_item
      from orcamento_itens where id = p_orcamento_item_id and orcamento_id = v_orcamento_id;
    if v_item.id is null then
      raise exception 'Item de orçamento informado não pertence ao orçamento desta OS';
    end if;
    if v_item.peca_id is null or v_item.peca_id <> p_peca_id then
      raise exception 'Peça informada não corresponde ao item aprovado do orçamento — peça fora do escopo aprovado exige fluxo de Adicional (não disponível nesta etapa); baixa bloqueada';
    end if;
    v_tem_vinculo := true;

  elsif v_os_origem_id is not null then
    -- OS de garantia (item G/GAR-005): item precisa estar vinculado via
    -- os_garantia_itens, referenciando o item da OS ORIGINAL.
    if p_orcamento_item_id is null then
      raise exception 'OS de garantia: informe o item original coberto pela garantia (p_orcamento_item_id) ao baixar peça — lançar serviço/peça sem relação com o item original não é permitido';
    end if;

    select oi.id, oi.peca_id, oi.quantidade into v_item
      from os_garantia_itens gi
      join orcamento_itens oi on oi.id = gi.orcamento_item_original_id
      where gi.os_garantia_id = p_os_id and oi.id = p_orcamento_item_id;
    if v_item.id is null then
      raise exception 'Item informado não está vinculado a esta OS de garantia — peça/serviço sem relação com o item original da OS que motivou o retorno não é permitida';
    end if;
    if v_item.peca_id is null or v_item.peca_id <> p_peca_id then
      raise exception 'Peça informada não corresponde ao item original coberto pela garantia';
    end if;
    v_tem_vinculo := true;
  end if;

  if v_tem_vinculo then
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
      raise exception 'Quantidade solicitada (%) excede o saldo aprovado do item (aprovado %, já executado nesta OS %) — necessário adicional', p_quantidade, v_item.quantidade, (v_ja_baixado - v_estornado);
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

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key, p_orcamento_item_id);

  if v_orcamento_id is not null and p_orcamento_item_id is not null then
    perform sincronizar_execucao_item_orcamento(p_orcamento_item_id, p_os_id);
  end if;
end;
$$;
