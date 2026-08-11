-- ETAPA 5 (P1-B) — APR-002 (aprovação parcial por item), APR-004/005/006
-- (registro estruturado do meio de aprovação), OS-002 (conversão de
-- orçamento parcialmente aprovado). Ver docs/testing/BUSINESS_RULES.md
-- BR-005/BR-006/BR-008/BR-035 (máquina de estados atualizada nesta rodada).
--
-- Decisão de escopo (instrução do dono do projeto, item 1): aprovação
-- parcial é por ITEM INTEIRO nesta etapa, não fração de quantidade dentro
-- do mesmo item — BUSINESS_RULES.md não determina o contrário em nenhum BR
-- existente, então mantém-se a leitura literal do enunciado.

-- ============================================================
-- Colunas novas em orcamento_itens: estado de aprovação por item +
-- registro estruturado do meio (APR-004/005/006). Cada item nasce
-- 'pendente'; nunca é apagado quando rejeitado (BR-026/APR-011).
-- ============================================================
alter table orcamento_itens add column if not exists status_aprovacao text not null default 'pendente'
  constraint orcamento_itens_status_aprovacao_check check (status_aprovacao in ('pendente', 'aprovado', 'rejeitado'));
alter table orcamento_itens add column if not exists meio_aprovacao text
  constraint orcamento_itens_meio_aprovacao_check check (meio_aprovacao in ('sistema', 'email', 'verbal_documentado'));
alter table orcamento_itens add column if not exists autorizado_por_nome text;   -- cliente/responsável que decidiu (distinto do usuário interno)
alter table orcamento_itens add column if not exists autorizado_em timestamptz;
alter table orcamento_itens add column if not exists registrado_por uuid references profiles(id); -- usuário interno que registrou a decisão
alter table orcamento_itens add column if not exists comprovante_path text;     -- evidência (obrigatória para meio = email, ver DOC-005)
alter table orcamento_itens add column if not exists observacao text;

create index if not exists idx_orcamento_itens_status_aprovacao on orcamento_itens (status_aprovacao);

-- ============================================================
-- Backfill: orçamentos já decididos ANTES desta etapa não podem "perder"
-- valor aprovado (a cobrança/execução passam a somar só itens
-- status_aprovacao='aprovado' a partir de agora — ver migration
-- 20260813100500). Sem este backfill, todo orçamento já 'aprovado' na
-- Fase 2/3/P1-A ficaria com 100% dos itens 'pendente' (default da coluna
-- nova) e o valor cobrável cairia pra zero silenciosamente — o que seria
-- uma regressão financeira grave, não uma migração neutra.
-- ============================================================
update orcamento_itens oi
  set status_aprovacao = 'aprovado',
      meio_aprovacao = 'sistema',
      autorizado_por_nome = o.autorizado_por_nome,
      autorizado_em = o.autorizado_em,
      registrado_por = o.criado_por,
      comprovante_path = o.comprovante_path,
      observacao = 'Backfill ETAPA 5 (P1-B): orçamento já estava aprovado (100%) antes da aprovação por item existir.'
  from orcamentos o
  where oi.orcamento_id = o.id and o.status = 'aprovado';

update orcamento_itens oi
  set status_aprovacao = 'rejeitado',
      meio_aprovacao = 'sistema',
      registrado_por = o.criado_por,
      observacao = 'Backfill ETAPA 5 (P1-B): orçamento já estava rejeitado (100%) antes da aprovação por item existir.'
  from orcamentos o
  where oi.orcamento_id = o.id and o.status = 'rejeitado';

-- ============================================================
-- Recalcula o status do orçamento a partir do estado dos itens (máquina de
-- estados determinística, item 2 do pedido / BR-035 atualizada):
--   algum item pendente            -> não mexe (aprovação não concluída)
--   todos aprovados                -> 'aprovado'
--   todos rejeitados               -> 'rejeitado'
--   mistura aprovado + rejeitado   -> 'parcialmente_aprovado'
-- Só atua quando o orçamento está 'enviado' ou já
-- 'parcialmente_aprovado' (uma nova decisão de item pendente pode
-- completar o conjunto) — nunca mexe em rascunho/substituido, e nunca
-- "desfaz" aprovado/rejeitado 100% já fechado (itens já são imutáveis
-- nesse ponto, então não há como isso ser re-executado de qualquer forma,
-- mas o guarda de status fica explícito por defesa em profundidade).
-- ============================================================
create or replace function recalcular_status_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_orcamento;
  v_total int;
  v_pendentes int;
  v_aprovados int;
  v_rejeitados int;
  v_novo status_orcamento;
begin
  select status into v_status from orcamentos where id = p_orcamento_id for update;
  if v_status is null or v_status not in ('enviado', 'parcialmente_aprovado') then
    return;
  end if;

  select count(*),
         count(*) filter (where status_aprovacao = 'pendente'),
         count(*) filter (where status_aprovacao = 'aprovado'),
         count(*) filter (where status_aprovacao = 'rejeitado')
    into v_total, v_pendentes, v_aprovados, v_rejeitados
    from orcamento_itens where orcamento_id = p_orcamento_id;

  if v_total = 0 or v_pendentes > 0 then
    return; -- aprovação não considerada concluída enquanto houver item sem decisão
  end if;

  if v_aprovados = v_total then
    v_novo := 'aprovado';
  elsif v_rejeitados = v_total then
    v_novo := 'rejeitado';
  else
    v_novo := 'parcialmente_aprovado';
  end if;

  if v_novo is distinct from v_status then
    update orcamentos set status = v_novo where id = p_orcamento_id;
  end if;
end;
$$;

revoke execute on function recalcular_status_orcamento(uuid) from public, anon, authenticated;

-- ============================================================
-- rpc_decidir_item_orcamento: decisão POR ITEM, com registro estruturado do
-- meio de aprovação (APR-004/005/006). Idempotente para retry do MESMO
-- clique (cenário M) e bloqueia decisão conflitante concorrente (cenário N)
-- — ambos resolvidos pelo lock FOR UPDATE do item + checagem de estado
-- atual antes de escrever.
-- ============================================================
create or replace function rpc_decidir_item_orcamento(
  p_orcamento_item_id uuid,
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
  v_item record;
  v_orc_status status_orcamento;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar decisão de item de orçamento';
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

  select oi.id, oi.orcamento_id, oi.status_aprovacao into v_item
    from orcamento_itens oi where oi.id = p_orcamento_item_id for update;
  if v_item.id is null then
    raise exception 'Item de orçamento não encontrado';
  end if;

  select status into v_orc_status from orcamentos where id = v_item.orcamento_id for update;
  if v_orc_status <> 'enviado' then
    raise exception 'Só é possível decidir itens de um orçamento no status enviado (atual: %)', v_orc_status;
  end if;

  -- Duplo clique/retry (cenário M): mesma decisão repetida é idempotente, não
  -- gera novo evento de auditoria nem falha.
  if v_item.status_aprovacao = p_decisao then
    return;
  end if;

  -- Decisão conflitante concorrente (cenário N) ou tentativa de reverter uma
  -- decisão já tomada: bloqueado — item decidido é imutável (BR-007/BR-026),
  -- alteração exige nova versão do orçamento (rpc_criar_versao_orcamento).
  if v_item.status_aprovacao <> 'pendente' then
    raise exception 'Item já decidido anteriormente (%) — decisão não pode ser revertida/trocada; crie uma nova versão do orçamento para alterar', v_item.status_aprovacao;
  end if;

  update orcamento_itens
    set status_aprovacao = p_decisao,
        meio_aprovacao = p_meio_aprovacao,
        autorizado_por_nome = p_autorizado_por_nome,
        autorizado_em = now(),
        registrado_por = auth.uid(),
        comprovante_path = p_comprovante_path,
        observacao = p_observacao
    where id = p_orcamento_item_id;

  perform registrar_auditoria('orcamento_itens', p_orcamento_item_id, 'decisao_item_orcamento',
    jsonb_build_object('status_aprovacao', 'pendente'),
    jsonb_build_object('status_aprovacao', p_decisao, 'meio_aprovacao', p_meio_aprovacao, 'autorizado_por_nome', p_autorizado_por_nome),
    p_observacao);

  perform recalcular_status_orcamento(v_item.orcamento_id);
end;
$$;

-- ============================================================
-- rpc_aprovar_orcamento / rpc_rejeitar_orcamento (já existiam desde a Fase
-- 2): viram wrappers de conveniência para os cenários 100% aprovado / 100%
-- rejeitado — decidem TODOS os itens ainda pendentes de uma vez, registrando
-- meio_aprovacao='sistema' (ação via botão único do sistema, sem granularidade
-- por item). Preserva a assinatura antiga (mesmo parâmetro), então nenhum
-- chamador existente (frontend/pgTAP) quebra. Continua exigindo autorização
-- de cliente externo (nome do orçamento) antes de aprovar, como sempre foi.
-- ============================================================
create or replace function rpc_aprovar_orcamento(p_orcamento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_tipo_cliente tipo_cliente;
  v_item record;
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

  for v_item in select id from orcamento_itens where orcamento_id = p_orcamento_id and status_aprovacao = 'pendente'
  loop
    update orcamento_itens
      set status_aprovacao = 'aprovado',
          meio_aprovacao = 'sistema',
          autorizado_por_nome = coalesce(v_orc.autorizado_por_nome, 'Aprovação integral via sistema'),
          autorizado_em = now(),
          registrado_por = auth.uid()
      where id = v_item.id;
    perform registrar_auditoria('orcamento_itens', v_item.id, 'decisao_item_orcamento',
      jsonb_build_object('status_aprovacao', 'pendente'),
      jsonb_build_object('status_aprovacao', 'aprovado', 'meio_aprovacao', 'sistema'), 'Aprovação integral (rpc_aprovar_orcamento)');
  end loop;

  perform recalcular_status_orcamento(p_orcamento_id);

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
  v_item record;
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

  for v_item in select id from orcamento_itens where orcamento_id = p_orcamento_id and status_aprovacao = 'pendente'
  loop
    update orcamento_itens
      set status_aprovacao = 'rejeitado',
          meio_aprovacao = 'sistema',
          autorizado_em = now(),
          registrado_por = auth.uid()
      where id = v_item.id;
    perform registrar_auditoria('orcamento_itens', v_item.id, 'decisao_item_orcamento',
      jsonb_build_object('status_aprovacao', 'pendente'),
      jsonb_build_object('status_aprovacao', 'rejeitado', 'meio_aprovacao', 'sistema'), 'Rejeição integral (rpc_rejeitar_orcamento)');
  end loop;

  perform recalcular_status_orcamento(p_orcamento_id);
end;
$$;

-- ============================================================
-- OS-002: rpc_criar_os passa a aceitar orçamento 'aprovado' OU
-- 'parcialmente_aprovado'. Itens rejeitados nunca entram em execução/baixa/
-- cobrança — isso já é garantido pelas RPCs de estoque/conclusão/financeiro
-- (migrations seguintes desta etapa), não pela conversão em si: a OS mantém
-- vínculo com o ORÇAMENTO inteiro (orcamento_id), e a elegibilidade real é
-- sempre decidida item a item nas RPCs downstream — igual ao desenho já
-- existente desde o P1-A (EST-004).
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
  v_tem_item_aprovado boolean;
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
    if v_orc.status not in ('aprovado', 'parcialmente_aprovado') then
      raise exception 'Orçamento precisa estar aprovado ou parcialmente aprovado para gerar OS (status atual: %)', v_orc.status;
    end if;
    if v_orc.veiculo_id <> p_veiculo_id then
      raise exception 'Orçamento não pertence ao veículo informado';
    end if;

    select exists (select 1 from orcamento_itens where orcamento_id = p_orcamento_id and status_aprovacao = 'aprovado')
      into v_tem_item_aprovado;
    if not v_tem_item_aprovado then
      raise exception 'Orçamento não tem nenhum item aprovado — nada elegível para execução';
    end if;

    -- Decisão de negócio #1 (P1-A, BR-008): nunca mais de uma OS NÃO
    -- CANCELADA por orçamento, independente do tipo.
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
