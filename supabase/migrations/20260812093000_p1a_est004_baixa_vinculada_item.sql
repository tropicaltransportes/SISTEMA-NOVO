-- ETAPA 4 (P1-A) — item D: EST-004 / E2E-003, baixa de peça em OS originada
-- de orçamento passa a ser obrigatoriamente vinculada ao item aprovado.
--
-- Decisão técnica registrada (ver docs/testing/BUSINESS_RULES.md, BR-014
-- atualizada): a baixa continua ocorrendo na EXECUÇÃO (rpc_baixar_peca_os),
-- não na conversão em OS — alternativa (B) do enunciado, já era o
-- comportamento real do sistema (rpc_criar_os nunca baixou estoque, isso já
-- era assim desde a Fase 2). O que muda agora é a RASTREABILIDADE: quando a
-- OS tem orcamento_id (OS originada de orçamento), toda baixa PRECISA
-- informar a qual orcamento_itens ela pertence, valida peça/quantidade
-- contra o aprovado, e nunca deixa passar peça fora do escopo aprovado.
-- Motivo técnico para preferir execução: baixar na conversão comprometeria
-- estoque físico antes do serviço realmente começar (ex.: orçamento aprovado
-- às 9h, carro só entra pra execução 3 dias depois — estoque ficaria
-- reservado/indisponível para outro atendimento urgente sem necessidade
-- real), e diverge do saldo físico de prateleira, que só muda quando a peça
-- de fato sai do estoque para ser usada.
--
-- Coluna nova: rastreia POR ITEM quanto já foi baixado (soma de
-- estoque_movimentos.quantidade onde orcamento_item_id = X e origem_id = OS
-- específica — escopado por OS, não globalmente, porque o MESMO item de
-- orçamento pode ser referenciado de novo por uma OS de garantia futura,
-- que deve ter sua própria cota, ver item G/GAR-005).
alter table estoque_movimentos add column if not exists orcamento_item_id uuid references orcamento_itens(id);
create index if not exists idx_estoque_mov_orcamento_item on estoque_movimentos (orcamento_item_id);

-- Estado de execução por item de orçamento (usado por CON-002/item E, mas
-- criado aqui porque rpc_baixar_peca_os já precisa escrever nele quando uma
-- baixa vinculada acontece — ver sincronizar_execucao_item_orcamento abaixo):
--   pendente  -> nada baixado ainda (ou item de mão de obra, nunca marcado)
--   parcial   -> baixa parcial (peça) ou marcação manual parcial
--   executado -> quantidade aprovada totalmente baixada, ou marcação manual
--   cancelado -> item aprovado mas dispensado (não será executado), marcado
--                manualmente com motivo — não bloqueia conclusão da OS
alter table orcamento_itens add column if not exists execucao_status text not null default 'pendente'
  constraint orcamento_itens_execucao_status_check check (execucao_status in ('pendente', 'parcial', 'executado', 'cancelado'));

-- ============================================================
-- rpc_registrar_saida_estoque ganha o parâmetro (mesmo padrão de
-- p_idempotency_key na ETAPA 3: DROP explícito da assinatura antiga antes de
-- recriar, para não repetir o bug de overload do PGRST203 corrigido em
-- 20260811170100_etapa3_fix_overload.sql).
-- ============================================================
drop function if exists rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid, uuid);

create or replace function rpc_registrar_saida_estoque(
  p_peca_id uuid,
  p_quantidade numeric,
  p_origem_tipo origem_movimento,
  p_origem_id uuid,
  p_idempotency_key uuid default null,
  p_orcamento_item_id uuid default null
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
    -- EST-004/E2E-003: erro explícito e específico (não genérico, não
    -- silencioso) — identifica a peça, o saldo disponível e o solicitado.
    raise exception 'Estoque insuficiente para a peça % (saldo disponível %, quantidade solicitada %)', p_peca_id, v_saldo_atual, p_quantidade;
  end if;

  update pecas set saldo_atual = v_novo_saldo where id = p_peca_id;

  begin
    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por, idempotency_key, orcamento_item_id)
    values
      (p_peca_id, 'saida', p_origem_tipo, p_origem_id, p_quantidade, v_custo_medio, v_novo_saldo, auth.uid(), p_idempotency_key, p_orcamento_item_id);
  exception when unique_violation then
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end;
end;
$$;

revoke execute on function rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid, uuid, uuid) from public, anon, authenticated;

-- ============================================================
-- rpc_baixar_peca_os: quando a OS tem orcamento_id, p_orcamento_item_id
-- passa a ser obrigatório, precisa pertencer ao orçamento da OS, a peça
-- precisa bater com a do item, e a quantidade acumulada já baixada (para
-- ESTA os_id + item) não pode ultrapassar a quantidade aprovada no item —
-- sem isso, bloqueia com mensagem clara de "necessário adicional" (módulo de
-- Adicionais em si continua fora de escopo desta etapa, só o bloqueio/sinal
-- está implementado, conforme pedido).
-- ============================================================
drop function if exists rpc_baixar_peca_os(uuid, uuid, numeric, uuid);

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
  v_item record;
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_disponivel numeric(12,3);
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  select status, orcamento_id into v_status, v_orcamento_id from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  if v_orcamento_id is not null then
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

  -- Fallback best-effort de dedup por janela de 5s (ver EST-009, ETAPA 3):
  -- só entra em ação quando o caller NÃO informou idempotency_key.
  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key, p_orcamento_item_id);

  -- CON-002 (item E): sincroniza o estado de execução do item de orçamento
  -- sempre que uma baixa vinculada acontece — permite ao rpc_concluir_os
  -- saber quais itens aprovados já foram atendidos.
  if p_orcamento_item_id is not null then
    perform sincronizar_execucao_item_orcamento(p_orcamento_item_id, p_os_id);
  end if;
end;
$$;

-- ============================================================
-- Recalcula orcamento_itens.execucao_status a partir do ledger real de
-- estoque_movimentos (nunca a partir de um contador solto) — chamada
-- internamente por rpc_baixar_peca_os (acima) e por rpc_estornar_saida_estoque
-- (ETAPA 4, veja o CREATE OR REPLACE de estornar_saida_estoque_interno no
-- item F/H desta rodada). Sem checagem de perfil própria — função interna.
-- ============================================================
create or replace function sincronizar_execucao_item_orcamento(p_orcamento_item_id uuid, p_os_id uuid)
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
    from orcamento_itens where id = p_orcamento_item_id;
  if v_qtd_aprovada is null then
    return; -- item não encontrado, nada a fazer
  end if;

  -- Item marcado manualmente como cancelado não é reaberto automaticamente
  -- por uma baixa (fluxo manual explícito prevalece sobre o automático).
  if v_status_atual = 'cancelado' then
    return;
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
  v_liquido := v_ja_baixado - v_estornado;

  update orcamento_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_aprovada then 'executado'
      else 'parcial'
    end
    where id = p_orcamento_item_id;
end;
$$;

revoke execute on function sincronizar_execucao_item_orcamento(uuid, uuid) from public, anon, authenticated;

-- ============================================================
-- estornar_saida_estoque_interno (origem: 20260810160000_p0_correcoes_criticas.sql)
-- ganha a re-sincronização do execucao_status do item quando o movimento
-- estornado estava vinculado a um item de orçamento — sem isso, cancelar/
-- estornar uma baixa deixaria o item "executado" mesmo sem a peça de fato
-- ter ficado no estoque (inconsistência entre CON-002 e o ledger real).
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
end;
$$;

revoke execute on function estornar_saida_estoque_interno(uuid) from public, anon, authenticated;
