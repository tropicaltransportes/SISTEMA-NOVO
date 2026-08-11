-- Fase 6 (correções P0 da auditoria de 2026-08-10, ver docs/testing/TEST_REPORT.md)
--
-- Corrige 6 achados P0, todos por CREATE OR REPLACE FUNCTION (nenhuma
-- migration antiga é alterada). Resumo:
--
--   P0-01 (AUT-005): current_perfil() retorna NULL para chamador sem sessão
--     (papel anon), e "NULL NOT IN (lista)" avalia NULL, que o IF do plpgsql
--     trata como falso — a exceção de permissão nunca disparava. Corrigido
--     centralizando a checagem na função tem_perfil() abaixo (usa "= ANY"
--     depois de garantir NOT NULL) e trocando TODA RPC afetada.
--   P0-02 (DOC-006): policy de leitura do bucket 'comprovantes' liberava
--     qualquer autenticado, sem checar perfil. Restringe a quem já tem
--     acesso ao módulo financeiro (mesmo critério usado em cobrancas/
--     parcelas/recebimentos: current_perfil() <> 'executor').
--   P0-03 (OS-004): rpc_criar_os não impedia reconverter um orçamento já
--     usado por outra OS ainda ativa.
--   P0-04 (EST-009): rpc_baixar_peca_os não tinha proteção de idempotência
--     — duplo clique duplicava a baixa. Adiciona janela de deduplicação de
--     5s para baixa idêntica (mesma OS/peça/quantidade).
--   P0-05 (OS-010): cancelar uma OS não estornava peças já baixadas. Adiciona
--     estorno automático (compensatório, auditável) de toda baixa vinculada
--     à OS ao cancelar, e cria rpc_estornar_saida_estoque (uso manual,
--     também fecha a lacuna EST-010 — não existia estorno de saída).
--   P0-06 (LIB-006): rpc_liberar_os só aceitava encarregado/
--     administrador_tecnico; BR-022/plano-arquitetura preveem que
--     suporte_administrativo também libere.
--
-- Cada função abaixo reproduz o corpo original (mesma migration de origem
-- citada no comentário) alterando SOMENTE o que está descrito acima.

-- ============================================================
-- Helper central de permissão (P0-01)
-- ============================================================
create or replace function tem_perfil(variadic p_perfis perfil_usuario[])
returns boolean
language sql
stable
as $$
  select current_perfil() is not null and current_perfil() = any(p_perfis)
$$;

comment on function tem_perfil is
  'Checagem de perfil que falha fechado (nega) quando current_perfil() é NULL — ou seja, chamador sem sessão. Substitui o padrão "current_perfil() not in (...)", que falhava aberto (permitia) para NULL. Ver docs/testing/TEST_REPORT.md, Achado crítico #1.';

-- ============================================================
-- Funções internas sem checagem de perfil própria: reforça o REVOKE
-- (P0-01 também cobre estas — o REVOKE de "from public" nas migrations
-- originais não bloqueava os papéis anon/authenticated, que recebem grants
-- próprios por padrão no Supabase).
-- ============================================================
revoke execute on function rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid) from public, anon, authenticated;
revoke execute on function rpc_registrar_entrada_estoque(uuid, numeric, numeric, origem_movimento, uuid) from public, anon, authenticated;
revoke execute on function marcar_solicitacao_convertida(uuid, status_solicitacao) from public, anon, authenticated;

-- ============================================================
-- P0-05 / EST-010: coluna para rastrear estorno de saída + RPCs
-- ============================================================
alter table estoque_movimentos add column if not exists estornado_de uuid references estoque_movimentos(id);

-- Núcleo do estorno de saída, sem checagem de perfil própria (mesmo padrão
-- de rpc_registrar_saida_estoque/entrada_estoque): só é chamada internamente
-- por rpc_estornar_saida_estoque (checa perfil) ou por rpc_transicionar_os
-- no cancelamento (já validou perfil antes de chegar aqui).
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
end;
$$;

revoke execute on function estornar_saida_estoque_interno(uuid) from public, anon, authenticated;

-- Wrapper público (uso manual, ex.: peça baixada errada por engano) — fecha
-- a lacuna EST-010 (não existia nenhuma forma de estornar uma saída).
create or replace function rpc_estornar_saida_estoque(p_movimento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para estornar saída de estoque';
  end if;
  perform estornar_saida_estoque_interno(p_movimento_id);
end;
$$;

-- ============================================================
-- Orçamentos (origem: 20260806130100_orcamentos.sql) — P0-01
-- ============================================================
create or replace function rpc_enviar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
  v_qtd_itens int;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para enviar orçamento';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'rascunho' then
    raise exception 'Somente orçamentos em rascunho podem ser enviados';
  end if;

  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  if v_qtd_itens = 0 then
    raise exception 'Orçamento precisa de ao menos um item para ser enviado';
  end if;

  update orcamentos set status = 'enviado' where id = p_orcamento_id;
end;
$$;

create or replace function rpc_registrar_autorizacao_orcamento(
  p_orcamento_id uuid,
  p_autorizado_por_nome text,
  p_comprovante_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar autorização';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'enviado' then
    raise exception 'Autorização só pode ser registrada em orçamento enviado';
  end if;

  update orcamentos
    set autorizado_por_nome = p_autorizado_por_nome,
        comprovante_path = p_comprovante_path,
        autorizado_em = now()
    where id = p_orcamento_id;
end;
$$;

create or replace function rpc_aprovar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_tipo_cliente tipo_cliente;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para aprovar orçamento';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.status <> 'enviado' then
    raise exception 'Somente orçamentos enviados podem ser aprovados';
  end if;

  select tipo into v_tipo_cliente from clientes where id = v_orc.cliente_id;
  if v_tipo_cliente = 'externo' and (v_orc.autorizado_por_nome is null or v_orc.comprovante_path is null) then
    raise exception 'Cliente externo exige autorização (nome + comprovante) antes de aprovar';
  end if;

  update orcamentos set status = 'aprovado' where id = p_orcamento_id;

  if v_orc.solicitacao_id is not null then
    perform marcar_solicitacao_convertida(v_orc.solicitacao_id, 'convertida_orcamento');
  end if;
end;
$$;

create or replace function rpc_rejeitar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para rejeitar orçamento';
  end if;

  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_status <> 'enviado' then
    raise exception 'Somente orçamentos enviados podem ser rejeitados';
  end if;

  update orcamentos set status = 'rejeitado' where id = p_orcamento_id;
end;
$$;

create or replace function rpc_criar_versao_orcamento(p_orcamento_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig record;
  v_raiz_id uuid;
  v_nova_versao int;
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para versionar orçamento';
  end if;

  select * into v_orig from orcamentos where id = p_orcamento_id for update;
  if v_orig.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orig.status not in ('enviado', 'aprovado', 'rejeitado') then
    raise exception 'Só é possível versionar orçamento enviado, aprovado ou rejeitado';
  end if;

  v_raiz_id := coalesce(v_orig.orcamento_raiz_id, v_orig.id);
  select coalesce(max(versao), 0) + 1 into v_nova_versao
    from orcamentos where id = v_raiz_id or orcamento_raiz_id = v_raiz_id;

  insert into orcamentos (solicitacao_id, veiculo_id, cliente_id, orcamento_raiz_id, versao, status, criado_por)
  values (v_orig.solicitacao_id, v_orig.veiculo_id, v_orig.cliente_id, v_raiz_id, v_nova_versao, 'rascunho', auth.uid())
  returning id into v_novo_id;

  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
  select v_novo_id, peca_id, descricao, quantidade, valor_unitario
    from orcamento_itens where orcamento_id = p_orcamento_id;

  update orcamentos set status = 'substituido' where id = p_orcamento_id;

  return v_novo_id;
end;
$$;

create or replace function rpc_registrar_acrescimo(
  p_orcamento_id uuid,
  p_valor_acrescimo numeric,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_percentual numeric(5,2);
  v_limite_percentual numeric(12,2);
  v_acumulado numeric(12,2);
  v_teto_absoluto constant numeric(12,2) := 5000.00;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar acréscimo';
  end if;

  if p_valor_acrescimo <= 0 then
    raise exception 'Valor de acréscimo deve ser positivo';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.status <> 'aprovado' then
    raise exception 'Acréscimo só pode ser registrado em orçamento aprovado';
  end if;

  select percentual_max into v_percentual
    from orcamento_faixa_acrescimo
    where ativo and v_orc.valor_total >= valor_min and (valor_max is null or v_orc.valor_total <= valor_max)
    order by valor_min desc
    limit 1;

  if v_percentual is null then
    raise exception 'Nenhuma faixa de acréscimo configurada para orçamentos de valor R$ %', v_orc.valor_total;
  end if;

  v_limite_percentual := round(v_orc.valor_total * v_percentual / 100, 2);

  select coalesce(sum(valor_acrescimo), 0) into v_acumulado
    from orcamento_acrescimos where orcamento_id = p_orcamento_id;
  v_acumulado := v_acumulado + p_valor_acrescimo;

  if v_acumulado > v_limite_percentual then
    raise exception 'Acréscimo acumulado (R$ %) excede o limite da faixa (% %% de R$ % = R$ %)',
      v_acumulado, v_percentual, v_orc.valor_total, v_limite_percentual;
  end if;

  if v_acumulado > v_teto_absoluto then
    raise exception 'Acréscimo acumulado (R$ %) excede o teto absoluto de R$ %', v_acumulado, v_teto_absoluto;
  end if;

  insert into orcamento_acrescimos (orcamento_id, valor_acrescimo, justificativa, aprovado_por)
  values (p_orcamento_id, p_valor_acrescimo, p_justificativa, auth.uid());
end;
$$;

-- ============================================================
-- Ordens de Serviço (origem: 20260806130200_ordens_servico.sql)
-- P0-01 em todas; P0-03 (OS-004) em rpc_criar_os; P0-04 (EST-009) em
-- rpc_baixar_peca_os; P0-05 (OS-010) em rpc_transicionar_os.
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
    -- P0-03 / OS-004: impede reconverter um orçamento que já gerou uma OS
    -- ativa (não cancelada). OS cancelada não bloqueia nova tentativa.
    if exists (
      select 1 from ordens_servico os
      where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada'
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

  return v_novo_id;
end;
$$;

create or replace function rpc_definir_checklist_os(p_os_id uuid, p_checklist_template_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para definir checklist da OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada, checklist não pode mais ser alterado';
  end if;

  update ordens_servico set checklist_template_id = p_checklist_template_id where id = p_os_id;
end;
$$;

create or replace function rpc_transicionar_os(p_os_id uuid, p_novo_status status_os)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_permitido boolean := false;
  v_mov_id uuid;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para transicionar OS';
  end if;

  if p_novo_status in ('concluida', 'liberada', 'reaberta_garantia') then
    raise exception 'Use a RPC específica para esta transição (rpc_concluir_os / rpc_liberar_os)';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  v_permitido := (v_status, p_novo_status) in (
    ('aberta', 'em_diagnostico'),
    ('em_diagnostico', 'aguardando_aprovacao'),
    ('em_diagnostico', 'em_execucao'),
    ('aguardando_aprovacao', 'em_execucao'),
    ('em_execucao', 'aguardando_teste'),
    ('aberta', 'cancelada'),
    ('em_diagnostico', 'cancelada'),
    ('aguardando_aprovacao', 'cancelada')
  );

  if not v_permitido then
    raise exception 'Transição % -> % não é permitida', v_status, p_novo_status;
  end if;

  -- P0-05 / OS-010: cancelar a OS estorna (compensa) toda baixa de estoque
  -- ainda não estornada vinculada a ela, em vez de deixar o estoque
  -- comprometido órfão. Chamada interna (sem checagem de perfil própria) —
  -- já validamos acima que o chamador é encarregado/administrador_tecnico.
  if p_novo_status = 'cancelada' then
    for v_mov_id in
      select em.id from estoque_movimentos em
      where em.origem_tipo = 'os' and em.origem_id = p_os_id and em.tipo = 'saida'
        and not exists (select 1 from estoque_movimentos e2 where e2.estornado_de = em.id)
    loop
      perform estornar_saida_estoque_interno(v_mov_id);
    end loop;
  end if;

  update ordens_servico set status = p_novo_status where id = p_os_id;
end;
$$;

create or replace function rpc_concluir_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_pendente boolean;
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

  update ordens_servico set status = 'concluida' where id = p_os_id;
end;
$$;

create or replace function rpc_baixar_peca_os(p_os_id uuid, p_peca_id uuid, p_quantidade numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if not tem_perfil('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  -- P0-04 / EST-009: bloqueia baixa idêntica (mesma OS/peça/quantidade)
  -- registrada nos últimos 5s — protege contra duplo clique/retry de rede
  -- sem impedir uma segunda baixa legítima e distinta no tempo.
  if exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id);
end;
$$;

-- ============================================================
-- Liberação/Garantia (origem: 20260806150000_garantia.sql — versão vigente
-- de rpc_liberar_os) — P0-01 + P0-06 (LIB-006: inclui suporte_administrativo)
-- ============================================================
create or replace function rpc_liberar_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_cobranca record;
  v_condicao_ok boolean;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para liberar OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'concluida' then
    raise exception 'Somente OS concluída pode ser liberada';
  end if;

  if v_os.tipo = 'externa' and v_os.os_origem_id is null then
    select c.* into v_cobranca
      from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.os_id = p_os_id and c.status <> 'cancelada'
      order by c.criado_em desc
      limit 1;

    if v_cobranca.id is null then
      raise exception 'OS externa exige cobrança gerada antes da liberação';
    end if;

    v_condicao_ok := v_cobranca.status = 'quitada'
      or exists (select 1 from parcelas where cobranca_id = v_cobranca.id)
      or exists (select 1 from termos_ciencia_debito where cobranca_id = v_cobranca.id);

    if not v_condicao_ok then
      raise exception 'Condição financeira pendente: parcele, quite a cobrança ou registre o Termo de Ciência de Débito';
    end if;
  end if;

  update ordens_servico set status = 'liberada', data_liberacao = now() where id = p_os_id;
end;
$$;

create or replace function rpc_criar_os_garantia(p_os_origem_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig record;
  v_novo_id uuid;
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

  insert into ordens_servico (veiculo_id, cliente_id, tipo, checklist_template_id, os_origem_id, criado_por)
  values (v_orig.veiculo_id, v_orig.cliente_id, v_orig.tipo, v_orig.checklist_template_id, p_os_origem_id, auth.uid())
  returning id into v_novo_id;

  update ordens_servico set status = 'reaberta_garantia' where id = p_os_origem_id;

  return v_novo_id;
end;
$$;

-- ============================================================
-- Financeiro (origem: 20260806140000_financeiro.sql) — P0-01
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
  v_valor_os numeric(12,2);
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

    select o.valor_total + coalesce((select sum(a.valor_acrescimo) from orcamento_acrescimos a where a.orcamento_id = o.id), 0)
      into v_valor_os
      from orcamentos o where o.id = v_os.orcamento_id;
    v_valor_total := v_valor_total + coalesce(v_valor_os, 0);
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

create or replace function rpc_parcelar_cobranca(p_cobranca_id uuid, p_parcelas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cobranca record;
  v_parcela jsonb;
  v_soma numeric(12,2) := 0;
  v_qtd_existentes int;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para parcelar cobrança';
  end if;

  select * into v_cobranca from cobrancas where id = p_cobranca_id for update;
  if v_cobranca.id is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_cobranca.status <> 'aberta' then
    raise exception 'Somente cobranças em aberto podem ser parceladas';
  end if;

  select count(*) into v_qtd_existentes from parcelas where cobranca_id = p_cobranca_id;
  if v_qtd_existentes > 0 then
    raise exception 'Cobrança já possui parcelamento formalizado';
  end if;

  if p_parcelas is null or jsonb_array_length(p_parcelas) = 0 then
    raise exception 'Informe ao menos uma parcela';
  end if;

  for v_parcela in select * from jsonb_array_elements(p_parcelas)
  loop
    if (v_parcela ->> 'valor')::numeric <= 0 then
      raise exception 'Valor de parcela inválido';
    end if;
    v_soma := v_soma + (v_parcela ->> 'valor')::numeric;
  end loop;

  if abs(v_soma - v_cobranca.valor_total) > 0.01 then
    raise exception 'Soma das parcelas (R$ %) não confere com o valor da cobrança (R$ %)', v_soma, v_cobranca.valor_total;
  end if;

  insert into parcelas (cobranca_id, numero_parcela, valor, vencimento)
  select p_cobranca_id, (v.item ->> 'numero_parcela')::int, (v.item ->> 'valor')::numeric, (v.item ->> 'vencimento')::date
  from jsonb_array_elements(p_parcelas) as v(item);
end;
$$;

create or replace function rpc_registrar_recebimento(
  p_parcela_id uuid,
  p_valor_recebido numeric,
  p_forma_pagamento text,
  p_data_recebimento date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parcela record;
  v_cobranca record;
  v_ja_recebido numeric(12,2);
  v_total_recebido numeric(12,2);
  v_novo_status status_cobranca;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar recebimento';
  end if;

  if p_valor_recebido <= 0 then
    raise exception 'Valor recebido deve ser positivo';
  end if;

  select * into v_parcela from parcelas where id = p_parcela_id for update;
  if v_parcela.id is null then
    raise exception 'Parcela não encontrada';
  end if;
  if v_parcela.status <> 'pendente' then
    raise exception 'Somente parcelas pendentes podem receber pagamento';
  end if;

  select * into v_cobranca from cobrancas where id = v_parcela.cobranca_id for update;
  if v_cobranca.status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe pagamento';
  end if;

  select coalesce(sum(valor_recebido), 0) into v_ja_recebido from recebimentos where parcela_id = p_parcela_id;
  if v_ja_recebido + p_valor_recebido > v_parcela.valor + 0.01 then
    raise exception 'Valor recebido (R$ %) excede o saldo da parcela (R$ %)', p_valor_recebido, v_parcela.valor - v_ja_recebido;
  end if;

  insert into recebimentos (parcela_id, valor_recebido, forma_pagamento, data_recebimento, criado_por)
  values (p_parcela_id, p_valor_recebido, p_forma_pagamento, p_data_recebimento, auth.uid());

  if v_ja_recebido + p_valor_recebido >= v_parcela.valor - 0.01 then
    update parcelas set status = 'paga' where id = p_parcela_id;
  end if;

  select coalesce(sum(r.valor_recebido), 0) into v_total_recebido
    from recebimentos r join parcelas p on p.id = r.parcela_id
    where p.cobranca_id = v_cobranca.id;

  if v_total_recebido >= v_cobranca.valor_total - 0.01 then
    v_novo_status := 'quitada';
  elsif v_total_recebido > 0 then
    v_novo_status := 'parcial';
  else
    v_novo_status := 'aberta';
  end if;

  update cobrancas set status = v_novo_status where id = v_cobranca.id;
end;
$$;

create or replace function rpc_registrar_termo_ciencia(p_cobranca_id uuid, p_arquivo_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_cobranca;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar termo de ciência';
  end if;

  if p_arquivo_path is null or p_arquivo_path = '' then
    raise exception 'Arquivo do termo é obrigatório';
  end if;

  select status into v_status from cobrancas where id = p_cobranca_id for update;
  if v_status is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Cobrança cancelada não recebe termo de ciência';
  end if;

  insert into termos_ciencia_debito (cobranca_id, arquivo_path) values (p_cobranca_id, p_arquivo_path);
end;
$$;

create or replace function rpc_cancelar_cobranca(p_cobranca_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cobranca record;
  v_tem_recebimento boolean;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar cobrança';
  end if;

  select * into v_cobranca from cobrancas where id = p_cobranca_id for update;
  if v_cobranca.id is null then
    raise exception 'Cobrança não encontrada';
  end if;
  if v_cobranca.status <> 'aberta' then
    raise exception 'Somente cobranças em aberto podem ser canceladas';
  end if;

  select exists (
    select 1 from recebimentos r join parcelas p on p.id = r.parcela_id where p.cobranca_id = p_cobranca_id
  ) into v_tem_recebimento;
  if v_tem_recebimento then
    raise exception 'Cobrança com recebimento registrado não pode ser cancelada';
  end if;

  update parcelas set status = 'cancelada' where cobranca_id = p_cobranca_id and status = 'pendente';
  update cobrancas set status = 'cancelada' where id = p_cobranca_id;
end;
$$;

-- ============================================================
-- Estoque/NF (origem: 20260806120200_estoque.sql) — P0-01
-- ============================================================
create or replace function rpc_confirmar_nf_entrada(p_nf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_nf;
  v_item record;
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
  v_novo_custo numeric(12,4);
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para confirmar nota fiscal';
  end if;

  select status into v_status from notas_fiscais_entrada where id = p_nf_id for update;
  if v_status is null then
    raise exception 'Nota fiscal não encontrada';
  end if;
  if v_status <> 'rascunho' then
    raise exception 'Somente notas em rascunho podem ser confirmadas';
  end if;

  for v_item in
    select peca_id, quantidade, valor_unitario from nf_entrada_itens where nf_id = p_nf_id
  loop
    select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
      from pecas where id = v_item.peca_id for update;

    if v_saldo_atual is null then
      raise exception 'Peça % não encontrada', v_item.peca_id;
    end if;

    v_novo_saldo := v_saldo_atual + v_item.quantidade;
    v_novo_custo := ((v_saldo_atual * v_custo_medio) + (v_item.quantidade * v_item.valor_unitario)) / v_novo_saldo;

    update pecas
      set saldo_atual = v_novo_saldo, custo_medio = v_novo_custo
      where id = v_item.peca_id;

    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
    values
      (v_item.peca_id, 'entrada', 'nf_entrada', p_nf_id, v_item.quantidade, v_item.valor_unitario, v_novo_saldo, auth.uid());
  end loop;

  update notas_fiscais_entrada set status = 'confirmada' where id = p_nf_id;
end;
$$;

create or replace function rpc_estornar_nf_entrada(p_nf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_nf;
  v_item record;
  v_saldo_atual numeric(12,3);
  v_custo_medio numeric(12,4);
  v_novo_saldo numeric(12,3);
  v_valor_total_atual numeric(18,4);
  v_novo_custo numeric(12,4);
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para estornar nota fiscal';
  end if;

  select status into v_status from notas_fiscais_entrada where id = p_nf_id for update;
  if v_status is null then
    raise exception 'Nota fiscal não encontrada';
  end if;
  if v_status <> 'confirmada' then
    raise exception 'Somente notas confirmadas podem ser estornadas';
  end if;

  for v_item in
    select peca_id, quantidade, valor_unitario from nf_entrada_itens where nf_id = p_nf_id
  loop
    select saldo_atual, custo_medio into v_saldo_atual, v_custo_medio
      from pecas where id = v_item.peca_id for update;

    v_novo_saldo := v_saldo_atual - v_item.quantidade;
    if v_novo_saldo < 0 then
      raise exception 'Estorno bloqueado: saldo atual da peça % é insuficiente (já consumido por outra movimentação)', v_item.peca_id;
    end if;

    v_valor_total_atual := (v_saldo_atual * v_custo_medio) - (v_item.quantidade * v_item.valor_unitario);
    if v_novo_saldo > 0 then
      v_novo_custo := v_valor_total_atual / v_novo_saldo;
    else
      v_novo_custo := 0;
    end if;

    update pecas
      set saldo_atual = v_novo_saldo, custo_medio = v_novo_custo
      where id = v_item.peca_id;

    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
    values
      (v_item.peca_id, 'estorno_entrada', 'estorno', p_nf_id, v_item.quantidade, v_item.valor_unitario, v_novo_saldo, auth.uid());
  end loop;

  update notas_fiscais_entrada set status = 'estornada' where id = p_nf_id;
end;
$$;

-- ============================================================
-- Venda avulsa (origem: 20260806130300_venda_avulsa.sql) — P0-01
-- ============================================================
create or replace function rpc_criar_venda_avulsa(p_cliente_id uuid, p_itens jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_venda_id uuid;
  v_item jsonb;
  v_peca_id uuid;
  v_quantidade numeric;
  v_valor_unitario numeric;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar venda avulsa';
  end if;

  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    raise exception 'Venda avulsa precisa de ao menos um item';
  end if;

  insert into vendas_avulsas (cliente_id, criado_por)
  values (p_cliente_id, auth.uid())
  returning id into v_venda_id;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    v_peca_id := (v_item ->> 'peca_id')::uuid;
    v_quantidade := (v_item ->> 'quantidade')::numeric;
    v_valor_unitario := (v_item ->> 'valor_unitario')::numeric;

    if v_peca_id is null or v_quantidade is null or v_quantidade <= 0 then
      raise exception 'Item de venda inválido: peça e quantidade (> 0) são obrigatórios';
    end if;

    insert into venda_avulsa_itens (venda_id, peca_id, quantidade, valor_unitario)
    values (v_venda_id, v_peca_id, v_quantidade, coalesce(v_valor_unitario, 0));

    perform rpc_registrar_saida_estoque(v_peca_id, v_quantidade, 'venda_avulsa', v_venda_id);
  end loop;

  return v_venda_id;
end;
$$;

-- ============================================================
-- Ajustes de estoque (origem: 20260807160100_ajustes_estoque.sql) — P0-01
-- (não estava na bateria de testes ao vivo da 1ª auditoria, mas usa o
-- mesmo padrão "current_perfil() not in (...)" — corrigido por consistência
-- e confirmado por leitura de código, não por execução.)
-- ============================================================
create or replace function rpc_registrar_ajuste_estoque(
  p_peca_id uuid,
  p_tipo text,
  p_quantidade numeric,
  p_custo_unitario numeric,
  p_motivo text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ajuste_id uuid;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para ajustar estoque';
  end if;

  if p_tipo not in ('entrada', 'saida') then
    raise exception 'Tipo de ajuste inválido: use entrada ou saida';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Informe o motivo do ajuste (mínimo de 5 caracteres)';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade deve ser positiva';
  end if;

  if p_tipo = 'entrada' and (p_custo_unitario is null or p_custo_unitario < 0) then
    raise exception 'Informe o custo unitário do material recebido';
  end if;

  insert into ajustes_estoque (peca_id, tipo, quantidade, custo_unitario, motivo, criado_por)
  values (
    p_peca_id,
    p_tipo::tipo_movimento_estoque,
    p_quantidade,
    case when p_tipo = 'entrada' then p_custo_unitario else null end,
    p_motivo,
    auth.uid()
  )
  returning id into v_ajuste_id;

  if p_tipo = 'entrada' then
    perform rpc_registrar_entrada_estoque(p_peca_id, p_quantidade, p_custo_unitario, 'ajuste_estoque', v_ajuste_id);
  else
    perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'ajuste_estoque', v_ajuste_id);
  end if;

  return v_ajuste_id;
end;
$$;

-- ============================================================
-- P0-02 / DOC-006: bucket 'comprovantes' não deve ser legível por
-- 'executor' (mesmo critério já usado nas tabelas de financeiro:
-- current_perfil() <> 'executor'). Uma restrição por registro específico
-- (só quem tem relação direta com a OS/cobrança) fica registrada como
-- melhoria P1 no relatório — mudança maior, fora do escopo de hotfix P0.
-- ============================================================
drop policy if exists "comprovantes_select_autenticado" on storage.objects;

create policy "comprovantes_select_gestao" on storage.objects
  for select to authenticated
  using (bucket_id = 'comprovantes' and current_perfil() <> 'executor');
