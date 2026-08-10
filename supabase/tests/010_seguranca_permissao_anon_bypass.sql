-- Regressão do achado crítico da auditoria de 2026-08-10 (docs/testing/TEST_REPORT.md).
-- NÃO EXECUTADO (ver supabase/tests/README.md) — infraestrutura pronta para
-- rodar assim que houver ambiente seguro (Docker local ou projeto de teste).
--
-- Bug: toda RPC que faz `if current_perfil() not in (...) then raise
-- exception` deixa passar um chamador SEM SESSÃO NENHUMA (papel `anon`),
-- porque current_perfil() retorna NULL para esse chamador, e
-- `NULL NOT IN (lista)` avalia para NULL — que o `IF` do plpgsql trata como
-- falso, então a exceção nunca dispara e a função continua executando.
--
-- Confirmado com evidência real (não destrutiva, sem gravação) contra o
-- projeto Supabase de produção/dev em 2026-08-10 — ver
-- docs/testing/scripts/safe_anon_rpc_checks.sh e a saída em
-- docs/testing/TEST_REPORT.md, achado crítico #1.
--
-- Critério de aceite da correção: trocar `current_perfil() not in (...)`
-- por `coalesce(current_perfil()::text, '') not in (...)` (ou equivalente
-- `current_perfil() is null or current_perfil() not in (...)`) em TODA RPC
-- do projeto que segue este padrão — não só nas listadas aqui.

begin;
select plan(6);
\i _helpers.sql

select tests.autenticar_como_anon();

-- Cada uma destas deveria falhar com 'Perfil sem permissão...' mesmo com IDs
-- inexistentes — se a mensagem for de negócio ("não encontrado(a)" etc.), a
-- função executou além do que deveria e o teste falha (throws_ok compara a
-- mensagem esperada).

select throws_ok(
  $$ select rpc_criar_os('00000000-0000-0000-0000-000000000000'::uuid, 'interna'::tipo_os) $$,
  'P0001', 'Perfil sem permissão para criar ordem de serviço',
  'rpc_criar_os deve negar chamador anônimo antes de checar o veículo'
);

select throws_ok(
  $$ select rpc_aprovar_orcamento('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', 'Perfil sem permissão para aprovar orçamento',
  'rpc_aprovar_orcamento deve negar chamador anônimo antes de checar o orçamento'
);

select throws_ok(
  $$ select rpc_liberar_os('00000000-0000-0000-0000-000000000000'::uuid) $$,
  'P0001', 'Perfil sem permissão para liberar OS',
  'rpc_liberar_os deve negar chamador anônimo antes de checar a OS'
);

select throws_ok(
  $$ select rpc_registrar_recebimento('00000000-0000-0000-0000-000000000000'::uuid, 1, 'pix', current_date) $$,
  'P0001', 'Perfil sem permissão para registrar recebimento',
  'rpc_registrar_recebimento deve negar chamador anônimo antes de checar a parcela'
);

-- rpc_registrar_saida_estoque / rpc_registrar_entrada_estoque não têm check
-- de perfil próprio (dependem de REVOKE + só serem chamadas por outras RPCs
-- já gated) — o teste aqui é se o REVOKE realmente bloqueia o papel `anon`.
select throws_ok(
  $$ select rpc_registrar_saida_estoque('00000000-0000-0000-0000-000000000000'::uuid, 1, 'os'::origem_movimento, '00000000-0000-0000-0000-000000000000'::uuid) $$,
  '42501', null,
  'rpc_registrar_saida_estoque deve ser inacessível (permission denied) para o papel anon — não deve reagir com "peça não encontrada"'
);

select throws_ok(
  $$ select rpc_registrar_entrada_estoque('00000000-0000-0000-0000-000000000000'::uuid, 1, 1, 'os'::origem_movimento, '00000000-0000-0000-0000-000000000000'::uuid) $$,
  '42501', null,
  'rpc_registrar_entrada_estoque deve ser inacessível (permission denied) para o papel anon'
);

select * from finish();
rollback;
