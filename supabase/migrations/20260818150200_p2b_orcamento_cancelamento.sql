-- FEATURE-ORCAMENTO-EXCLUSAO-01 (parte 3/3) — cancelamento formal de
-- orçamento pós-rascunho (BR-046).
--
-- Colunas próprias (cancelado_em/cancelado_por/cancelamento_motivo), não só
-- auditoria: espelha desconto_motivo/desconto_por/desconto_em
-- (20260814110200_p1c_desconto_orcamento.sql) porque `orcamentos` é legível
-- por todo perfil ativo (inclusive executor), enquanto auditoria_eventos não
-- é (auditoria_select_gestao exclui executor) — sem essas colunas, um
-- executor olhando um orçamento cancelado nunca veria o motivo.
--
-- Nenhuma outra RPC/RLS precisa mudar por causa do cancelamento. Todo RPC
-- que já grava em `orcamentos` é gated por um allow-list específico de
-- status (rpc_aprovar/rejeitar_orcamento: 'enviado'; rpc_criar_versao_orcamento:
-- 'enviado'/'aprovado'/'rejeitado'; rpc_criar_os: 'aprovado'/'parcialmente_aprovado';
-- rpc_registrar_acrescimo: 'aprovado'; rpc_decidir_item_orcamento:
-- orc.status='enviado') e 'cancelado' nunca entra em nenhum desses
-- allow-lists — confirmado lendo cada corpo antes desta migration. Só
-- rpc_enviar_orcamento e rpc_aplicar_desconto_orcamento aceitavam
-- 'rascunho' diretamente e por isso já foram atualizadas (não por causa do
-- cancelamento, e sim da exclusão de rascunho — ver 20260818150000) com a
-- guarda de deleted_at; um orçamento nunca é 'rascunho' e 'cancelado' ao
-- mesmo tempo, então essas duas RPCs não precisam de guarda extra aqui.

alter table orcamentos
  add column cancelado_em timestamptz,
  add column cancelado_por uuid references profiles(id),
  add column cancelamento_motivo text;

-- ============================================================
-- rpc_cancelar_orcamento — cancelamento formal (BR-046). Só orçamento que já
-- saiu do rascunho, sem OS ativa vinculada (mesmo predicado de
-- BR-008/OS-004/BR-045), motivo obrigatório, idempotente.
-- ============================================================
create or replace function rpc_cancelar_orcamento(
  p_orcamento_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cancelar orçamento';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do cancelamento é obrigatório (mínimo de 5 caracteres)';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;

  if v_orc.status = 'cancelado' then
    raise exception 'Este orçamento já foi cancelado em %', v_orc.cancelado_em;
  end if;

  if v_orc.status not in ('enviado', 'aprovado', 'rejeitado', 'parcialmente_aprovado') then
    raise exception 'Somente orçamentos enviados, aprovados, rejeitados ou parcialmente aprovados podem ser cancelados — use Excluir Rascunho para orçamento em rascunho (atual: %)', v_orc.status;
  end if;

  if exists (
    select 1 from ordens_servico os
    where os.orcamento_id = p_orcamento_id and os.status <> 'cancelada'
  ) then
    raise exception 'Este orçamento já foi convertido em uma OS ativa — não pode ser cancelado';
  end if;

  update orcamentos
    set status = 'cancelado',
        cancelado_em = now(),
        cancelado_por = auth.uid(),
        cancelamento_motivo = p_motivo
    where id = p_orcamento_id;

  perform registrar_auditoria('orcamentos', p_orcamento_id, 'ORCAMENTO_CANCELADO',
    jsonb_build_object('status', v_orc.status),
    jsonb_build_object('status', 'cancelado'),
    p_motivo);
end;
$$;
