-- ETAPA 6 (P1-C) — correção cosmética encontrada na execução real do E2E
-- externo com desconto (item 17): a mensagem de erro de teto excedido em
-- rpc_aplicar_desconto_orcamento usava `%.2f%%` no RAISE — PL/pgSQL RAISE
-- só suporta `%` como placeholder posicional (sem largura/precisão estilo
-- printf), então ".2f" vazava como texto literal na mensagem (ex.:
-- "19.9993.2f%" em vez de "19.99%"). Bloqueio em si sempre funcionou
-- corretamente (HTTP 400, negócio correto) — só o texto da mensagem estava
-- malformado. Corrige arredondando antes de interpolar e usando `%%` só
-- para o símbolo de porcentagem literal.
create or replace function rpc_aplicar_desconto_orcamento(
  p_orcamento_id uuid,
  p_percentual numeric default null,
  p_valor numeric default null,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc record;
  v_config desconto_config;
  v_bruto numeric(12,2);
  v_desconto numeric(12,2);
  v_percentual_efetivo numeric(7,4);
  v_item record;
  v_restante numeric(12,2);
  v_rateado numeric(12,2);
  v_qtd_itens int;
  v_i int := 0;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para conceder desconto';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do desconto é obrigatório (mínimo de 5 caracteres)';
  end if;
  if (p_percentual is not null and p_valor is not null) or (p_percentual is null and p_valor is null) then
    raise exception 'Informe percentual OU valor de desconto, nunca os dois nem nenhum';
  end if;

  select * into v_orc from orcamentos where id = p_orcamento_id for update;
  if v_orc.id is null then
    raise exception 'Orçamento não encontrado';
  end if;
  if v_orc.status <> 'rascunho' then
    raise exception 'Desconto só pode ser aplicado com o orçamento em rascunho — orçamento já enviado/aprovado exige nova versão (rpc_criar_versao_orcamento) para alterar valor comercial já apresentado ao cliente';
  end if;

  select coalesce(sum(valor_total), 0) into v_bruto from orcamento_itens where orcamento_id = p_orcamento_id;
  if v_bruto <= 0 then
    raise exception 'Orçamento sem itens (ou valor bruto zerado) — nada para aplicar desconto';
  end if;

  if p_valor is not null then
    if p_valor < 0 then
      raise exception 'Valor de desconto inválido';
    end if;
    v_desconto := p_valor;
  else
    if p_percentual < 0 or p_percentual > 100 then
      raise exception 'Percentual de desconto inválido (0 a 100)';
    end if;
    v_desconto := round(v_bruto * p_percentual / 100, 2);
  end if;

  if v_desconto > v_bruto then
    raise exception 'Desconto (R$ %) não pode exceder o valor bruto do orçamento (R$ %) — valor final nunca pode ficar negativo', v_desconto, v_bruto;
  end if;

  select * into v_config from desconto_config_vigente();
  if v_desconto > 0 then
    if v_config.id is null or not v_config.habilitado then
      raise exception 'Desconto está desabilitado na configuração vigente';
    end if;
    v_percentual_efetivo := round((v_desconto / v_bruto) * 100, 2);
    if v_percentual_efetivo > v_config.percentual_maximo then
      raise exception 'Desconto solicitado (% %%) excede o teto configurado (% %%)', v_percentual_efetivo, v_config.percentual_maximo;
    end if;
  end if;

  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  v_restante := v_desconto;
  for v_item in select id, valor_total from orcamento_itens where orcamento_id = p_orcamento_id order by id
  loop
    v_i := v_i + 1;
    if v_i = v_qtd_itens then
      v_rateado := v_restante;
    else
      v_rateado := round(v_item.valor_total / v_bruto * v_desconto, 2);
    end if;
    v_restante := v_restante - v_rateado;
    update orcamento_itens set desconto_rateado = v_rateado where id = v_item.id;
  end loop;

  update orcamentos
    set valor_bruto = v_bruto,
        desconto_valor = v_desconto,
        desconto_percentual = round((v_desconto / v_bruto) * 100, 2),
        desconto_motivo = p_motivo,
        desconto_por = auth.uid(),
        desconto_em = now(),
        valor_liquido = v_bruto - v_desconto,
        valor_total = v_bruto - v_desconto
    where id = p_orcamento_id;

  perform registrar_auditoria('orcamentos', p_orcamento_id, 'aplicar_desconto',
    jsonb_build_object('desconto_valor', v_orc.desconto_valor),
    jsonb_build_object('desconto_valor', v_desconto, 'desconto_percentual', round((v_desconto / v_bruto) * 100, 2)),
    p_motivo);
end;
$$;
