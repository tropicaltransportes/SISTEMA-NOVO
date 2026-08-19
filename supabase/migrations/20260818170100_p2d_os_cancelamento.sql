-- FEATURE-OS-CANCELAMENTO-01 (parte 2/3) — cancelamento formal de OS.
-- Ver docs/testing/BUSINESS_RULES.md BR-049/BR-050.
--
-- rpc_transicionar_os deixa de aceitar 'cancelada' (RPC dedicada abaixo,
-- que trata motivo, apontamentos, adicionais, estoque e garantia).
-- rpc_cancelar_os_adicional é refatorada para delegar a um helper interno
-- (cancelar_os_adicional_interno), reaproveitado por rpc_cancelar_os —
-- nunca duplica a lógica de fechamento de adicional 'aguardando_aprovacao'.

alter table ordens_servico
  add column cancelado_em timestamptz,
  add column cancelado_por uuid references profiles(id),
  add column cancelamento_motivo text;

-- ============================================================
-- Helper interno: núcleo de rpc_cancelar_os_adicional, sem checagem de
-- perfil própria (quem chama já validou). Corpo idêntico ao da RPC
-- original de 20260813100600_p1b_cancelar_adicional.sql, só extraído para
-- ser reaproveitado por rpc_cancelar_os sem duplicar comportamento.
-- ============================================================
create or replace function cancelar_os_adicional_interno(p_adicional_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adicional record;
  v_item record;
begin
  select id, os_id, status into v_adicional from os_adicionais where id = p_adicional_id for update;
  if v_adicional.id is null then
    raise exception 'Adicional não encontrado';
  end if;
  if v_adicional.status <> 'aguardando_aprovacao' then
    raise exception 'Só é possível cancelar um adicional ainda aguardando aprovação (status atual: %) — itens já decididos individualmente devem ser tratados item a item', v_adicional.status;
  end if;

  for v_item in select id from os_adicional_itens where adicional_id = p_adicional_id and status_aprovacao = 'pendente'
  loop
    update os_adicional_itens
      set status_aprovacao = 'rejeitado',
          meio_aprovacao = 'sistema',
          autorizado_por_nome = 'Cancelamento do adicional',
          autorizado_em = now(),
          registrado_por = auth.uid(),
          observacao = p_motivo
      where id = v_item.id;
    perform registrar_auditoria('os_adicional_itens', v_item.id, 'cancelar_item_adicional_por_cancelamento_cabecalho',
      jsonb_build_object('status_aprovacao', 'pendente'),
      jsonb_build_object('status_aprovacao', 'rejeitado'), p_motivo);
  end loop;

  perform registrar_auditoria('os_adicionais', p_adicional_id, 'cancelar_adicional', null,
    jsonb_build_object('os_id', v_adicional.os_id), p_motivo);

  -- Cancelamento sempre resolve o cabeçalho como 'rejeitado' — inclusive o
  -- caso de adicional sem nenhum item, que recalcular_status_os_adicional
  -- trataria como 'aguardando_aprovacao' (regra pensada para "ainda não
  -- decidido", não para "cancelado"); por isso a transição é explícita.
  update os_adicionais set status = 'rejeitado' where id = p_adicional_id;
end;
$$;

revoke execute on function cancelar_os_adicional_interno(uuid, text) from public, anon, authenticated;

-- RPC pública passa a delegar ao helper — comportamento idêntico ao de
-- antes desta migration.
create or replace function rpc_cancelar_os_adicional(p_adicional_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar adicional';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Cancelar um adicional exige motivo (mínimo de 5 caracteres) — ação auditável';
  end if;
  perform cancelar_os_adicional_interno(p_adicional_id, p_motivo);
end;
$$;

-- ============================================================
-- rpc_transicionar_os — deixa de aceitar 'cancelada'. Corpo reproduzido de
-- 20260810160000_p0_correcoes_criticas.sql:447-502, removendo as 3 tuplas
-- de cancelamento do array v_permitido e o loop de estorno associado (que
-- migrou para rpc_cancelar_os), e acrescentando a mensagem de
-- redirecionamento.
-- ============================================================
create or replace function rpc_transicionar_os(p_os_id uuid, p_novo_status status_os)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_permitido boolean := false;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para transicionar OS';
  end if;

  if p_novo_status in ('concluida', 'liberada', 'reaberta_garantia') then
    raise exception 'Use a RPC específica para esta transição (rpc_concluir_os / rpc_liberar_os)';
  end if;
  if p_novo_status = 'cancelada' then
    raise exception 'Use rpc_cancelar_os para cancelar — exige motivo e trata apontamentos, adicionais, estoque e garantia';
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
    ('em_execucao', 'aguardando_teste')
  );

  if not v_permitido then
    raise exception 'Transição % -> % não é permitida', v_status, p_novo_status;
  end if;

  update ordens_servico set status = p_novo_status where id = p_os_id;
end;
$$;

-- ============================================================
-- rpc_cancelar_os — cancelamento formal (BR-049/BR-050). Permitido de
-- aberta/em_diagnostico/aguardando_aprovacao/em_execucao/aguardando_teste/
-- concluida. Bloqueado (idempotência) se já cancelada; bloqueado se
-- liberada/reaberta_garantia; bloqueado por recebimento confirmado ou
-- cobrança ativa vinculada (cancelamento de cobrança é fluxo manual
-- separado, gate de perfil próprio suporte_administrativo/
-- administrador_tecnico — rpc_cancelar_os nunca cancela cobrança "por
-- tabela"). Transação única (raise = rollback automático): encerra
-- apontamentos abertos, fecha adicionais aguardando aprovação, estorna
-- estoque não estornado (peça de orçamento e de adicional), reabre item de
-- mão de obra parcial para pendente, reverte a OS origem para liberada se
-- esta for uma OS de garantia, e só então transiciona para cancelada.
-- ============================================================
create or replace function rpc_cancelar_os(p_os_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_mov_id uuid;
  v_adicional record;
  v_exec record;
  v_tem_recebimento boolean;
  v_tem_cobranca_ativa boolean;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar OS';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do cancelamento é obrigatório (mínimo de 5 caracteres) — ação auditável';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  if v_os.deleted_at is not null then
    raise exception 'OS excluída não pode ser cancelada';
  end if;

  if v_os.status = 'cancelada' then
    raise exception 'Esta OS já foi cancelada em %', v_os.cancelado_em;
  end if;

  if v_os.status in ('liberada', 'reaberta_garantia') then
    raise exception 'OS já liberada/encerrada não pode ser cancelada (status atual: %)', v_os.status;
  end if;

  -- Recebimento confirmado nunca é desfeito por cancelamento de OS.
  select exists (
    select 1
    from cobranca_origens co
    join parcelas p on p.cobranca_id = co.cobranca_id
    join recebimentos r on r.parcela_id = p.id
    where co.os_id = p_os_id
  ) into v_tem_recebimento;
  if v_tem_recebimento then
    raise exception 'Esta OS possui recebimento confirmado e exige tratamento financeiro antes do cancelamento';
  end if;

  -- Cobrança ativa vinculada: cancele a cobrança primeiro (fluxo dedicado,
  -- gate de perfil próprio) — rpc_cancelar_os nunca cancela cobrança "por
  -- tabela".
  select exists (
    select 1 from cobranca_origens co
    join cobrancas c on c.id = co.cobranca_id
    where co.os_id = p_os_id and c.status <> 'cancelada'
  ) into v_tem_cobranca_ativa;
  if v_tem_cobranca_ativa then
    raise exception 'Esta OS possui cobrança ativa vinculada — cancele a cobrança primeiro e só então cancele a OS';
  end if;

  -- Defesa em profundidade (já é estruturalmente impossível dado o
  -- bloqueio de liberada/reaberta_garantia acima — mantido por clareza).
  if exists (select 1 from ordens_servico where os_origem_id = p_os_id) then
    raise exception 'Esta OS já gerou uma OS de garantia — não pode ser cancelada';
  end if;

  -- 1) Encerra apontamentos em aberto.
  for v_exec in select id from os_executores where os_id = p_os_id and fim is null
  loop
    update os_executores set fim = now() where id = v_exec.id;
    perform registrar_auditoria('os_executores', v_exec.id, 'APONTAMENTO_ENCERRADO_POR_CANCELAMENTO',
      jsonb_build_object('fim', null), jsonb_build_object('fim', now()), p_motivo);
  end loop;

  -- 2) Adicionais ainda aguardando decisão fecham formalmente (helper
  -- reaproveitado de rpc_cancelar_os_adicional).
  for v_adicional in select id from os_adicionais where os_id = p_os_id and status = 'aguardando_aprovacao'
  loop
    perform cancelar_os_adicional_interno(v_adicional.id, p_motivo);
    perform registrar_auditoria('os_adicionais', v_adicional.id, 'ADICIONAL_CANCELADO_POR_OS', null,
      jsonb_build_object('motivo', 'cancelamento da OS'), p_motivo);
  end loop;

  -- 3) Estorna toda saída de estoque não estornada da OS (peça de
  -- orçamento original e de adicional — mesma origem_tipo/origem_id). O
  -- estorno já resincroniza sozinho orcamento_itens.execucao_status e
  -- os_adicional_itens.execucao_status via
  -- estornar_saida_estoque_interno -> sincronizar_execucao_item_*.
  for v_mov_id in
    select em.id from estoque_movimentos em
    where em.origem_tipo = 'os' and em.origem_id = p_os_id and em.tipo = 'saida'
      and not exists (select 1 from estoque_movimentos e2 where e2.estornado_de = em.id)
  loop
    perform estornar_saida_estoque_interno(v_mov_id);
  end loop;

  -- 4) Itens de MÃO DE OBRA (sem peça, portanto sem ledger para
  -- resincronizar sozinho): reabre 'parcial' -> 'pendente', espelhando o
  -- que o passo 3 já faz automaticamente do lado de peça. Nunca 'cancelado'
  -- — esse valor é um override manual permanente que travaria a
  -- reconversão do orçamento numa nova OS (ver BR-049).
  if v_os.orcamento_id is not null then
    update orcamento_itens
      set execucao_status = 'pendente'
      where orcamento_id = v_os.orcamento_id
        and peca_id is null
        and status_aprovacao = 'aprovado'
        and execucao_status = 'parcial';
  end if;

  update os_adicional_itens oai
    set execucao_status = 'pendente'
    from os_adicionais a
    where a.id = oai.adicional_id
      and a.os_id = p_os_id
      and oai.peca_id is null
      and oai.status_aprovacao = 'aprovado'
      and oai.execucao_status = 'parcial';

  -- 5) Se esta OS É uma garantia, a OS ORIGEM volta a 'liberada' — sem
  -- isto, cancelar uma garantia aberta por engano prende a origem para
  -- sempre em 'reaberta_garantia' (rpc_criar_os_garantia só roda de novo
  -- em origem com status='liberada', e não existe hoje nenhum outro
  -- caminho de volta).
  if v_os.os_origem_id is not null then
    update ordens_servico
      set status = 'liberada'
      where id = v_os.os_origem_id and status = 'reaberta_garantia';
  end if;

  -- 6) Transição final.
  update ordens_servico
    set status = 'cancelada',
        cancelado_em = now(),
        cancelado_por = auth.uid(),
        cancelamento_motivo = p_motivo
    where id = p_os_id;

  -- audit_trg_os_status grava 'mudanca_status' com motivo sempre null;
  -- este evento explícito carrega o motivo real.
  perform registrar_auditoria('ordens_servico', p_os_id, 'OS_CANCELADA',
    jsonb_build_object('status', v_os.status),
    jsonb_build_object('status', 'cancelada'), p_motivo);
end;
$$;
