-- ETAPA 4 (P1-A) — item G: GAR-005, garantia precisa ficar ligada à OS
-- original E ao item/serviço original (BR-024). Antes, rpc_criar_os_garantia
-- só copiava veículo/cliente/tipo/checklist da OS original — nada
-- identificava QUAL item/serviço da OS original é objeto da garantia, então
-- qualquer coisa podia ser lançada na OS de garantia sem relação nenhuma com
-- o que motivou o retorno.
create table os_garantia_itens (
  id uuid primary key default gen_random_uuid(),
  os_garantia_id uuid not null references ordens_servico(id),
  orcamento_item_original_id uuid not null references orcamento_itens(id),
  motivo text not null,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now(),
  unique (os_garantia_id, orcamento_item_original_id)
);

create index idx_os_garantia_itens_os on os_garantia_itens (os_garantia_id);

alter table os_garantia_itens enable row level security;

create policy "os_garantia_itens_select_autenticado" on os_garantia_itens
  for select
  using (current_user_ativo());

-- Escrita só via rpc_criar_os_garantia (abaixo) — nenhuma policy/grant de
-- INSERT/UPDATE/DELETE direto para o cliente.
revoke insert, update, delete on os_garantia_itens from authenticated, anon;

-- rpc_criar_os_garantia agora EXIGE ao menos um item original (da OS que
-- está sendo reaberta em garantia) e grava o vínculo. Sem orçamento na OS
-- original (ex.: OS interna, sem orcamento_id) não há item pra vincular —
-- nesse caso o array pode vir vazio (nada a exigir; residual documentado no
-- relatório, fora do escopo típico de garantia de cliente externo).
drop function if exists rpc_criar_os_garantia(uuid);

create or replace function rpc_criar_os_garantia(p_os_origem_id uuid, p_itens_originais uuid[] default null)
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

  -- GAR-005: quando a OS original tem orçamento, é obrigatório informar
  -- quais itens dele são objeto desta garantia — impede abrir uma garantia
  -- "em branco" e depois lançar qualquer serviço sem relação com a origem.
  if v_orig.orcamento_id is not null then
    if p_itens_originais is null or array_length(p_itens_originais, 1) is null or array_length(p_itens_originais, 1) = 0 then
      raise exception 'Informe ao menos um item da OS original (p_itens_originais) — garantia sem vínculo com item/serviço original não é permitida';
    end if;

    select count(*) into v_qtd_itens_validos
      from orcamento_itens where id = any(p_itens_originais) and orcamento_id = v_orig.orcamento_id;
    if v_qtd_itens_validos <> array_length(p_itens_originais, 1) then
      raise exception 'Um ou mais itens informados não pertencem ao orçamento da OS original';
    end if;
  end if;

  insert into ordens_servico (veiculo_id, cliente_id, tipo, checklist_template_id, os_origem_id, criado_por)
  values (v_orig.veiculo_id, v_orig.cliente_id, v_orig.tipo, v_orig.checklist_template_id, p_os_origem_id, auth.uid())
  returning id into v_novo_id;

  if p_itens_originais is not null then
    foreach v_item_id in array p_itens_originais loop
      insert into os_garantia_itens (os_garantia_id, orcamento_item_original_id, motivo, criado_por)
      values (v_novo_id, v_item_id, 'Retorno em garantia (90 dias) do item da OS ' || p_os_origem_id, auth.uid());
    end loop;
  end if;

  update ordens_servico set status = 'reaberta_garantia' where id = p_os_origem_id;

  return v_novo_id;
end;
$$;

-- ============================================================
-- rpc_baixar_peca_os ganha o ramo de garantia: quando a OS é de garantia
-- (os_origem_id preenchido, orcamento_id sempre NULL nesse caso — ver
-- constraint os_externa_exige_orcamento), a baixa também exige
-- p_orcamento_item_id, mas validado contra os_garantia_itens (item da OS
-- ORIGINAL) em vez de orcamento_itens da própria OS (que não tem
-- orçamento). Isso fecha o requisito de GAR-005: não dá pra lançar peça sem
-- relação com o item que motivou o retorno. Cota própria por OS de
-- garantia (não compartilha com o que já foi consumido na OS original).
-- ============================================================
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
  end if;

  if v_item.id is not null then
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
