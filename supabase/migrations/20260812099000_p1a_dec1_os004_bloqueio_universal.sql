-- ETAPA 4 (P1-A) — Decisão de negócio #1 (OS-004), achado NOVO desta rodada
-- descoberto por execução real ao formalizar/testar a regra (não estava
-- coberto pela rodada anterior): o bloqueio de reconversão duplicada
-- (P0-03, ver 20260810160000_p0_correcoes_criticas.sql) só existia DENTRO
-- do bloco `if p_tipo = 'externa' then` — ou seja, uma OS INTERNA vinculada
-- a um orçamento (combinação válida no schema: orcamento_id é opcional e
-- não restrito por tipo, só `externa` que EXIGE) não tinha proteção
-- nenhuma. Confirmado por execução real, ver
-- docs/testing/_etapa4_dec1_os004_reconversao_output.txt, passo 2: uma 2ª
-- OS interna foi criada com sucesso (HTTP 200) para o mesmo orçamento,
-- enquanto a 1ª OS interna ainda estava ativa — deveria ter sido bloqueada.
--
-- Regra formalizada (ver docs/testing/BUSINESS_RULES.md, BR-008 atualizada):
-- nunca pode existir mais de uma OS NÃO CANCELADA para o mesmo orçamento,
-- independente do tipo (interna/externa). A checagem agora roda sempre que
-- p_orcamento_id não é nulo, não só quando p_tipo = 'externa'.
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
    -- Decisão de negócio #1 (OS-004, ETAPA 4): nunca mais de uma OS NÃO
    -- CANCELADA por orçamento, independente do tipo. OS cancelada libera o
    -- orçamento para nova conversão; histórico de todas as OS é preservado
    -- (nunca apagado/ocultado — a checagem só olha status, nunca deleta nada).
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
