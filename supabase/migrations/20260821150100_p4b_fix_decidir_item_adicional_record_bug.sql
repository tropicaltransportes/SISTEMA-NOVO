-- ETAPA OS-ESCOPO-04 (fix) — rpc_decidir_item_os_adicional, redefinida em
-- 20260821150000_p4_os_escopo04.sql, atribuía direto em campos de um
-- "record" ainda não populado (v_item.id, v_item.adicional_id, ...) — isso
-- não é permitido em plpgsql, um record só ganha estrutura a partir de um
-- SELECT INTO de linha inteira. Achado rodando a suíte pgTAP
-- (110_documento_final_os.sql): "record v_item is not assigned yet".
-- Mesma classe de bug já corrigida antes em rpc_baixar_peca_os (ver
-- 20260812098000_p1a_fix_baixar_peca_record_bug.sql) — desta vez trocando
-- os campos do record por variáveis escalares dedicadas, em vez de tentar
-- popular um record parcialmente.
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
