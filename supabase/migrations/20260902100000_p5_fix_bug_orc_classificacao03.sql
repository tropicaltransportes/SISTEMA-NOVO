-- BUG-ORC-CLASSIFICACAO-03 — investigação completa em
-- docs/testing/UX_PDF_ORCAMENTO_01_REPORT.md. Resumo:
--
-- rpc_dados_pdf_orcamento JÁ devolvia 'natureza' desde
-- 20260818160000_p2c_pdf_orcamento_dados_comerciais.sql (ETAPA
-- UX-PDF-ORCAMENTO-01), e OrcamentoPdf.vue/pdfOrcamento.js JÁ filtram
-- corretamente por `item.natureza === 'peca'` desde então — a hipótese
-- inicial ("RPC nunca devolvia natureza") estava errada, baseada numa
-- versão desatualizada desta função lida antes de eu notar a redefinição
-- de 18/08. A causa raiz real do orçamento reportado é OUTRA: o formulário
-- de item do orçamento (OrcamentosList.vue) permitia salvar um item no modo
-- "Peça" sem selecionar de fato uma peça do catálogo (placeholder dizia
-- "Peça (opcional)") — o item ia pro banco com peca_id NULL, e a coluna
-- GERADA orcamento_itens.natureza (estrutural, correta por definição)
-- classificava esse item como 'servico_avulso', porque não existe uma 4ª
-- categoria "peça sem catálogo" no modelo (corrigido nesta mesma etapa, ver
-- OrcamentosList.vue: peca_id agora é obrigatório no modo "Peça").
--
-- Esta migration só acrescenta peca_id/servico_id ao payload de 'itens'
-- (pedido explícito da seção 7 do BUG-ORC-CLASSIFICACAO-03 — "não obrigar o
-- frontend a reconstruir a natureza por heurística", dá mais visibilidade
-- pra debug futuro) — corpo idêntico ao de 20260818160000 (preserva
-- cliente.telefone/email adicionados naquela etapa), nada removido.
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
    'cliente', jsonb_build_object(
      'id', cli.id, 'nome', cli.nome, 'documento', cli.documento, 'tipo', cli.tipo,
      'telefone', cli.telefone, 'email', cli.email
    ),
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
        'autorizado_em', oi.autorizado_em,
        'natureza', oi.natureza,
        -- BUG-ORC-CLASSIFICACAO-03: campos estruturais que faltavam.
        'peca_id', oi.peca_id,
        'servico_id', oi.servico_id
      ) order by oi.id)
      from orcamento_itens oi where oi.orcamento_id = o.id
    ), '[]'::jsonb)
  )
  from orcamentos o
  join clientes cli on cli.id = o.cliente_id
  join veiculos v on v.id = o.veiculo_id
  where o.id = p_orcamento_id;
$$;
