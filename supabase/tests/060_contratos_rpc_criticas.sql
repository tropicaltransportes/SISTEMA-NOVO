-- ETAPA 7 (RC1), seção 6 — testes de CONTRATO permanentes para as 10 RPCs
-- críticas do roteiro de homologação final:
--   rpc_criar_os, rpc_transicionar_os, rpc_concluir_os, rpc_baixar_peca_os,
--   rpc_criar_cobranca, rpc_liberar_os, rpc_criar_os_garantia,
--   rpc_decidir_item_orcamento, rpc_decidir_item_os_adicional,
--   rpc_registrar_termo_ciencia.
--
-- Objetivo (igual ao motivo do REG-GAR-001 em 050_regressao_garantia.sql):
-- detectar quando um `CREATE OR REPLACE FUNCTION` futuro muda a assinatura
-- esperada OU elimina silenciosamente a checagem de permissão — exatamente
-- a classe de bug já vista duas vezes neste projeto (o bug histórico
-- `NULL NOT IN (...)` que deixava `anon` passar, ver 010_seguranca_*, e a
-- regressão do ramo de garantia em rpc_baixar_peca_os, ver 050_*).
--
-- Duas camadas por RPC:
--   1) assinatura (has_function) — nome, ordem e tipo dos parâmetros. Se
--      alguém adicionar/remover/reordenar um parâmetro (como aconteceu de
--      fato com rpc_registrar_termo_ciencia — ver
--      20260815120000_rc1_fix_overload_orfao_termo_ciencia.sql), este teste
--      falha imediatamente.
--   2) permissão — chamando como `anon` (sem sessão nenhuma), a RPC precisa
--      continuar rejeitando. Cada uma destas 10 funções faz
--      `if not tem_perfil(...) then raise exception` como a PRIMEIRA
--      instrução do corpo, então os parâmetros abaixo usam valores "vazios"
--      de propósito — não avaliam a regra de negócio, só a barreira de
--      permissão, que é o contrato que este arquivo protege.
begin;

select plan(20);

select tests.autenticar_como_anon();

-- ------------------------------------------------------------------
-- 1) Assinaturas — travam nome/ordem/tipo dos parâmetros hoje em produção.
-- ------------------------------------------------------------------
select has_function('public', 'rpc_criar_os',
  ARRAY['uuid','tipo_os','uuid','uuid','uuid'],
  'contrato: rpc_criar_os(p_veiculo_id uuid, p_tipo tipo_os, p_orcamento_id uuid, p_solicitacao_id uuid, p_checklist_template_id uuid)')
union all
-- ETAPA OS-FLOW-03: rpc_transicionar_os ganhou p_motivo (obrigatório só
-- para os 2 retrocessos de fase novos — ver 20260819180000/180100 e
-- BUSINESS_RULES.md BR-053). A versão de 2 parâmetros foi
-- explicitamente dropada na migration de correção (não coexiste como
-- overload), então o contrato correto agora é o de 3 parâmetros.
select has_function('public', 'rpc_transicionar_os',
  ARRAY['uuid','status_os','text'],
  'contrato: rpc_transicionar_os(p_os_id uuid, p_novo_status status_os, p_motivo text)')
union all
select has_function('public', 'rpc_concluir_os',
  ARRAY['uuid'],
  'contrato: rpc_concluir_os(p_os_id uuid)')
union all
select has_function('public', 'rpc_baixar_peca_os',
  ARRAY['uuid','uuid','numeric','uuid','uuid','uuid'],
  'contrato: rpc_baixar_peca_os(p_os_id, p_peca_id, p_quantidade, p_idempotency_key, p_orcamento_item_id, p_os_adicional_item_id)')
union all
select has_function('public', 'rpc_criar_cobranca',
  ARRAY['uuid','uuid[]','uuid[]'],
  'contrato: rpc_criar_cobranca(p_cliente_id uuid, p_os_ids uuid[], p_venda_ids uuid[])')
union all
select has_function('public', 'rpc_liberar_os',
  ARRAY['uuid'],
  'contrato: rpc_liberar_os(p_os_id uuid)')
union all
select has_function('public', 'rpc_criar_os_garantia',
  ARRAY['uuid','uuid[]','uuid[]'],
  'contrato: rpc_criar_os_garantia(p_os_origem_id uuid, p_itens_originais uuid[], p_itens_adicionais_originais uuid[])')
union all
select has_function('public', 'rpc_decidir_item_orcamento',
  ARRAY['uuid','text','text','text','text','text'],
  'contrato: rpc_decidir_item_orcamento(p_orcamento_item_id, p_decisao, p_meio_aprovacao, p_autorizado_por_nome, p_comprovante_path, p_observacao)')
union all
select has_function('public', 'rpc_decidir_item_os_adicional',
  ARRAY['uuid','text','text','text','text','text'],
  'contrato: rpc_decidir_item_os_adicional(p_item_id, p_decisao, p_meio_aprovacao, p_autorizado_por_nome, p_comprovante_path, p_observacao)')
union all
select has_function('public', 'rpc_registrar_termo_ciencia',
  ARRAY['uuid','text','text','text','text'],
  'contrato: rpc_registrar_termo_ciencia(p_cobranca_id, p_arquivo_path, p_responsavel_nome, p_responsavel_documento, p_observacao) — ÚNICA assinatura, ver correção RC1 do overload órfão')

-- ------------------------------------------------------------------
-- 2) Permissão — chamador `anon` (sem sessão) tem que continuar barrado nas
--    10 RPCs. Regressão típica: reescrita da função "esquece" o `if not
--    tem_perfil(...)` inicial, ou o reordena para depois de uma consulta que
--    já vaza dado/efeito colateral.
-- ------------------------------------------------------------------
union all
select throws_ok(
  $$ select rpc_criar_os('00000000-0000-0000-0000-000000000000'::uuid, 'interna'::tipo_os) $$,
  'P0001', null, 'permissão: rpc_criar_os nega anon'
)
union all
select throws_ok(
  $$ select rpc_transicionar_os('00000000-0000-0000-0000-000000000000'::uuid, 'em_execucao'::status_os) $$,
  'P0001', null, 'permissão: rpc_transicionar_os nega anon'
)
union all
select throws_ok(
  $$ select rpc_concluir_os('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', null, 'permissão: rpc_concluir_os nega anon'
)
union all
select throws_ok(
  $$ select rpc_baixar_peca_os('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 1) $$,
  'P0001', null, 'permissão: rpc_baixar_peca_os nega anon'
)
union all
select throws_ok(
  $$ select rpc_criar_cobranca('00000000-0000-0000-0000-000000000000'::uuid, array['00000000-0000-0000-0000-000000000000'::uuid], null) $$,
  'P0001', null, 'permissão: rpc_criar_cobranca nega anon'
)
union all
select throws_ok(
  $$ select rpc_liberar_os('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', null, 'permissão: rpc_liberar_os nega anon'
)
union all
select throws_ok(
  $$ select rpc_criar_os_garantia('00000000-0000-0000-0000-000000000000'::uuid, null, null) $$,
  'P0001', null, 'permissão: rpc_criar_os_garantia nega anon'
)
union all
select throws_ok(
  $$ select rpc_decidir_item_orcamento('00000000-0000-0000-0000-000000000000'::uuid, 'aprovado', 'sistema', 'x', null, null) $$,
  'P0001', null, 'permissão: rpc_decidir_item_orcamento nega anon'
)
union all
select throws_ok(
  $$ select rpc_decidir_item_os_adicional('00000000-0000-0000-0000-000000000000'::uuid, 'aprovado', 'sistema', 'x', null, null) $$,
  'P0001', null, 'permissão: rpc_decidir_item_os_adicional nega anon'
)
union all
select throws_ok(
  $$ select rpc_registrar_termo_ciencia('00000000-0000-0000-0000-000000000000'::uuid, 'x', 'x', null, null) $$,
  'P0001', null, 'permissão: rpc_registrar_termo_ciencia nega anon'
);

rollback;
