-- ETAPA 3 de homologação (2026-08-11) — corrige os 2 achados P0 reabertos
-- nesta rodada, ambos confirmados por execução real e limpa ANTES desta
-- migration (ver docs/testing/_etapa3_prefix_output.txt):
--
--   AUT-004: profiles.ativo=false não bloqueava NENHUMA operação. current_perfil()
--     só lia profiles.perfil, ignorando profiles.ativo. Como tem_perfil() (fix
--     P0-01) e toda RLS do projeto dependem de current_perfil(), a correção
--     mínima e abrangente é fazer current_perfil() retornar NULL também para
--     usuário inativo — mesma técnica "fail closed" já usada pelo P0-01 para
--     chamador sem sessão. Isso propaga automaticamente para: tem_perfil()
--     (todas as RPCs já migradas), toda policy RLS que usa current_perfil()
--     diretamente, e as RPCs mais antigas que ainda comparam com
--     "current_perfil() not in (...)" (essas também passam a negar, porque
--     NULL NOT IN (...) é NULL, tratado como falso pelo IF do plpgsql —
--     mesmo mecanismo de falha-fechada do achado P0-01 original, agora a
--     nosso favor).
--     Evidência do bug: docs/testing/_etapa3_prefix_output.txt, bloco AUT-004
--     — usuário teste.inativo (ativo=false) executou rpc_baixar_peca_os com
--     sucesso (HTTP 204) numa OS/peça exclusivas, nunca usadas antes.
--
--   EST-009: a proteção P0-04 (janela de dedup de 5s) não é idempotência
--     persistente — repetir a MESMA baixa lógica depois de >5s duplicava a
--     saída normalmente. Substituímos/complementamos por um mecanismo
--     persistente real: idempotency_key opcional fornecida pelo chamador,
--     gravada no próprio movimento e protegida por unique index parcial —
--     válida para sempre (não expira), e também resolve corretamente
--     chamadas concorrentes idênticas (a trava FOR UPDATE já existente na
--     peça serializa as duas chamadas; a segunda, ao ser liberada, encontra
--     o movimento já gravado com a mesma chave e é bloqueada). A janela de
--     5s é mantida como fallback best-effort só para chamadas SEM chave
--     (compatibilidade retroativa com qualquer caller antigo) — mas deixa de
--     ser a única linha de defesa.
--     Evidência do bug: docs/testing/_etapa3_prefix_output.txt, bloco
--     EST-009 — saldo caiu 30 -> 26 (baixa original) -> bloqueado (retry
--     imediato) -> 26 -> 22 (retry após 6s, MESMA operação lógica, duplicou).

-- ============================================================
-- AUT-004: current_perfil() passa a falhar fechado para usuário inativo
-- ============================================================
create or replace function current_perfil()
returns perfil_usuario
language sql
stable
security definer
set search_path = public
as $$
  select perfil from profiles where id = auth.uid() and ativo = true
$$;

comment on function current_perfil is
  'Retorna o perfil do usuário autenticado, ou NULL se: sem sessão, sem linha em profiles, OU profiles.ativo = false. Fail-closed para usuário inativo (ver docs/testing/TEST_REPORT_EXECUTION_03.md, AUT-004) — mesma filosofia do fix P0-01 (tem_perfil) para chamador sem sessão.';

-- ============================================================
-- EST-009: idempotency_key persistente em estoque_movimentos
-- ============================================================
alter table estoque_movimentos add column if not exists idempotency_key uuid;

-- Único por (origem, peça, tipo, chave) quando a chave é informada — retries
-- com a mesma chave nunca geram uma 2ª linha, não importa quanto tempo passe.
create unique index if not exists ux_estoque_mov_idempotency
  on estoque_movimentos (origem_tipo, origem_id, peca_id, tipo, idempotency_key)
  where idempotency_key is not null;

create or replace function rpc_registrar_saida_estoque(
  p_peca_id uuid,
  p_quantidade numeric,
  p_origem_tipo origem_movimento,
  p_origem_id uuid,
  p_idempotency_key uuid default null
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

  -- Trava a linha da peça primeiro: serializa qualquer chamada concorrente
  -- (mesma peça), inclusive duas chamadas idênticas simultâneas com a mesma
  -- idempotency_key — a segunda só prossegue depois que a primeira já
  -- commitou o movimento, e cai no bloqueio abaixo.
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
    raise exception 'Estoque insuficiente para a peça % (saldo % , solicitado %)', p_peca_id, v_saldo_atual, p_quantidade;
  end if;

  update pecas set saldo_atual = v_novo_saldo where id = p_peca_id;

  begin
    insert into estoque_movimentos
      (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por, idempotency_key)
    values
      (p_peca_id, 'saida', p_origem_tipo, p_origem_id, p_quantidade, v_custo_medio, v_novo_saldo, auth.uid(), p_idempotency_key);
  exception when unique_violation then
    -- Defesa em profundidade: se por qualquer motivo o SELECT acima não
    -- pegou a duplicata (ex.: corrida fora do padrão esperado), a unique
    -- index garante que nunca existem 2 movimentos com a mesma chave.
    raise exception 'Operação já processada (idempotency_key % já usada para esta baixa) — nenhuma nova movimentação foi registrada', p_idempotency_key;
  end;
end;
$$;

create or replace function rpc_baixar_peca_os(
  p_os_id uuid,
  p_peca_id uuid,
  p_quantidade numeric,
  p_idempotency_key uuid default null
)
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

  -- Fallback best-effort (só entra em ação quando o caller NÃO informou uma
  -- idempotency_key): mantém a janela de 5s da P0-04 para clientes antigos,
  -- mas essa NÃO é mais a única proteção — quem informar p_idempotency_key
  -- fica protegido de forma definitiva pela unique index, sem depender de
  -- tempo (ver EST-009 em docs/testing/TEST_REPORT_EXECUTION_03.md).
  if p_idempotency_key is null and exists (
    select 1 from estoque_movimentos
    where origem_tipo = 'os' and origem_id = p_os_id and peca_id = p_peca_id
      and tipo = 'saida' and quantidade = p_quantidade
      and criado_em > now() - interval '5 seconds'
  ) then
    raise exception 'Baixa idêntica já registrada nos últimos segundos para esta OS/peça — possível duplo clique';
  end if;

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id, p_idempotency_key);
end;
$$;
