-- ETAPA OS-ESCOPO-04 — DEV/QA APENAS. Formaliza: ORÇAMENTO APROVADO =
-- autorização comercial máxima; ORDEM DE SERVIÇO = registro do que
-- efetivamente foi realizado. "Aprovado" deixa de significar
-- "obrigatoriamente executado/utilizado" — rpc_concluir_os não bloqueia
-- mais conclusão só porque sobrou peça aprovada não usada ou serviço
-- aprovado não executado (BR-021 sai de PROVISÓRIA para DEFINIDA com essa
-- semântica). Em paralelo, encarregado/administrador_tecnico ganham edição
-- livre do escopo operacional da OS (quantidade, peça, descrição, remoção),
-- sem tocar no orçamento aprovado (que continua imutável).
--
-- DECISÃO DE ARQUITETURA (auditoria prévia, ver plano da etapa): a OS não
-- tem tabela própria de itens hoje — lê/escreve direto em
-- orcamento_itens.execucao_status (e o equivalente em os_adicional_itens).
-- Isso é incompatível com o pedido por dois motivos concretos: (1)
-- orcamento_itens é o registro histórico do orçamento, não pode ser
-- reescrito por uma edição operacional da OS (BR-007); (2) essa coluna é
-- POR ITEM, não por OS — numa reconversão (BR-008: orçamento gera nova OS
-- depois que a anterior foi cancelada), o estado de execução de uma OS
-- vazaria pra outra. `os_escopo_itens` é criada com uma linha por (OS,
-- item de origem) — nunca compartilhada entre incarnações de OS — e
-- reaproveita literalmente o vocabulário já usado hoje
-- ('pendente'/'parcial'/'executado'/'cancelado'), sem enum novo.

-- ============================================================
-- 1. Tabela nova: escopo operacional da OS.
-- ============================================================
create table if not exists os_escopo_itens (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  origem_tipo text not null check (origem_tipo in ('orcamento', 'adicional')),
  orcamento_item_id uuid references orcamento_itens(id),
  os_adicional_item_id uuid references os_adicional_itens(id),
  check (num_nonnulls(orcamento_item_id, os_adicional_item_id) = 1),
  peca_id_override uuid references pecas(id),
  descricao_override text,
  quantidade_escopo numeric(12,3) not null check (quantidade_escopo > 0),
  valor_unitario_override numeric(12,2) check (valor_unitario_override >= 0),
  execucao_status text not null default 'pendente'
    constraint os_escopo_itens_execucao_status_check check (execucao_status in ('pendente', 'parcial', 'executado', 'cancelado')),
  removido_em timestamptz,
  removido_por uuid references profiles(id),
  motivo_remocao text,
  editado_em timestamptz,
  editado_por uuid references profiles(id),
  criado_em timestamptz not null default now()
);

create index if not exists idx_os_escopo_itens_os on os_escopo_itens (os_id);
create unique index if not exists ux_os_escopo_itens_orcamento_item on os_escopo_itens (os_id, orcamento_item_id) where orcamento_item_id is not null;
create unique index if not exists ux_os_escopo_itens_adicional_item on os_escopo_itens (os_id, os_adicional_item_id) where os_adicional_item_id is not null;

alter table os_escopo_itens enable row level security;

drop policy if exists "os_escopo_itens_select_autenticado" on os_escopo_itens;
create policy "os_escopo_itens_select_autenticado" on os_escopo_itens
  for select using (current_user_ativo());

-- Escrita exclusivamente via RPC (SECURITY DEFINER) — mesmo padrão de
-- orcamento_itens/os_adicional_itens.
revoke insert, update, delete on os_escopo_itens from authenticated;

comment on table os_escopo_itens is
  'Escopo operacional da OS (ETAPA OS-ESCOPO-04) — uma linha por (OS, item de origem aprovado). Fonte de verdade para conclusão/cobrança/documento final a partir desta etapa. orcamento_itens/os_adicional_itens continuam imutáveis como registro histórico do aprovado.';

-- ============================================================
-- 2. Backfill: OS já existentes (DEV/QA) ganham escopo retroativo a partir
-- do estado atual — sem isso, baixa de peça em OS já em andamento quebraria
-- (rpc_baixar_peca_os passa a validar contra quantidade_escopo).
-- ============================================================
insert into os_escopo_itens (os_id, origem_tipo, orcamento_item_id, quantidade_escopo, execucao_status)
select os.id, 'orcamento', oi.id, oi.quantidade, oi.execucao_status
from ordens_servico os
join orcamento_itens oi on oi.orcamento_id = os.orcamento_id
where oi.status_aprovacao = 'aprovado'
on conflict do nothing;

insert into os_escopo_itens (os_id, origem_tipo, os_adicional_item_id, quantidade_escopo, execucao_status)
select a.os_id, 'adicional', oai.id, oai.quantidade, oai.execucao_status
from os_adicionais a
join os_adicional_itens oai on oai.adicional_id = a.id
where oai.status_aprovacao = 'aprovado'
on conflict do nothing;

-- ============================================================
-- 3. rpc_criar_os — ganha a criação do escopo inicial a partir dos itens já
-- aprovados do orçamento (corpo idêntico ao de
-- 20260818170300_p2d_os_reconversao_apos_exclusao.sql, só acrescenta o
-- insert em os_escopo_itens no fim).
-- ============================================================
create or replace function rpc_criar_os(
  p_veiculo_id uuid,
  p_tipo tipo_os,
  p_orcamento_id uuid default null,
  p_solicitacao_id uuid default null,
  p_checklist_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_veiculo record;
  v_cliente_tipo tipo_cliente;
  v_orc record;
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para criar ordem de serviço';
  end if;

  select v.id, v.cliente_id into v_veiculo from veiculos v where v.id = p_veiculo_id and v.deleted_at is null;
  if v_veiculo.id is null then
    raise exception 'Veículo não encontrado';
  end if;

  select tipo into v_cliente_tipo from clientes where id = v_veiculo.cliente_id;
  if p_tipo = 'interna' and v_cliente_tipo <> 'interno' then
    raise exception 'OS interna exige veículo da frota própria (cliente interno)';
  end if;
  if p_tipo = 'externa' and v_cliente_tipo <> 'externo' then
    raise exception 'OS externa exige veículo de cliente externo';
  end if;

  if p_tipo = 'externa' then
    if p_orcamento_id is null then
      raise exception 'OS externa exige orçamento aprovado';
    end if;
  end if;

  if p_orcamento_id is not null then
    select * into v_orc from orcamentos where id = p_orcamento_id for update;
    if v_orc.id is null then
      raise exception 'Orçamento não encontrado';
    end if;
    if v_orc.status <> 'aprovado' then
      raise exception 'Orçamento precisa estar aprovado para gerar OS';
    end if;
    if v_orc.veiculo_id <> p_veiculo_id then
      raise exception 'Orçamento não pertence ao veículo informado';
    end if;
    if exists (
      select 1 from ordens_servico os
      where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada' and os.deleted_at is null
    ) then
      raise exception 'Este orçamento já foi convertido em uma OS ativa';
    end if;
  end if;

  insert into ordens_servico (orcamento_id, veiculo_id, cliente_id, tipo, checklist_template_id, criado_por)
  values (p_orcamento_id, p_veiculo_id, v_veiculo.cliente_id, p_tipo, p_checklist_template_id, auth.uid())
  returning id into v_novo_id;

  if p_solicitacao_id is not null then
    perform marcar_solicitacao_convertida(p_solicitacao_id, 'convertida_os');
  end if;

  -- OS-ESCOPO-04: snapshot do escopo operacional a partir dos itens já
  -- aprovados do orçamento (uma linha por item, teto = quantidade aprovada).
  if p_orcamento_id is not null then
    insert into os_escopo_itens (os_id, origem_tipo, orcamento_item_id, quantidade_escopo)
    select v_novo_id, 'orcamento', oi.id, oi.quantidade
    from orcamento_itens oi
    where oi.orcamento_id = p_orcamento_id and oi.status_aprovacao = 'aprovado'
    on conflict do nothing;
  end if;

  return v_novo_id;
end;
$$;

-- ============================================================
-- 4. rpc_decidir_item_os_adicional — ganha a criação da linha de escopo
-- quando o item é aprovado (corpo idêntico ao de
-- 20260813100200_p1b_adc_tabelas.sql, só acrescenta o insert no ramo
-- 'aprovado').
-- ============================================================
create or replace function rpc_decidir_item_os_adicional(
  p_item_id uuid,
  p_decisao text,
  p_meio_aprovacao text,
  p_autorizado_por_nome text,
  p_comprovante_path text default null,
  p_observacao text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_adicional_id uuid;
  v_status_aprovacao text;
  v_quantidade numeric(12,3);
  v_os_id uuid;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar decisão de item de adicional';
  end if;

  if p_decisao not in ('aprovado', 'rejeitado') then
    raise exception 'Decisão inválida: % (use aprovado ou rejeitado)', p_decisao;
  end if;
  if p_meio_aprovacao not in ('sistema', 'email', 'verbal_documentado') then
    raise exception 'Meio de aprovação inválido: % (use sistema, email ou verbal_documentado)', p_meio_aprovacao;
  end if;
  if p_autorizado_por_nome is null or length(trim(p_autorizado_por_nome)) < 2 then
    raise exception 'Nome de quem autorizou (cliente/responsável) é obrigatório';
  end if;
  if p_meio_aprovacao = 'email' then
    if p_comprovante_path is null or trim(p_comprovante_path) = '' then
      raise exception 'Aprovação via e-mail exige evidência (comprovante_path) — DOC-005';
    end if;
    if not storage_objeto_existe('comprovantes', p_comprovante_path) then
      raise exception 'Comprovante informado não foi encontrado no Storage (bucket comprovantes, path %) — envie o arquivo antes de registrar a decisão', p_comprovante_path;
    end if;
  end if;
  if p_meio_aprovacao = 'verbal_documentado' and (p_observacao is null or length(trim(p_observacao)) < 10) then
    raise exception 'Aprovação verbal documentada exige observação com detalhe suficiente para rastreabilidade (mínimo de 10 caracteres)';
  end if;

  select oai.id, oai.adicional_id, oai.status_aprovacao, oai.quantidade, a.os_id
    into v_item_id, v_adicional_id, v_status_aprovacao, v_quantidade, v_os_id
    from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    where oai.id = p_item_id for update;
  if v_item_id is null then
    raise exception 'Item de adicional não encontrado';
  end if;

  if v_status_aprovacao = p_decisao then
    return; -- ADC-008/cenário M: retry idempotente
  end if;

  if v_status_aprovacao <> 'pendente' then
    raise exception 'Item de adicional já decidido anteriormente (%) — decisão não pode ser revertida/trocada', v_status_aprovacao;
  end if;

  update os_adicional_itens
    set status_aprovacao = p_decisao,
        meio_aprovacao = p_meio_aprovacao,
        autorizado_por_nome = p_autorizado_por_nome,
        autorizado_em = now(),
        registrado_por = auth.uid(),
        comprovante_path = p_comprovante_path,
        observacao = p_observacao
    where id = p_item_id;

  perform registrar_auditoria('os_adicional_itens', p_item_id, 'decisao_item_adicional',
    jsonb_build_object('status_aprovacao', 'pendente'),
    jsonb_build_object('status_aprovacao', p_decisao, 'meio_aprovacao', p_meio_aprovacao, 'autorizado_por_nome', p_autorizado_por_nome),
    p_observacao);

  perform recalcular_status_os_adicional(v_adicional_id);

  -- OS-ESCOPO-04: item aprovado ganha linha de escopo operacional na OS dona
  -- do adicional (teto = quantidade precificada/aprovada do item).
  if p_decisao = 'aprovado' then
    insert into os_escopo_itens (os_id, origem_tipo, os_adicional_item_id, quantidade_escopo)
    values (v_os_id, 'adicional', p_item_id, v_quantidade)
    on conflict do nothing;
  end if;
end;
$$;

-- ============================================================
-- 5. sincronizar_execucao_item_orcamento — o teto de execução passa a ser
-- os_escopo_itens.quantidade_escopo (pode ter sido reduzido via
-- rpc_editar_item_escopo_os), não mais orcamento_itens.quantidade bruta.
-- Escreve em os_escopo_itens (fonte de verdade nova, por-OS) e continua
-- espelhando em orcamento_itens.execucao_status (compat — leitores antigos
-- como rpc_relatorio_encerramento_os/garantia continuam funcionando, ainda
-- que esse espelho use o teto bruto histórico, não o escopo reduzido).
-- ============================================================
create or replace function sincronizar_execucao_item_orcamento(p_orcamento_item_id uuid, p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qtd_aprovada numeric(12,3);
  v_qtd_teto numeric(12,3);
  v_status_escopo_atual text;
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_liquido numeric(12,3);
begin
  select quantidade into v_qtd_aprovada from orcamento_itens where id = p_orcamento_item_id;
  if v_qtd_aprovada is null then
    return;
  end if;

  select quantidade_escopo, execucao_status into v_qtd_teto, v_status_escopo_atual
    from os_escopo_itens where os_id = p_os_id and orcamento_item_id = p_orcamento_item_id;
  if v_qtd_teto is null then
    v_qtd_teto := v_qtd_aprovada; -- fallback defensivo (não deveria acontecer pós-backfill)
  end if;

  if v_status_escopo_atual = 'cancelado' then
    return; -- item removido do escopo desta OS não é reaberto automaticamente por uma baixa
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

  update os_escopo_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_teto then 'executado'
      else 'parcial'
    end
    where os_id = p_os_id and orcamento_item_id = p_orcamento_item_id;

  update orcamento_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_aprovada then 'executado'
      else 'parcial'
    end
    where id = p_orcamento_item_id and execucao_status <> 'cancelado';
end;
$$;

-- ============================================================
-- 6. sincronizar_execucao_item_adicional — mesmo tratamento, espelho de
-- os_adicional_itens.
-- ============================================================
create or replace function sincronizar_execucao_item_adicional(p_os_adicional_item_id uuid, p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_qtd_aprovada numeric(12,3);
  v_qtd_teto numeric(12,3);
  v_status_escopo_atual text;
  v_ja_baixado numeric(12,3);
  v_estornado numeric(12,3);
  v_liquido numeric(12,3);
begin
  select quantidade into v_qtd_aprovada from os_adicional_itens where id = p_os_adicional_item_id;
  if v_qtd_aprovada is null then
    return;
  end if;

  select quantidade_escopo, execucao_status into v_qtd_teto, v_status_escopo_atual
    from os_escopo_itens where os_id = p_os_id and os_adicional_item_id = p_os_adicional_item_id;
  if v_qtd_teto is null then
    v_qtd_teto := v_qtd_aprovada;
  end if;

  if v_status_escopo_atual = 'cancelado' then
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

  update os_escopo_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_teto then 'executado'
      else 'parcial'
    end
    where os_id = p_os_id and os_adicional_item_id = p_os_adicional_item_id;

  update os_adicional_itens
    set execucao_status = case
      when v_liquido <= 0 then 'pendente'
      when v_liquido >= v_qtd_aprovada then 'executado'
      else 'parcial'
    end
    where id = p_os_adicional_item_id and execucao_status <> 'cancelado';
end;
$$;

-- ============================================================
-- 7. rpc_baixar_peca_os — mesma assinatura de
-- 20260818170200_p2d_os_concorrencia_e_correcoes.sql; só troca o teto usado
-- nos ramos B (adicional) e C (orçamento original) de
-- v_adic_item.quantidade/v_item.quantidade (aprovado bruto) para
-- os_escopo_itens.quantidade_escopo (escopo, pode ter sido reduzido). O
-- ramo A (garantia) não usa os_escopo_itens — continua com
-- os_garantia_itens.quantidade, conceito à parte, sem mudança.
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
  v_qtd_teto numeric(12,3);
  v_escopo_status text;
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
    from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  -- ------------------------------------------------------------
  -- Ramo A: OS de GARANTIA (checado PRIMEIRO — sem mudança nesta etapa).
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

    select coalesce(quantidade_escopo, v_adic_item.quantidade) into v_qtd_teto
      from os_escopo_itens where os_id = p_os_id and os_adicional_item_id = p_os_adicional_item_id;
    v_qtd_teto := coalesce(v_qtd_teto, v_adic_item.quantidade);

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
    v_disponivel := v_qtd_teto - (v_ja_baixado - v_estornado);

    if p_quantidade > v_disponivel then
      raise exception 'Quantidade solicitada (%) excede o saldo disponível do item de adicional no escopo desta OS (escopo %, já executado %)', p_quantidade, v_qtd_teto, (v_ja_baixado - v_estornado);
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

    select os.quantidade_escopo, os.execucao_status into v_qtd_teto, v_escopo_status
      from os_escopo_itens os where os.os_id = p_os_id and os.orcamento_item_id = p_orcamento_item_id;
    if v_qtd_teto is null then
      v_qtd_teto := v_item.quantidade;
    end if;
    if v_escopo_status = 'cancelado' then
      raise exception 'Este item foi removido do escopo desta OS — não é possível registrar utilização (peça fora do escopo operacional)';
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
    v_disponivel := v_qtd_teto - (v_ja_baixado - v_estornado);

    if p_quantidade > v_disponivel then
      raise exception 'Quantidade solicitada (%) excede o saldo disponível do item no escopo desta OS (escopo %, já executado %) — necessário adicional para ir além do aprovado', p_quantidade, v_qtd_teto, (v_ja_baixado - v_estornado);
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
-- 8. rpc_editar_item_escopo_os — encarregado/administrador_tecnico editam
-- quantidade/descrição/peça/valor de um item do escopo, só enquanto ele
-- ainda não teve efeito material (execucao_status = 'pendente'). Aumentar
-- quantidade ou valor acima do aprovado na origem é sempre bloqueado — isso
-- passa pelo fluxo de Adicional já existente, nunca por aqui.
-- ============================================================
create or replace function rpc_editar_item_escopo_os(
  p_escopo_item_id uuid,
  p_quantidade numeric default null,
  p_descricao text default null,
  p_peca_id uuid default null,
  p_valor_unitario numeric default null,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_escopo record;
  v_qtd_origem numeric(12,3);
  v_valor_origem numeric(12,2);
  v_antes jsonb;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para editar item do escopo da OS';
  end if;

  select * into v_escopo from os_escopo_itens where id = p_escopo_item_id for update;
  if v_escopo.id is null then
    raise exception 'Item de escopo não encontrado';
  end if;
  if v_escopo.execucao_status in ('executado', 'parcial') then
    raise exception 'Item já tem utilização/execução registrada (%) — não pode mais ser editado; use o fluxo formal de estorno se precisar corrigir', v_escopo.execucao_status;
  end if;
  if v_escopo.execucao_status = 'cancelado' then
    raise exception 'Item já foi removido do escopo desta OS';
  end if;

  if v_escopo.origem_tipo = 'orcamento' then
    select quantidade, valor_unitario into v_qtd_origem, v_valor_origem
      from orcamento_itens where id = v_escopo.orcamento_item_id;
  else
    select quantidade, valor_unitario into v_qtd_origem, v_valor_origem
      from os_adicional_itens where id = v_escopo.os_adicional_item_id;
  end if;

  if p_quantidade is not null and p_quantidade > v_qtd_origem then
    raise exception 'Quantidade solicitada (%) excede o aprovado na origem (%) — aumento de escopo exige Adicional, não edição direta', p_quantidade, v_qtd_origem;
  end if;
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'Quantidade deve ser positiva';
  end if;
  if p_valor_unitario is not null and p_valor_unitario > v_valor_origem then
    raise exception 'Valor unitário solicitado (%) excede o aprovado na origem (%) — aumento de valor exige Adicional, não edição direta', p_valor_unitario, v_valor_origem;
  end if;
  if p_valor_unitario is not null and p_valor_unitario < 0 then
    raise exception 'Valor unitário inválido';
  end if;
  if p_peca_id is not null and not exists (select 1 from pecas where id = p_peca_id) then
    raise exception 'Peça não encontrada';
  end if;

  v_antes := jsonb_build_object(
    'quantidade_escopo', v_escopo.quantidade_escopo,
    'descricao_override', v_escopo.descricao_override,
    'peca_id_override', v_escopo.peca_id_override,
    'valor_unitario_override', v_escopo.valor_unitario_override
  );

  update os_escopo_itens set
    quantidade_escopo = coalesce(p_quantidade, quantidade_escopo),
    descricao_override = coalesce(p_descricao, descricao_override),
    peca_id_override = coalesce(p_peca_id, peca_id_override),
    valor_unitario_override = coalesce(p_valor_unitario, valor_unitario_override),
    editado_em = now(),
    editado_por = auth.uid()
    where id = p_escopo_item_id;

  perform registrar_auditoria('os_escopo_itens', p_escopo_item_id, 'os_item_editado', v_antes,
    jsonb_build_object(
      'quantidade_escopo', coalesce(p_quantidade, v_escopo.quantidade_escopo),
      'descricao_override', coalesce(p_descricao, v_escopo.descricao_override),
      'peca_id_override', coalesce(p_peca_id, v_escopo.peca_id_override),
      'valor_unitario_override', coalesce(p_valor_unitario, v_escopo.valor_unitario_override)
    ), p_motivo);
end;
$$;

-- ============================================================
-- 9. rpc_remover_item_escopo_os — "Remover da OS" (seção 7 do pedido).
-- Mesma regra de BR-042 (motivo obrigatório, bloqueado a partir de
-- executado/parcial), agora na tabela de escopo por-OS. Nunca apaga a linha
-- nem toca no item de origem (orçamento/adicional) — só sai do escopo
-- operacional desta OS, fica consultável no histórico.
-- ============================================================
create or replace function rpc_remover_item_escopo_os(
  p_escopo_item_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_escopo record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para remover item do escopo da OS';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Remover um item do escopo exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;

  select * into v_escopo from os_escopo_itens where id = p_escopo_item_id for update;
  if v_escopo.id is null then
    raise exception 'Item de escopo não encontrado';
  end if;
  if v_escopo.execucao_status in ('executado', 'parcial') then
    raise exception 'Item já tem utilização/execução registrada (%) — não pode ser removido; use o fluxo formal de estorno se precisar corrigir', v_escopo.execucao_status;
  end if;
  if v_escopo.execucao_status = 'cancelado' then
    return; -- já removido, idempotente
  end if;

  update os_escopo_itens set
    execucao_status = 'cancelado',
    removido_em = now(),
    removido_por = auth.uid(),
    motivo_remocao = p_motivo
    where id = p_escopo_item_id;

  perform registrar_auditoria('os_escopo_itens', p_escopo_item_id, 'os_item_removido',
    jsonb_build_object('execucao_status', v_escopo.execucao_status),
    jsonb_build_object('execucao_status', 'cancelado'), p_motivo);
end;
$$;

-- ============================================================
-- 9b. rpc_marcar_item_orcamento_execucao / rpc_marcar_item_os_adicional_execucao
-- — RPCs legadas (marcar mão de obra 'executado', ou "dispensar" um item),
-- ainda usadas pelo frontend (botão check/× de OsServicos.vue). Corpo
-- idêntico ao de 20260814110800_p1c_cancelamento_item_aprovado.sql, só
-- ganham o espelho em os_escopo_itens no final — sem isso, marcar mão de
-- obra como executada por este caminho não apareceria no documento
-- final/cobrança novos (que passam a ler de os_escopo_itens). "Remover da
-- OS" pela tela nova usa rpc_remover_item_escopo_os (seção 9); esta RPC
-- continua existindo por compatibilidade e porque ainda é o único caminho
-- pra marcar mão de obra como executada manualmente.
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

  if v_os_id is not null then
    update os_escopo_itens set execucao_status = p_status where os_id = v_os_id and orcamento_item_id = p_orcamento_item_id;
  end if;

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

  if p_status = 'cancelado' and v_item.execucao_status in ('executado', 'parcial') then
    raise exception 'Item de adicional já executado (%) não pode ser cancelado — cancelamento só é permitido para item aprovado ainda não executado (execucao_status pendente)', v_item.execucao_status;
  end if;

  v_status_anterior := v_item.execucao_status;
  v_os_id := v_item.os_id;

  select status into v_os_status from ordens_servico where id = v_os_id;
  if v_os_status in ('concluida', 'liberada') then
    raise exception 'OS já concluída/liberada — use uma correção formal auditada, não a marcação direta de execução';
  end if;

  update os_adicional_itens set execucao_status = p_status where id = p_item_id;

  update os_escopo_itens set execucao_status = p_status where os_id = v_os_id and os_adicional_item_id = p_item_id;

  perform registrar_auditoria('os_adicional_itens', p_item_id, 'marcar_execucao_item_adicional',
    jsonb_build_object('execucao_status', v_status_anterior), jsonb_build_object('execucao_status', p_status), p_motivo);
end;
$$;

-- ============================================================
-- 10. rpc_concluir_os — remove os dois blocos que bloqueavam conclusão por
-- item aprovado pendente/parcial (20260819180000_p2e_os_fluxo_transicoes.sql
-- linhas 184-195 e 205-214). Todo o resto (apontamento aberto, checklist,
-- fotos, adicional aguardando decisão do cliente) continua bloqueando —
-- essas são pendências reais, não "aprovado ≠ usado".
-- ============================================================
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

  -- OS-ESCOPO-04: item aprovado 'pendente'/'parcial' NÃO bloqueia mais
  -- conclusão (aprovado ≠ obrigatoriamente executado/utilizado, BR-021
  -- passa de PROVISÓRIA a DEFINIDA com esta semântica). Use
  -- rpc_resumo_escopo_pendente_os antes de chamar esta RPC para exibir o
  -- resumo informativo ao usuário (seção 22 do pedido) — a decisão de
  -- concluir com escopo reduzido é do usuário, a proteção real (não pode
  -- aumentar cobrança silenciosamente, não pode apagar histórico) continua
  -- toda no backend, só não é mais este bloqueio específico.
  select exists (
    select 1 from os_adicionais a
    where a.os_id = p_os_id and a.status = 'aguardando_aprovacao'
  ) into v_adicional_aguardando;
  if v_adicional_aguardando then
    raise exception 'Existe adicional aguardando decisão do cliente — resolva a aprovação (ADC-003/004) antes de concluir';
  end if;

  update ordens_servico set status = 'concluida' where id = p_os_id;

  if v_os.tipo = 'interna' then
    perform calcular_e_snapshot_custo_interno_os(p_os_id);
  end if;
end;
$$;

-- ============================================================
-- 11. rpc_resumo_escopo_pendente_os — leitura, alimenta o modal "Concluir
-- mesmo assim?" do frontend (seção 22 do pedido) ANTES de chamar
-- rpc_concluir_os.
-- ============================================================
create or replace function rpc_resumo_escopo_pendente_os(p_os_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'pecas_nao_utilizadas', (
      select count(*) from os_escopo_itens ei
      join orcamento_itens oi on oi.id = ei.orcamento_item_id
      where ei.os_id = p_os_id and ei.origem_tipo = 'orcamento'
        and oi.peca_id is not null and ei.execucao_status in ('pendente', 'parcial')
      union all
      select count(*) from os_escopo_itens ei
      join os_adicional_itens oai on oai.id = ei.os_adicional_item_id
      where ei.os_id = p_os_id and ei.origem_tipo = 'adicional'
        and oai.peca_id is not null and ei.execucao_status in ('pendente', 'parcial')
    ),
    'servicos_nao_executados', (
      select count(*) from os_escopo_itens ei
      join orcamento_itens oi on oi.id = ei.orcamento_item_id
      where ei.os_id = p_os_id and ei.origem_tipo = 'orcamento'
        and oi.peca_id is null and ei.execucao_status in ('pendente', 'parcial')
      union all
      select count(*) from os_escopo_itens ei
      join os_adicional_itens oai on oai.id = ei.os_adicional_item_id
      where ei.os_id = p_os_id and ei.origem_tipo = 'adicional'
        and oai.peca_id is null and ei.execucao_status in ('pendente', 'parcial')
    )
  );
$$;

revoke execute on function rpc_resumo_escopo_pendente_os(uuid) from public, anon;

-- ============================================================
-- 12. rpc_criar_cobranca — deixa de somar o valor INTEGRAL de todo item
-- aprovado e não cancelado, passa a ponderar pela quantidade REALMENTE
-- utilizada/executada (seções 17-19 do pedido). Reaproveita literalmente a
-- MESMA fórmula que rpc_documento_final_os (20260820190000) já usa em
-- 'resumo_financeiro.valor_final' — peça = quantidade líquida do ledger ×
-- valor_unitario BRUTO (não valor_liquido — o desconto é subtraído à parte,
-- como uma linha só, igual já fazia o documento final); mão de obra
-- binária (executado = 100%, senão 0); desconto = soma de
-- desconto_rateado de todo item aprovado ainda no escopo (não prorateado
-- por utilização — mesmo comportamento que já existia). Reusar a mesma
-- fórmula em vez de inventar uma nova garante, por construção, que
-- documento final e cobrança nunca divirjam (seção 19 do pedido: "Documento
-- R$1700, Cobrança R$1900 sem justificativa" deixa de poder acontecer).
-- Adicional não tem desconto (BR-011 é conceito orçamento-only).
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
  v_valor_desconto numeric(12,2);
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

    -- Itens do orçamento original: quantidade líquida do ledger (peça) ou
    -- binário executado (mão de obra), sobre valor_unitario BRUTO — mesma
    -- fórmula de rpc_documento_final_os (subtotal_pecas/subtotal_mao_obra).
    -- Agregação em duas camadas: a subquery calcula a quantidade líquida
    -- POR ITEM (precisa de group by ali), a agregação externa soma o valor
    -- resultante de TODOS os itens (sem group by — senão só o primeiro item
    -- do grupo seria atribuído à variável escalar).
    select coalesce(sum(
      case
        when v.peca_id is not null then greatest(v.qtd_liquida, 0) * v.valor_unitario
        when v.execucao_status = 'executado' then v.quantidade * v.valor_unitario
        else 0
      end
    ), 0) into v_valor_itens_aprovados
    from (
      select oi.id, oi.peca_id, oi.quantidade, oi.valor_unitario, ei.execucao_status,
        coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
          - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0) as qtd_liquida
      from orcamento_itens oi
      join os_escopo_itens ei on ei.orcamento_item_id = oi.id and ei.os_id = v_os_id
      left join estoque_movimentos em on em.orcamento_item_id = oi.id and em.origem_tipo = 'os' and em.origem_id = v_os_id
      where oi.orcamento_id = v_os.orcamento_id and oi.status_aprovacao = 'aprovado' and ei.execucao_status <> 'cancelado'
      group by oi.id, oi.peca_id, oi.quantidade, oi.valor_unitario, ei.execucao_status
    ) v;

    -- Desconto: soma de desconto_rateado de todo item aprovado ainda no
    -- escopo desta OS (não prorateado por utilização — mesmo comportamento
    -- que rpc_documento_final_os.desconto já tinha).
    select coalesce(sum(oi.desconto_rateado), 0) into v_valor_desconto
      from orcamento_itens oi
      join os_escopo_itens ei on ei.orcamento_item_id = oi.id and ei.os_id = v_os_id
      where oi.orcamento_id = v_os.orcamento_id and oi.status_aprovacao = 'aprovado' and ei.execucao_status <> 'cancelado';

    -- Itens de adicional: mesma lógica de quantidade, sobre valor_unitario
    -- (adicional não tem desconto — BR-011 é conceito orçamento-only).
    select coalesce(sum(
      case
        when v.peca_id is not null then greatest(v.qtd_liquida, 0) * v.valor_unitario
        when v.execucao_status = 'executado' then v.quantidade * v.valor_unitario
        else 0
      end
    ), 0) into v_valor_adicionais_aprovados
    from (
      select oai.id, oai.peca_id, oai.quantidade, oai.valor_unitario, ei.execucao_status,
        coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
          - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0) as qtd_liquida
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      join os_escopo_itens ei on ei.os_adicional_item_id = oai.id and ei.os_id = v_os_id
      left join estoque_movimentos em on em.os_adicional_item_id = oai.id and em.origem_tipo = 'os' and em.origem_id = v_os_id
      where a.os_id = v_os_id and oai.status_aprovacao = 'aprovado' and ei.execucao_status <> 'cancelado'
      group by oai.id, oai.peca_id, oai.quantidade, oai.valor_unitario, ei.execucao_status
    ) v;

    select coalesce(sum(a.valor_acrescimo), 0) into v_valor_acrescimos
      from orcamento_acrescimos a where a.orcamento_id = v_os.orcamento_id;

    v_valor_total := v_valor_total + v_valor_itens_aprovados - v_valor_desconto + v_valor_adicionais_aprovados + v_valor_acrescimos;
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

-- ============================================================
-- 13. rpc_documento_final_os — corpo idêntico ao original
-- (20260820190000_p3_doc_os_final01.sql), preservando toda a estrutura
-- (empresa/os/cliente/veiculo/executores/resumo_financeiro/cobranca/
-- custo_interno/garantia). Única mudança: peca_qtd/mao_obra/desconto agora
-- fazem JOIN com os_escopo_itens (fonte de verdade por-OS a partir desta
-- etapa) em vez de ler execucao_status direto de
-- orcamento_itens/os_adicional_itens — resolve também o gap que o
-- comentário original documentava (item parcial agora chega até aqui de
-- verdade, não só executado 100%/cancelado 0%). peca_id/descricao ganham
-- override quando o item foi editado via rpc_editar_item_escopo_os.
-- ============================================================
create or replace function rpc_documento_final_os(p_os_id uuid)
returns jsonb
language sql
stable
as $$
  with peca_qtd as (
    select oi.id as item_id, coalesce(ei.peca_id_override, oi.peca_id) as peca_id,
           coalesce(ei.descricao_override, oi.descricao) as descricao, oi.valor_unitario,
           coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
             - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0) as quantidade_utilizada
    from orcamento_itens oi
    join os_escopo_itens ei on ei.orcamento_item_id = oi.id and ei.os_id = p_os_id
    left join estoque_movimentos em
      on em.orcamento_item_id = oi.id and em.origem_tipo = 'os' and em.origem_id = p_os_id
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.peca_id is not null
      and oi.status_aprovacao = 'aprovado'
      and ei.execucao_status <> 'cancelado'
    group by oi.id, oi.peca_id, oi.descricao, oi.valor_unitario, ei.peca_id_override, ei.descricao_override
    union all
    select oai.id, coalesce(ei.peca_id_override, oai.peca_id), coalesce(ei.descricao_override, oai.descricao), oai.valor_unitario,
           coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
             - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0)
    from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    join os_escopo_itens ei on ei.os_adicional_item_id = oai.id and ei.os_id = p_os_id
    left join estoque_movimentos em
      on em.os_adicional_item_id = oai.id and em.origem_tipo = 'os' and em.origem_id = p_os_id
    where a.os_id = p_os_id
      and oai.peca_id is not null
      and oai.status_aprovacao = 'aprovado'
      and ei.execucao_status <> 'cancelado'
    group by oai.id, oai.peca_id, oai.descricao, oai.valor_unitario, ei.peca_id_override, ei.descricao_override
  ),
  mao_obra as (
    select oi.id as item_id, coalesce(ei.descricao_override, oi.descricao) as descricao, oi.quantidade, oi.valor_unitario
    from orcamento_itens oi
    join os_escopo_itens ei on ei.orcamento_item_id = oi.id and ei.os_id = p_os_id
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.peca_id is null
      and oi.status_aprovacao = 'aprovado'
      and ei.execucao_status = 'executado'
    union all
    select oai.id, coalesce(ei.descricao_override, oai.descricao), oai.quantidade, oai.valor_unitario
    from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    join os_escopo_itens ei on ei.os_adicional_item_id = oai.id and ei.os_id = p_os_id
    where a.os_id = p_os_id
      and oai.peca_id is null
      and oai.status_aprovacao = 'aprovado'
      and ei.execucao_status = 'executado'
  ),
  subtotal_pecas as (
    select coalesce(sum(quantidade_utilizada * valor_unitario), 0) as valor
    from peca_qtd where quantidade_utilizada > 0
  ),
  subtotal_mao_obra as (
    select coalesce(sum(quantidade * valor_unitario), 0) as valor from mao_obra
  ),
  desconto as (
    -- Só orçamento tem desconto (item 20) — adicional nunca tem, nesta etapa
    -- do produto (mesma nota já registrada em rpc_criar_cobranca). Filtro de
    -- remoção agora via os_escopo_itens (por-OS), não mais
    -- orcamento_itens.execucao_status direto.
    select coalesce(sum(oi.desconto_rateado), 0) as valor
    from orcamento_itens oi
    join os_escopo_itens ei on ei.orcamento_item_id = oi.id and ei.os_id = p_os_id
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.status_aprovacao = 'aprovado' and ei.execucao_status <> 'cancelado'
  ),
  acrescimos as (
    select coalesce(sum(a.valor_acrescimo), 0) as valor
    from orcamento_acrescimos a
    where a.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
  )
  select jsonb_build_object(
    'empresa', jsonb_build_object('nome', 'Tropical Transportes — Oficina Mecânica'),
    'os', jsonb_build_object(
      'id', os.id,
      'numero_legivel', 'OS-' || upper(substr(os.id::text, 1, 8)),
      'tipo', os.tipo,
      'status', os.status,
      'data_abertura', os.data_abertura,
      'data_liberacao', os.data_liberacao
    ),
    'cliente', jsonb_build_object(
      'id', cli.id, 'nome', cli.nome, 'documento', cli.documento,
      'telefone', cli.telefone, 'email', cli.email, 'tipo', cli.tipo
    ),
    'veiculo', jsonb_build_object(
      'id', vei.id, 'placa', vei.placa, 'modelo', vei.modelo, 'ano', vei.ano, 'prefixo', vei.prefixo
    ),
    'executores', coalesce((
      select jsonb_agg(distinct p.nome order by p.nome)
      from os_executores oe join profiles p on p.id = oe.usuario_id
      where oe.os_id = os.id
    ), '[]'::jsonb),
    'pecas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'descricao', pq.descricao,
        'sku', pe.sku,
        'quantidade', pq.quantidade_utilizada,
        'valor_unitario', pq.valor_unitario,
        'valor_total', round(pq.quantidade_utilizada * pq.valor_unitario, 2)
      ) order by pq.descricao)
      from peca_qtd pq left join pecas pe on pe.id = pq.peca_id
      where pq.quantidade_utilizada > 0
    ), '[]'::jsonb),
    'mao_de_obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'descricao', mo.descricao,
        'quantidade', mo.quantidade,
        'valor_unitario', mo.valor_unitario,
        'valor_total', round(mo.quantidade * mo.valor_unitario, 2)
      ) order by mo.descricao)
      from mao_obra mo
    ), '[]'::jsonb),
    'resumo_financeiro', jsonb_build_object(
      'subtotal_pecas', (select valor from subtotal_pecas),
      'subtotal_mao_obra', (select valor from subtotal_mao_obra),
      'valor_bruto', (select valor from subtotal_pecas) + (select valor from subtotal_mao_obra),
      'desconto_valor', (select valor from desconto),
      'acrescimos_valor', (select valor from acrescimos),
      'valor_final', round(
        (select valor from subtotal_pecas) + (select valor from subtotal_mao_obra)
          - (select valor from desconto) + (select valor from acrescimos)
      , 2)
    ),
    'cobranca', (
      select jsonb_build_object('id', c.id, 'valor_total', c.valor_total, 'status', c.status)
      from cobranca_origens co join cobrancas c on c.id = co.cobranca_id
      where co.os_id = os.id and c.status <> 'cancelada'
      order by c.criado_em desc limit 1
    ),
    'custo_interno', case when os.tipo = 'interna' then jsonb_build_object(
      'custo_pecas', os.custo_pecas,
      'custo_mao_obra', os.custo_mao_obra,
      'custo_total', os.custo_total
    ) else null end,
    'garantia', case when os.data_liberacao is not null then jsonb_build_object(
      'prazo_dias', 90,
      'expira_em', os.data_liberacao + interval '90 days'
    ) else null end
  )
  from ordens_servico os
  join clientes cli on cli.id = os.cliente_id
  join veiculos vei on vei.id = os.veiculo_id
  where os.id = p_os_id;
$$;

comment on function rpc_documento_final_os(uuid) is
  'Documento comercial de conclusão da OS (DOC-OS-FINAL-01, redefinida na ETAPA OS-ESCOPO-04) — só leitura, security invoker (RLS de cada tabela consultada aplica normalmente). Não confundir com rpc_relatorio_encerramento_os (relatório interno de auditoria, BR-025).';
