-- Regressão do achado crítico #1 da auditoria (docs/testing/TEST_REPORT.md),
-- corrigido em supabase/migrations/20260810160000_p0_correcoes_criticas.sql.
-- Requer supabase/tests/_helpers.sql já aplicado uma vez no banco.
--
-- Executado via `supabase db query --linked -f <este arquivo>`, que só
-- retorna o resultado do ÚLTIMO SELECT do batch — por isso todas as
-- asserções ficam num único SELECT (UNION ALL), como última instrução antes
-- do ROLLBACK (sem usar plan()/finish(), que dependeriam de outro SELECT
-- depois e ficariam ocultos pela mesma limitação).
begin;

select plan(6);
select tests.autenticar_como_anon();

select throws_ok(
  $$ select rpc_criar_os('00000000-0000-0000-0000-000000000000'::uuid, 'interna'::tipo_os) $$,
  'P0001', 'Perfil sem permissão para criar ordem de serviço',
  'rpc_criar_os nega chamador anônimo'
)
union all
select throws_ok(
  $$ select rpc_aprovar_orcamento('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', 'Perfil sem permissão para aprovar orçamento',
  'rpc_aprovar_orcamento nega chamador anônimo'
)
union all
select throws_ok(
  $$ select rpc_liberar_os('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', 'Perfil sem permissão para liberar OS',
  'rpc_liberar_os nega chamador anônimo'
)
union all
select throws_ok(
  $$ select rpc_registrar_recebimento('00000000-0000-0000-0000-000000000000'::uuid, 1, 'pix', current_date) $$,
  'P0001', 'Perfil sem permissão para registrar recebimento',
  'rpc_registrar_recebimento nega chamador anônimo'
)
union all
select throws_ok(
  $$ select rpc_registrar_saida_estoque('00000000-0000-0000-0000-000000000000'::uuid, 1, 'os'::origem_movimento, '00000000-0000-0000-0000-000000000000'::uuid) $$,
  '42501', null,
  'rpc_registrar_saida_estoque inacessível (permission denied) para anon'
)
union all
select throws_ok(
  $$ select rpc_registrar_entrada_estoque('00000000-0000-0000-0000-000000000000'::uuid, 1, 1, 'os'::origem_movimento, '00000000-0000-0000-0000-000000000000'::uuid) $$,
  '42501', null,
  'rpc_registrar_entrada_estoque inacessível (permission denied) para anon'
);

rollback;
