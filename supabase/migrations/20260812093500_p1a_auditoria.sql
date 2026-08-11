-- ETAPA 4 (P1-A) — item H: AUD-001/002/003, trilha de auditoria para
-- eventos críticos (BR-027). Tabela append-only: sem policy de UPDATE/DELETE
-- para nenhum papel, sem GRANT de INSERT direto para authenticated/anon —
-- a única via de escrita é a função registrar_auditoria() (SECURITY
-- DEFINER), chamada de dentro de outras RPCs/triggers já autenticados/
-- validados, nunca exposta como RPC pública standalone.
create table auditoria_eventos (
  id uuid primary key default gen_random_uuid(),
  entidade text not null,
  entidade_id uuid not null,
  acao text not null,
  usuario_id uuid references profiles(id),
  valor_anterior jsonb,
  valor_novo jsonb,
  motivo text,
  criado_em timestamptz not null default now()
);

create index idx_auditoria_entidade on auditoria_eventos (entidade, entidade_id);
create index idx_auditoria_criado_em on auditoria_eventos (criado_em);

alter table auditoria_eventos enable row level security;

-- Leitura: mesmo critério do módulo financeiro/documentos (não-executor) —
-- auditoria expõe detalhe operacional/administrativo sensível.
create policy "auditoria_select_gestao" on auditoria_eventos
  for select
  using (current_perfil() <> 'executor');

-- Nenhuma policy de INSERT/UPDATE/DELETE: authenticated/anon não conseguem
-- escrever nesta tabela de jeito nenhum, nem por engano de um GRANT futuro
-- (RLS sem policy de escrita = nega por padrão). A função abaixo roda como
-- dono (SECURITY DEFINER) e contorna a RLS para inserir.
revoke insert, update, delete on auditoria_eventos from authenticated, anon;

create or replace function registrar_auditoria(
  p_entidade text,
  p_entidade_id uuid,
  p_acao text,
  p_valor_anterior jsonb default null,
  p_valor_novo jsonb default null,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into auditoria_eventos (entidade, entidade_id, acao, usuario_id, valor_anterior, valor_novo, motivo)
  values (p_entidade, p_entidade_id, p_acao, auth.uid(), p_valor_anterior, p_valor_novo, p_motivo);
end;
$$;

comment on function registrar_auditoria is
  'Único ponto de escrita em auditoria_eventos. Chamada internamente por triggers e RPCs — nunca exposta diretamente como RPC de escrita livre para o cliente (ver GRANT/REVOKE abaixo). ETAPA 4 P1-A, item H (AUD-001/002/003).';

-- Não expõe a função de escrita como RPC livre: só quem já tem EXECUTE nas
-- RPCs/triggers internos que a chamam (roda como SECURITY DEFINER, então
-- mesmo que alguém chamasse via PostgREST, o efeito é só inserir uma linha
-- de auditoria com o próprio auth.uid() — não há como falsificar
-- valor_anterior de forma que afete dados reais, mas por disciplina de design
-- (mesmo padrão de rpc_registrar_saida_estoque) revoga de authenticated/anon.
revoke execute on function registrar_auditoria(text, uuid, text, jsonb, jsonb, text) from public, anon, authenticated;

-- ============================================================
-- Triggers automáticas: cobrem "mudança de status da OS" (inclui
-- cancelamento e liberação, que são só valores de status), "alteração de
-- preço" e "alteração administrativa crítica" (perfil/ativo de usuário).
-- ============================================================

-- AUD-002/AUD-003: qualquer mudança de status em ordens_servico (cobre
-- conclusão, liberação, cancelamento e as transições normais).
create or replace function audit_trg_os_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    perform registrar_auditoria('ordens_servico', new.id, 'mudanca_status',
      jsonb_build_object('status', old.status), jsonb_build_object('status', new.status), null);
  end if;
  return new;
end;
$$;

create trigger trg_audit_os_status
  after update on ordens_servico
  for each row execute function audit_trg_os_status();

-- AUD-001: alteração de preço em item de orçamento (única via de escrita de
-- preço no sistema é UPDATE direto de orcamento_itens.valor_unitario,
-- restrito pela RLS a rascunho — ver 20260806130100_orcamentos.sql. Trigger
-- captura o evento independentemente do caminho de escrita, mais robusto do
-- que instrumentar cada chamador).
create or replace function audit_trg_orcamento_item_preco()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.valor_unitario is distinct from old.valor_unitario then
    perform registrar_auditoria('orcamento_itens', new.id, 'alteracao_preco',
      jsonb_build_object('valor_unitario', old.valor_unitario), jsonb_build_object('valor_unitario', new.valor_unitario), null);
  end if;
  return new;
end;
$$;

create trigger trg_audit_orcamento_item_preco
  after update on orcamento_itens
  for each row execute function audit_trg_orcamento_item_preco();

-- Alteração administrativa crítica: perfil ou ativo de um usuário mudando
-- (só administrador_tecnico consegue, via profiles_update_admin — ver
-- 20260806120000_profiles.sql).
create or replace function audit_trg_profile_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.perfil is distinct from old.perfil or new.ativo is distinct from old.ativo then
    perform registrar_auditoria('profiles', new.id, 'alteracao_administrativa',
      jsonb_build_object('perfil', old.perfil, 'ativo', old.ativo),
      jsonb_build_object('perfil', new.perfil, 'ativo', new.ativo), null);
  end if;
  return new;
end;
$$;

create trigger trg_audit_profile_admin
  after update on profiles
  for each row execute function audit_trg_profile_admin();

-- Estorno: todo INSERT de tipo 'estorno_saida'/'estorno_entrada' já é, por
-- si só, um lançamento compensatório auditável no ledger de estoque
-- (BR-016) — a trigger só espelha o evento em auditoria_eventos para busca
-- cruzada unificada (mesma tabela de auditoria de todo o resto do sistema).
create or replace function audit_trg_estorno_estoque()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tipo in ('estorno_saida', 'estorno_entrada') then
    perform registrar_auditoria('estoque_movimentos', new.id, new.tipo::text,
      jsonb_build_object('estornado_de', new.estornado_de),
      jsonb_build_object('peca_id', new.peca_id, 'quantidade', new.quantidade, 'saldo_resultante', new.saldo_resultante), null);
  end if;
  return new;
end;
$$;

create trigger trg_audit_estorno_estoque
  after insert on estoque_movimentos
  for each row execute function audit_trg_estorno_estoque();
