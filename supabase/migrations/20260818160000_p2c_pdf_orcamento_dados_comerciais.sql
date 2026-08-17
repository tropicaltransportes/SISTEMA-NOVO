-- ETAPA UX-PDF-ORCAMENTO-01 — reformulação visual do PDF comercial de
-- orçamento. Esta migration NÃO altera regra de negócio, cálculo,
-- aprovação, versionamento, valor nem permissão — só estende
-- rpc_dados_pdf_orcamento (20260814111000_p1c_relatorios.sql) para expor
-- dados que já existem nas tabelas, necessários para o novo layout:
--
--   1. itens[].natureza — discriminador 'peca'/'servico_cadastrado'/
--      'servico_avulso', coluna GERADA já existente em orcamento_itens
--      desde FEATURE-SERVICOS-01 (20260817140100_p2_fix_natureza_gerada.sql).
--      Necessário para separar as seções PEÇAS e MÃO DE OBRA sem recorrer a
--      análise textual da descrição (proibido pela instrução da etapa,
--      item 11) — o discriminador estrutural já existe, só não era
--      devolvido por esta RPC.
--   2. cliente.telefone / cliente.email — colunas já existentes em
--      `clientes` (20260806120100_clientes_veiculos.sql), com a mesma RLS
--      de SELECT (current_user_ativo/autenticado) que já libera nome/
--      documento/tipo hoje. Necessário para a seção CLIENTE do novo layout
--      (item 7 da instrução: "Telefone, se existir / E-mail, se existir").
--
-- SECURITY: função continua SECURITY INVOKER (padrão, sem "security
-- definer") — respeita a RLS de cada tabela para o usuário chamador, exatamente
-- como antes. Nenhuma tabela nova, nenhuma policy nova, nenhuma coluna nova.
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
        'natureza', oi.natureza
      ) order by oi.id)
      from orcamento_itens oi where oi.orcamento_id = o.id
    ), '[]'::jsonb)
  )
  from orcamentos o
  join clientes cli on cli.id = o.cliente_id
  join veiculos v on v.id = o.veiculo_id
  where o.id = p_orcamento_id;
$$;
