-- EST-002, EST-007, EST-008, EST-009 — NÃO EXECUTADO (ver supabase/tests/README.md).
begin;
select plan(5);
\i _helpers.sql

select tests.autenticar_como(tests.criar_usuario_teste('suporte_administrativo'::perfil_usuario));

-- Peça de teste com saldo conhecido.
insert into pecas (id, sku, descricao, saldo_atual, custo_medio)
values ('11111111-1111-1111-1111-111111111111', 'SKU-TESTE-EST', 'Peça de teste', 5, 10);

-- EST-008: saída com quantidade negativa/zero deve ser bloqueada.
select throws_ok(
  $$ select rpc_registrar_saida_estoque('11111111-1111-1111-1111-111111111111'::uuid, -1, 'venda_avulsa'::origem_movimento, gen_random_uuid()) $$,
  'P0001', 'Quantidade de saída deve ser positiva',
  'EST-008: saída com quantidade negativa deve ser bloqueada'
);

select throws_ok(
  $$ select rpc_registrar_saida_estoque('11111111-1111-1111-1111-111111111111'::uuid, 0, 'venda_avulsa'::origem_movimento, gen_random_uuid()) $$,
  'P0001', 'Quantidade de saída deve ser positiva',
  'EST-002 (espelhado p/ saída): quantidade zero deve ser bloqueada'
);

-- EST-007: saldo insuficiente (saldo=5, pede 10) deve ser bloqueado e não pode deixar saldo negativo.
select throws_ok(
  $$ select rpc_registrar_saida_estoque('11111111-1111-1111-1111-111111111111'::uuid, 10, 'venda_avulsa'::origem_movimento, gen_random_uuid()) $$,
  'P0001', null,
  'EST-007: saída maior que o saldo disponível deve ser bloqueada'
);

select is(
  (select saldo_atual from pecas where id = '11111111-1111-1111-1111-111111111111'),
  5::numeric,
  'EST-007: saldo permanece inalterado após tentativa de saída acima do disponível'
);

-- EST-009: repetir a baixa da MESMA origem (mesma OS) hoje NÃO é bloqueada
-- pela RPC genérica — não há checagem de idempotência por origem_id em
-- rpc_registrar_saida_estoque. Este teste documenta o comportamento atual
-- (esperado FALHAR até que BR-033 seja implementada para este caminho).
select lives_ok(
  $$ select rpc_registrar_saida_estoque('11111111-1111-1111-1111-111111111111'::uuid, 1, 'os'::origem_movimento, '22222222-2222-2222-2222-222222222222'::uuid) $$,
  'primeira baixa da OS 222...222 (referência)'
);
-- Repetir a mesma baixa da mesma OS NÃO deveria duplicar (BR-033) — hoje duplica.
-- (deixado como observação; ver TEST_REPORT.md EST-009 = DIVERGE_DA_REGRA)

select * from finish();
rollback;
