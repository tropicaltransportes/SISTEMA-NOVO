-- ETAPA 6 (P1-C) — itens 1, 4, 5, 7: dados estruturados (JSON) para o PDF de
-- orçamento (ORC-013/DOC-001/DOC-002), o relatório de encerramento
-- (CON-005/CON-006/DOC-003), o relatório de garantia (GAR-007) e o
-- histórico do veículo (CAD-012). Nenhuma dessas funções MODIFICA dado —
-- são só leitura/consolidação (a "geração de documento" é responsabilidade
-- do frontend, a partir destes dados vindos do backend, conforme instrução
-- item 1: "os dados usados devem vir do backend atual").
--
-- SECURITY INVOKER (padrão, sem "security definer"): respeita a RLS de cada
-- tabela consultada para o usuário chamador — não é um jeito novo de burlar
-- permissão, só agrega o que o usuário já podia ver espalhado em várias
-- tabelas. Um executor, por exemplo, não vê valor de cobrança porque a RLS
-- de 'cobrancas' já bloqueia SELECT para executor (BR-013/financeiro) — a
-- função simplesmente retornará esse pedaço vazio/null para ele.

-- ============================================================
-- item 1: dados completos de UMA versão do orçamento, para o PDF.
-- Versionamento: cada versão é uma linha própria e imutável em `orcamentos`
-- (rpc_criar_versao_orcamento nunca edita a versão anterior, só marca
-- status='substituido' e cria uma linha nova) — então chamar esta função
-- com o id da versão 1 continua reproduzindo o documento da versão 1
-- mesmo depois de existir versão 2, 3, etc.
-- ============================================================
create or replace function rpc_dados_pdf_orcamento(p_orcamento_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'empresa', jsonb_build_object('nome', 'Tropical Transportes — Oficina Mecânica'),
    'orcamento', jsonb_build_object(
      'id', o.id,
      'numero_legivel', 'ORC-' || substr(o.id::text, 1, 8) || '-V' || o.versao,
      'versao', o.versao,
      'orcamento_raiz_id', coalesce(o.orcamento_raiz_id, o.id),
      'status', o.status,
      'criado_em', o.criado_em,
      'autorizado_por_nome', o.autorizado_por_nome,
      'autorizado_em', o.autorizado_em,
      'valor_bruto', coalesce(o.valor_bruto, o.valor_total),
      'desconto_percentual', o.desconto_percentual,
      'desconto_valor', coalesce(o.desconto_valor, 0),
      'desconto_motivo', o.desconto_motivo,
      'valor_liquido', coalesce(o.valor_liquido, o.valor_total),
      'valor_total', o.valor_total
    ),
    'cliente', jsonb_build_object('id', cli.id, 'nome', cli.nome, 'documento', cli.documento, 'tipo', cli.tipo),
    'veiculo', jsonb_build_object('id', v.id, 'placa', v.placa, 'modelo', v.modelo, 'ano', v.ano, 'prefixo', v.prefixo),
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', oi.id,
        'descricao', oi.descricao,
        'quantidade', oi.quantidade,
        'valor_unitario', oi.valor_unitario,
        'valor_total_original', oi.valor_total,
        'desconto_rateado', oi.desconto_rateado,
        'valor_liquido', oi.valor_liquido,
        'status_aprovacao', oi.status_aprovacao,
        'meio_aprovacao', oi.meio_aprovacao,
        'autorizado_por_nome', oi.autorizado_por_nome,
        'autorizado_em', oi.autorizado_em
      ) order by oi.id)
      from orcamento_itens oi where oi.orcamento_id = o.id
    ), '[]'::jsonb)
  )
  from orcamentos o
  join clientes cli on cli.id = o.cliente_id
  join veiculos v on v.id = o.veiculo_id
  where o.id = p_orcamento_id;
$$;

-- ============================================================
-- item 4 (CON-005/CON-006/DOC-003): relatório de encerramento da OS.
-- Consolida tudo que já está registrado — não recalcula, não altera a OS.
-- ============================================================
create or replace function rpc_relatorio_encerramento_os(p_os_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'os', jsonb_build_object(
      'id', os.id, 'tipo', os.tipo, 'status', os.status,
      'data_abertura', os.data_abertura, 'data_liberacao', os.data_liberacao,
      'previsao_conclusao', os.previsao_conclusao,
      'previsao_definida_por', os.previsao_definida_por, 'previsao_definida_em', os.previsao_definida_em,
      'centro_custo_id', os.centro_custo_id,
      'custo_pecas', os.custo_pecas, 'custo_mao_obra', os.custo_mao_obra, 'custo_total', os.custo_total,
      'custo_hora_aplicado', os.custo_hora_aplicado, 'horas_apontadas_total', os.horas_apontadas_total,
      'custo_calculado_em', os.custo_calculado_em
    ),
    'cliente', jsonb_build_object('id', cli.id, 'nome', cli.nome, 'tipo', cli.tipo),
    'veiculo', jsonb_build_object('id', vei.id, 'placa', vei.placa, 'modelo', vei.modelo, 'ano', vei.ano),
    'orcamento_original', case when os.orcamento_id is null then null else (
      select jsonb_build_object('id', o.id, 'versao', o.versao, 'valor_bruto', o.valor_bruto, 'desconto_valor', o.desconto_valor, 'valor_liquido', o.valor_liquido,
        'itens', coalesce((select jsonb_agg(jsonb_build_object('id', oi.id, 'descricao', oi.descricao, 'quantidade', oi.quantidade,
            'valor_unitario', oi.valor_unitario, 'status_aprovacao', oi.status_aprovacao, 'execucao_status', oi.execucao_status, 'valor_liquido', oi.valor_liquido) order by oi.id)
          from orcamento_itens oi where oi.orcamento_id = o.id), '[]'::jsonb))
      from orcamentos o where o.id = os.orcamento_id
    ) end,
    'adicionais', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'numero', a.numero, 'motivo', a.motivo, 'status', a.status,
        'itens', coalesce((select jsonb_agg(jsonb_build_object('id', oai.id, 'descricao', oai.descricao, 'quantidade', oai.quantidade,
              'valor_unitario', oai.valor_unitario, 'valor_total', oai.valor_total,
              'status_aprovacao', oai.status_aprovacao, 'execucao_status', oai.execucao_status) order by oai.id)
            from os_adicional_itens oai where oai.adicional_id = a.id), '[]'::jsonb)
      ) order by a.numero)
      from os_adicionais a where a.os_id = os.id
    ), '[]'::jsonb),
    'executores', coalesce((
      select jsonb_agg(jsonb_build_object(
        'usuario_id', oe.usuario_id, 'nome', p.nome, 'etapa', oe.etapa, 'inicio', oe.inicio, 'fim', oe.fim,
        'horas', case when oe.fim is not null then round(extract(epoch from (oe.fim - oe.inicio)) / 3600.0, 2) else null end,
        'ativo', oe.ativo, 'removido_em', oe.removido_em, 'motivo_remocao', oe.motivo_remocao
      ) order by oe.inicio)
      from os_executores oe join profiles p on p.id = oe.usuario_id where oe.os_id = os.id
    ), '[]'::jsonb),
    'checklist', coalesce((
      select jsonb_agg(jsonb_build_object('descricao', cti.descricao, 'obrigatorio', cti.obrigatorio, 'ok', r.ok, 'respondido_em', r.respondido_em) order by cti.id)
      from checklist_template_itens cti
      left join os_checklist_respostas r on r.template_item_id = cti.id and r.os_id = os.id
      where cti.template_id = os.checklist_template_id
    ), '[]'::jsonb),
    'fotos', coalesce((
      select jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo, 'arquivo_path', f.arquivo_path, 'enviado_por', f.enviado_por, 'enviado_em', f.enviado_em, 'observacao', f.observacao) order by f.enviado_em)
      from os_fotos f where f.os_id = os.id
    ), '[]'::jsonb),
    'pecas_utilizadas', coalesce((
      select jsonb_agg(jsonb_build_object('peca_id', em.peca_id, 'quantidade', em.quantidade, 'custo_unitario', em.custo_unitario, 'tipo', em.tipo, 'criado_em', em.criado_em) order by em.criado_em)
      from estoque_movimentos em where em.origem_tipo = 'os' and em.origem_id = os.id
    ), '[]'::jsonb),
    'cobranca', (
      select jsonb_build_object('id', c.id, 'valor_total', c.valor_total, 'status', c.status)
      from cobranca_origens co join cobrancas c on c.id = co.cobranca_id
      where co.os_id = os.id and c.status <> 'cancelada'
      order by c.criado_em desc limit 1
    ),
    'garantia_aberta_desta_os', (
      select jsonb_agg(jsonb_build_object('os_garantia_id', g.id, 'status', g.status, 'criado_em', g.data_abertura))
      from ordens_servico g where g.os_origem_id = os.id
    )
  )
  from ordens_servico os
  join clientes cli on cli.id = os.cliente_id
  join veiculos vei on vei.id = os.veiculo_id
  where os.id = p_os_id;
$$;

-- ============================================================
-- item 5 (GAR-007): relatório de garantia. p_os_garantia_id é a OS de
-- garantia (status reaberta_garantia/concluida/liberada, os_origem_id
-- aponta pra OS original).
-- ============================================================
create or replace function rpc_relatorio_garantia_os(p_os_garantia_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'os_garantia', jsonb_build_object('id', g.id, 'status', g.status, 'data_abertura', g.data_abertura, 'data_liberacao', g.data_liberacao),
    'os_original', jsonb_build_object('id', orig.id, 'data_abertura', orig.data_abertura, 'data_liberacao', orig.data_liberacao),
    'prazo_garantia_dias', 90,
    'prazo_garantia_expira_em', orig.data_liberacao + interval '90 days',
    'cliente', jsonb_build_object('id', cli.id, 'nome', cli.nome),
    'veiculo', jsonb_build_object('id', vei.id, 'placa', vei.placa, 'modelo', vei.modelo),
    'itens_originais_objeto_garantia', coalesce((
      select jsonb_agg(jsonb_build_object('origem', 'orcamento_original', 'item_id', oi.id, 'descricao', oi.descricao, 'quantidade', oi.quantidade, 'motivo', gi.motivo))
      from os_garantia_itens gi join orcamento_itens oi on oi.id = gi.orcamento_item_original_id
      where gi.os_garantia_id = g.id
    ), '[]'::jsonb),
    'itens_adicionais_objeto_garantia', coalesce((
      select jsonb_agg(jsonb_build_object('origem', 'adicional', 'item_id', oai.id, 'descricao', oai.descricao, 'quantidade', oai.quantidade, 'motivo', gi.motivo))
      from os_garantia_itens gi join os_adicional_itens oai on oai.id = gi.os_adicional_item_original_id
      where gi.os_garantia_id = g.id
    ), '[]'::jsonb),
    'execucao_realizada', coalesce((
      select jsonb_agg(jsonb_build_object('peca_id', em.peca_id, 'quantidade', em.quantidade, 'criado_em', em.criado_em))
      from estoque_movimentos em where em.origem_tipo = 'os' and em.origem_id = g.id and em.tipo = 'saida'
    ), '[]'::jsonb),
    'responsaveis', coalesce((
      select jsonb_agg(jsonb_build_object('usuario_id', oe.usuario_id, 'nome', p.nome, 'inicio', oe.inicio, 'fim', oe.fim))
      from os_executores oe join profiles p on p.id = oe.usuario_id where oe.os_id = g.id
    ), '[]'::jsonb),
    'conclusao', jsonb_build_object('status', g.status, 'data_liberacao', g.data_liberacao)
  )
  from ordens_servico g
  join ordens_servico orig on orig.id = g.os_origem_id
  join clientes cli on cli.id = g.cliente_id
  join veiculos vei on vei.id = g.veiculo_id
  where g.id = p_os_garantia_id;
$$;

-- ============================================================
-- item 7 (CAD-012): histórico cronológico do veículo. Não duplica dado —
-- só agrega as entidades existentes (OS, orçamentos, garantias). Nenhuma
-- tabela nova.
-- ============================================================
create or replace function rpc_historico_veiculo(p_veiculo_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'veiculo', jsonb_build_object('id', v.id, 'placa', v.placa, 'modelo', v.modelo, 'ano', v.ano, 'prefixo', v.prefixo, 'cliente_id', v.cliente_id),
    'ordens_servico', coalesce((
      select jsonb_agg(jsonb_build_object(
        'os_id', os.id, 'tipo', os.tipo, 'status', os.status,
        'data_abertura', os.data_abertura, 'data_liberacao', os.data_liberacao,
        'previsao_conclusao', os.previsao_conclusao,
        'orcamento_id', os.orcamento_id, 'os_origem_id', os.os_origem_id,
        'custo_total', os.custo_total,
        'valor_faturado', (
          select c.valor_total from cobranca_origens co join cobrancas c on c.id = co.cobranca_id
          where co.os_id = os.id and c.status <> 'cancelada' order by c.criado_em desc limit 1
        ),
        'executores', coalesce((select jsonb_agg(distinct p.nome) from os_executores oe join profiles p on p.id = oe.usuario_id where oe.os_id = os.id), '[]'::jsonb),
        'e_garantia_de', os.os_origem_id
      ) order by os.data_abertura desc)
      from ordens_servico os where os.veiculo_id = p_veiculo_id
    ), '[]'::jsonb),
    'orcamentos', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'versao', o.versao, 'status', o.status, 'valor_total', o.valor_total, 'criado_em', o.criado_em) order by o.criado_em desc)
      from orcamentos o where o.veiculo_id = p_veiculo_id
    ), '[]'::jsonb)
  )
  from veiculos v where v.id = p_veiculo_id;
$$;
