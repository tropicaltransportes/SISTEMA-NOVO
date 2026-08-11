-- ETAPA 6 (P1-C) — Decisão 7 (ORC-007/ORC-008/FIN-003/PEN-007) e item 9
-- (rateio determinístico): desconto estruturado e auditável no orçamento.
--
-- Modelo: orcamentos ganha valor_bruto/desconto_valor/desconto_percentual/
-- valor_liquido (cabeçalho, para leitura/PDF). orcamento_itens ganha
-- desconto_rateado + valor_liquido (coluna gerada) — o desconto é aplicado
-- PROPORCIONALMENTE a cada item (instrução item 9: "preferir aplicar
-- desconto aos itens aos quais ele efetivamente pertence"), com o ÚLTIMO
-- item absorvendo o resíduo de arredondamento, garantindo
-- sum(desconto_rateado) = desconto_valor exatamente (nunca há centavo
-- divergente entre orçamento e a soma dos itens).
--
-- rpc_criar_cobranca (P1-B) já soma orcamento_itens.valor_total (aprovado)
-- para compor a cobrança — passa a somar valor_liquido em vez disso, então
-- o desconto flui automaticamente até a cobrança/PDF sem tocar mais nada.
--
-- Janela de aplicação: só enquanto o orçamento está em 'rascunho' (mesma
-- janela editável de preço/item já existente). Se o orçamento já foi
-- enviado/aprovado, alterar o desconto exige nova versão
-- (rpc_criar_versao_orcamento, já existente desde a Fase 2) — nunca altera
-- silenciosamente um valor comercial já aprovado pelo cliente.

alter table orcamentos add column if not exists valor_bruto numeric(12,2);
alter table orcamentos add column if not exists desconto_percentual numeric(5,2);
alter table orcamentos add column if not exists desconto_valor numeric(12,2) not null default 0;
alter table orcamentos add column if not exists desconto_motivo text;
alter table orcamentos add column if not exists desconto_por uuid references profiles(id);
alter table orcamentos add column if not exists desconto_em timestamptz;
alter table orcamentos add column if not exists valor_liquido numeric(12,2);

-- Backfill: orçamentos existentes nunca tiveram desconto — bruto = líquido = valor_total atual.
update orcamentos set valor_bruto = valor_total, valor_liquido = valor_total where valor_bruto is null;

alter table orcamento_itens add column if not exists desconto_rateado numeric(12,2) not null default 0;
-- Não pode referenciar valor_total (também gerada — Postgres não permite
-- coluna gerada referenciar outra coluna gerada) — repete a mesma expressão
-- base (quantidade * valor_unitario), que é o que valor_total já calcula.
alter table orcamento_itens add column if not exists valor_liquido numeric(12,2) generated always as (quantidade * valor_unitario - desconto_rateado) stored;

-- ============================================================
-- rpc_aplicar_desconto_orcamento: encarregado/administrador_tecnico (mesma
-- autoridade de preço, BR-010/PODE_EDITAR_PRECO), só em orçamento rascunho.
-- Informe percentual OU valor (nunca os dois). Nunca permite valor final
-- negativo. Teto lido de desconto_config_vigente(): desabilitado -> bloqueia
-- qualquer desconto > 0; acima do percentual máximo -> bloqueia.
-- ============================================================
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
    v_percentual_efetivo := (v_desconto / v_bruto) * 100;
    if v_percentual_efetivo > v_config.percentual_maximo then
      raise exception 'Desconto solicitado (%.2f%%) excede o teto configurado (%.2f%%)', v_percentual_efetivo, v_config.percentual_maximo;
    end if;
  end if;

  -- Rateio proporcional determinístico: cada item recebe
  -- round(item.valor_total / bruto * desconto, 2); o ÚLTIMO item (ordenado
  -- por id, ordem estável) recebe o resíduo, garantindo soma exata.
  select count(*) into v_qtd_itens from orcamento_itens where orcamento_id = p_orcamento_id;
  v_restante := v_desconto;
  for v_item in select id, valor_total from orcamento_itens where orcamento_id = p_orcamento_id order by id
  loop
    v_i := v_i + 1;
    if v_i = v_qtd_itens then
      v_rateado := v_restante; -- último item absorve o resíduo de arredondamento
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

-- rpc_criar_cobranca (P1-B) somava orcamento_itens.valor_total para itens
-- aprovados — passa a somar valor_liquido (valor_total - desconto_rateado),
-- para que o desconto concedido no orçamento chegue até a cobrança sem
-- divergência de centavos. Itens de adicional não têm desconto nesta etapa
-- (fora de escopo — adicional já nasce com preço definido pelo encarregado).
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
  v_valor_itens_aprovados numeric(12,2);
  v_valor_adicionais_aprovados numeric(12,2);
  v_valor_acrescimos numeric(12,2);
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

    select coalesce(sum(valor_liquido), 0) into v_valor_itens_aprovados
      from orcamento_itens
      where orcamento_id = v_os.orcamento_id and status_aprovacao = 'aprovado';

    -- item 11 (P1-C): item de adicional formalmente CANCELADO (aprovado mas
    -- dispensado antes de executar) nunca entra na cobrança.
    select coalesce(sum(oai.valor_total), 0) into v_valor_adicionais_aprovados
      from os_adicional_itens oai
      join os_adicionais a on a.id = oai.adicional_id
      where a.os_id = v_os_id and oai.status_aprovacao = 'aprovado' and oai.execucao_status <> 'cancelado';

    select coalesce(sum(a.valor_acrescimo), 0) into v_valor_acrescimos
      from orcamento_acrescimos a where a.orcamento_id = v_os.orcamento_id;

    v_valor_total := v_valor_total + v_valor_itens_aprovados + v_valor_adicionais_aprovados + v_valor_acrescimos;
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
