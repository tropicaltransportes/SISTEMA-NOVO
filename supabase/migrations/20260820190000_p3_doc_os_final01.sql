-- ETAPA DOC-OS-FINAL-01 — documento comercial de conclusão da OS (view +
-- PDF), equivalente em arquitetura ao PDF de orçamento (rpc_dados_pdf_orcamento
-- / OrcamentoPdf.vue). Só leitura/consolidação — nenhuma tabela nova, nenhuma
-- regra financeira nova: todo valor já é snapshot desde a Fase 2/P1-C
-- (orcamento_itens.valor_unitario nunca faz join vivo com catálogo;
-- os.custo_pecas/custo_mao_obra/custo_total já são congelados em
-- calcular_e_snapshot_custo_interno_os na conclusão — ver
-- 20260814110500_p1c_cliente_interno_custo.sql).
--
-- Por que uma RPC nova (rpc_documento_final_os) em vez de reaproveitar
-- rpc_relatorio_encerramento_os: aquela é o relatório INTERNO já homologado
-- (BR-025/DOC-003) — carrega checklist, fotos, IDs técnicos, movimentos de
-- estoque crus. O documento comercial não pode carregar nada disso (item 46
-- do pedido). Não altera rpc_relatorio_encerramento_os.
--
-- ACHADO DURANTE A IMPLEMENTAÇÃO (registrado aqui e no
-- TEST_REPORT_OS_DOCUMENTO_FINAL01.md, decisão confirmada com o dono do
-- projeto): a máquina de estados atual (rpc_concluir_os,
-- 20260819180000_p2e_os_fluxo_transicoes.sql:184-195) só permite concluir a
-- OS quando todo item aprovado do orçamento/adicional está com
-- execucao_status='executado' (100% da quantidade aprovada baixada) OU
-- 'cancelado' (0% baixado, e rpc_marcar_item_orcamento_execucao só permite
-- cancelar a partir de 'pendente' — 20260814110800_p1c_cancelamento_item_aprovado.sql:66-68).
-- Não existe hoje um caminho para "fechar" um item parcialmente baixado
-- (execucao_status='parcial') preservando a quantidade real entregue — logo
-- o cenário "aprovado 5, utilizado 3, resto dispensado" (itens 12/50 do
-- pedido) NÃO é alcançável numa OS realmente concluída pelo sistema atual.
-- Esta RPC já calcula a quantidade utilizada a partir do ledger real
-- (estoque_movimentos), então no dia em que esse gap for corrigido (fora de
-- escopo desta etapa — é o mesmo módulo que já causou 2 incidentes de
-- produção), o documento passa a refletir corretamente sem precisar ser
-- tocado de novo.

create or replace function rpc_documento_final_os(p_os_id uuid)
returns jsonb
language sql
stable
as $$
  with peca_qtd as (
    -- Quantidade EFETIVAMENTE UTILIZADA (itens 11/13 do pedido) = líquido do
    -- ledger real (saida - estorno_saida), nunca a quantidade aprovada —
    -- ainda que hoje, dado o gap documentado acima, os dois só possam
    -- coincidir (executado = 100% baixado) ou o item nem apareça aqui
    -- (0 baixado). peca_id/descrição/valor_unitario são snapshot do item
    -- (nunca join vivo com pecas para preço — só para nome/sku de exibição).
    select oi.id as item_id, oi.peca_id, oi.descricao, oi.valor_unitario,
           coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
             - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0) as quantidade_utilizada
    from orcamento_itens oi
    left join estoque_movimentos em
      on em.orcamento_item_id = oi.id and em.origem_tipo = 'os' and em.origem_id = p_os_id
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.peca_id is not null
      and oi.status_aprovacao = 'aprovado'
    group by oi.id, oi.peca_id, oi.descricao, oi.valor_unitario
    union all
    select oai.id, oai.peca_id, oai.descricao, oai.valor_unitario,
           coalesce(sum(em.quantidade) filter (where em.tipo = 'saida'), 0)
             - coalesce(sum(em.quantidade) filter (where em.tipo = 'estorno_saida'), 0)
    from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    left join estoque_movimentos em
      on em.os_adicional_item_id = oai.id and em.origem_tipo = 'os' and em.origem_id = p_os_id
    where a.os_id = p_os_id
      and oai.peca_id is not null
      and oai.status_aprovacao = 'aprovado'
    group by oai.id, oai.peca_id, oai.descricao, oai.valor_unitario
  ),
  mao_obra as (
    -- Mão de obra não passa por baixa de estoque — sinal de "efetivamente
    -- executado" é execucao_status='executado' (marcação manual, item 14/15).
    select oi.id as item_id, oi.descricao, oi.quantidade, oi.valor_unitario
    from orcamento_itens oi
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.peca_id is null
      and oi.status_aprovacao = 'aprovado'
      and oi.execucao_status = 'executado'
    union all
    select oai.id, oai.descricao, oai.quantidade, oai.valor_unitario
    from os_adicional_itens oai
    join os_adicionais a on a.id = oai.adicional_id
    where a.os_id = p_os_id
      and oai.peca_id is null
      and oai.status_aprovacao = 'aprovado'
      and oai.execucao_status = 'executado'
  ),
  subtotal_pecas as (
    select coalesce(sum(quantidade_utilizada * valor_unitario), 0) as valor
    from peca_qtd where quantidade_utilizada > 0
  ),
  subtotal_mao_obra as (
    select coalesce(sum(quantidade * valor_unitario), 0) as valor from mao_obra
  ),
  desconto as (
    -- Só orçamento tem desconto (item 20) — adicional nunca tem, nesta etapa
    -- do produto (mesma nota já registrada em rpc_criar_cobranca).
    select coalesce(sum(oi.desconto_rateado), 0) as valor
    from orcamento_itens oi
    where oi.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
      and oi.status_aprovacao = 'aprovado' and oi.execucao_status <> 'cancelado'
  ),
  acrescimos as (
    select coalesce(sum(a.valor_acrescimo), 0) as valor
    from orcamento_acrescimos a
    where a.orcamento_id = (select orcamento_id from ordens_servico where id = p_os_id)
  )
  select jsonb_build_object(
    'empresa', jsonb_build_object('nome', 'Tropical Transportes — Oficina Mecânica'),
    'os', jsonb_build_object(
      'id', os.id,
      -- Mesmo padrão do orçamento (numero_legivel derivado do UUID, sem
      -- numeração sequencial nova — item 7 do pedido): rpc_dados_pdf_orcamento
      -- usa 'ORC-' || substr(id,1,8); aqui, 'OS-' || substr(id,1,8).
      'numero_legivel', 'OS-' || upper(substr(os.id::text, 1, 8)),
      'tipo', os.tipo,
      'status', os.status,
      'data_abertura', os.data_abertura,
      'data_liberacao', os.data_liberacao
    ),
    'cliente', jsonb_build_object(
      'id', cli.id, 'nome', cli.nome, 'documento', cli.documento,
      'telefone', cli.telefone, 'email', cli.email, 'tipo', cli.tipo
    ),
    'veiculo', jsonb_build_object(
      'id', vei.id, 'placa', vei.placa, 'modelo', vei.modelo, 'ano', vei.ano, 'prefixo', vei.prefixo
    ),
    'executores', coalesce((
      select jsonb_agg(distinct p.nome order by p.nome)
      from os_executores oe join profiles p on p.id = oe.usuario_id
      where oe.os_id = os.id
    ), '[]'::jsonb),
    'pecas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'descricao', pq.descricao,
        'sku', pe.sku,
        'quantidade', pq.quantidade_utilizada,
        'valor_unitario', pq.valor_unitario,
        'valor_total', round(pq.quantidade_utilizada * pq.valor_unitario, 2)
      ) order by pq.descricao)
      from peca_qtd pq left join pecas pe on pe.id = pq.peca_id
      where pq.quantidade_utilizada > 0
    ), '[]'::jsonb),
    'mao_de_obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'descricao', mo.descricao,
        'quantidade', mo.quantidade,
        'valor_unitario', mo.valor_unitario,
        'valor_total', round(mo.quantidade * mo.valor_unitario, 2)
      ) order by mo.descricao)
      from mao_obra mo
    ), '[]'::jsonb),
    'resumo_financeiro', jsonb_build_object(
      'subtotal_pecas', (select valor from subtotal_pecas),
      'subtotal_mao_obra', (select valor from subtotal_mao_obra),
      'valor_bruto', (select valor from subtotal_pecas) + (select valor from subtotal_mao_obra),
      'desconto_valor', (select valor from desconto),
      'acrescimos_valor', (select valor from acrescimos),
      -- Réplica exata da fórmula de rpc_criar_cobranca (item 23 do pedido —
      -- "VALOR FINAL = VALOR FATURÁVEL"): bruto (peças+mão de obra
      -- efetivamente utilizadas) - desconto rateado + acréscimos. Calculado
      -- sempre, mesmo antes de existir uma cobrança de fato (a cobrança é um
      -- passo separado, pós-conclusão) — quando a cobrança existir, os dois
      -- valores precisam bater exatamente (validado em pgTAP).
      'valor_final', round(
        (select valor from subtotal_pecas) + (select valor from subtotal_mao_obra)
          - (select valor from desconto) + (select valor from acrescimos)
      , 2)
    ),
    'cobranca', (
      select jsonb_build_object('id', c.id, 'valor_total', c.valor_total, 'status', c.status)
      from cobranca_origens co join cobrancas c on c.id = co.cobranca_id
      where co.os_id = os.id and c.status <> 'cancelada'
      order by c.criado_em desc limit 1
    ),
    -- Cliente interno (item 4/54): custo consolidado já snapshot na
    -- conclusão, nunca convertido em valor de venda. Cliente externo nunca
    -- recebe este bloco (null).
    'custo_interno', case when os.tipo = 'interna' then jsonb_build_object(
      'custo_pecas', os.custo_pecas,
      'custo_mao_obra', os.custo_mao_obra,
      'custo_total', os.custo_total
    ) else null end,
    -- Garantia (item 26): só monta quando a OS já foi liberada (data de
    -- início da contagem real) — antes disso não existe data a partir da
    -- qual calcular expiração, e o pedido veda declarar prazo genérico sem
    -- base real (item 26: "não declarar genericamente"). 90 dias é o mesmo
    -- literal fixo hoje realmente aplicado por rpc_criar_os_garantia — não
    -- usa garantia_dias_snapshot por catálogo, que é só metadado decorativo
    -- (confirmado em 20260817140000_p2_servicos_catalogo.sql).
    'garantia', case when os.data_liberacao is not null then jsonb_build_object(
      'prazo_dias', 90,
      'expira_em', os.data_liberacao + interval '90 days'
    ) else null end
  )
  from ordens_servico os
  join clientes cli on cli.id = os.cliente_id
  join veiculos vei on vei.id = os.veiculo_id
  where os.id = p_os_id;
$$;

comment on function rpc_documento_final_os(uuid) is
  'Documento comercial de conclusão da OS (DOC-OS-FINAL-01) — só leitura, security invoker (RLS de cada tabela consultada aplica normalmente). Não confundir com rpc_relatorio_encerramento_os (relatório interno de auditoria, BR-025).';
