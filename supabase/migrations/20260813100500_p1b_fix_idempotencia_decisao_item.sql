-- ETAPA 5 (P1-B) — CORRETIVA: achado real durante execução do E2E principal
-- (docs/testing/_etapa5_e2e_parte1_output.txt, cenário M).
--
-- Bug: rpc_decidir_item_orcamento checava `orcamentos.status = 'enviado'`
-- ANTES de checar se a chamada era um retry idempotente do mesmo item já
-- decidido. Isso funciona enquanto o orçamento ainda tem itens pendentes
-- (status continua 'enviado'), mas quebra exatamente no caso mais comum de
-- duplo clique/retry de rede: a decisão que COMPLETA o conjunto de itens
-- (a última) já muda orcamentos.status para aprovado/parcialmente_aprovado/
-- rejeitado (via recalcular_status_orcamento) antes do retry chegar — e o
-- retry, mesmo sendo EXATAMENTE a mesma decisão já registrada, era
-- rejeitado com "Só é possível decidir itens de um orçamento no status
-- enviado", em vez do no-op silencioso esperado (cenário M da matriz de
-- testes). Nunca editar a migration já aplicada (20260813100100) — corrige
-- aqui, reordenando: primeiro trava o item e checa idempotência/conflito,
-- só then valida o status do orçamento (e só quando a decisão é NOVA).
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

  select oi.id, oi.orcamento_id, oi.status_aprovacao into v_item
    from orcamento_itens oi where oi.id = p_orcamento_item_id for update;
  if v_item.id is null then
    raise exception 'Item de orçamento não encontrado';
  end if;

  -- Duplo clique/retry (cenário M): checado ANTES de qualquer validação de
  -- estado do orçamento pai — mesma decisão repetida é sempre um no-op
  -- silencioso, mesmo que o orçamento já tenha fechado o status
  -- (aprovado/parcialmente_aprovado/rejeitado) por causa desta MESMA
  -- decisão ter sido a última pendente.
  if v_item.status_aprovacao = p_decisao then
    return;
  end if;

  -- Decisão conflitante concorrente (cenário N) ou tentativa de reverter uma
  -- decisão já tomada: bloqueado — item decidido é imutável (BR-007/BR-026).
  if v_item.status_aprovacao <> 'pendente' then
    raise exception 'Item já decidido anteriormente (%) — decisão não pode ser revertida/trocada; crie uma nova versão do orçamento para alterar', v_item.status_aprovacao;
  end if;

  -- Só chega aqui para uma decisão REALMENTE NOVA (item ainda pendente) —
  -- aí sim o orçamento precisa estar 'enviado' (não faz sentido decidir item
  -- de orçamento em rascunho, nem depois de substituído).
  select status into v_orc_status from orcamentos where id = v_item.orcamento_id for update;
  if v_orc_status <> 'enviado' then
    raise exception 'Só é possível decidir itens de um orçamento no status enviado (atual: %)', v_orc_status;
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
