-- EST-002, EST-007, EST-008, EST-009 — executado via `supabase db query --linked -f`.
-- Usa rpc_baixar_peca_os (entrada pública real) em vez de chamar
-- rpc_registrar_saida_estoque diretamente — depois do P0-01, essa RPC
-- interna tem EXECUTE revogado até de "authenticated", só é alcançável via
-- wrapper (rpc_baixar_peca_os/rpc_criar_venda_avulsa), como pretendido.
begin;

select plan(6);

-- Fixtures criadas AINDA como superusuário (antes de trocar de papel) porque
-- ordens_servico não tem nenhuma policy de INSERT para "authenticated" —
-- só é gravável via RPC (rpc_criar_os) por design.
do $$ declare v_uid uuid; begin
  v_uid := tests.criar_usuario_teste('suporte_administrativo'::perfil_usuario);
  perform set_config('tests.uid_atual', v_uid::text, true);
end $$;

insert into pecas (id, sku, descricao, saldo_atual, custo_medio)
values ('11111111-1111-1111-1111-111111111111', 'PGTAP_SKU_TESTE_EST', 'PGTAP Peça de teste', 5, 10);

insert into clientes (id, tipo, nome) values ('11111111-2222-2222-2222-222222222222', 'interno', 'PGTAP Cliente Teste EST');
insert into veiculos (id, cliente_id, placa) values ('11111111-3333-3333-3333-333333333333', '11111111-2222-2222-2222-222222222222', 'PGTAP01');
insert into ordens_servico (id, veiculo_id, cliente_id, tipo, status, criado_por)
values ('11111111-4444-4444-4444-444444444444', '11111111-3333-3333-3333-333333333333', '11111111-2222-2222-2222-222222222222', 'interna', 'em_execucao', current_setting('tests.uid_atual')::uuid);

select tests.autenticar_como(current_setting('tests.uid_atual')::uuid);

select throws_ok(
  $$ select rpc_baixar_peca_os('11111111-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, -1) $$,
  'P0001', 'Quantidade de saída deve ser positiva',
  'EST-008: baixa com quantidade negativa deve ser bloqueada'
)
union all
select throws_ok(
  $$ select rpc_baixar_peca_os('11111111-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 0) $$,
  'P0001', 'Quantidade de saída deve ser positiva',
  'EST-002 (espelhado p/ baixa): quantidade zero deve ser bloqueada'
)
union all
select throws_ok(
  $$ select rpc_baixar_peca_os('11111111-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 10) $$,
  'P0001', null,
  'EST-007: baixa maior que o saldo disponível (5) deve ser bloqueada'
)
union all
select is(
  (select saldo_atual from pecas where id = '11111111-1111-1111-1111-111111111111'),
  5::numeric,
  'EST-007: saldo permanece inalterado (5) após tentativa acima do disponível'
)
union all
-- Primeira baixa válida de 2 unidades — deve funcionar sem lançar exceção.
-- (RETURNS VOID: usar lives_ok, não "IS NULL" — uma chamada void bem
-- sucedida não é SQL NULL, é só ausência de valor de retorno.)
select lives_ok(
  $$ select rpc_baixar_peca_os('11111111-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 2) $$,
  'baixa válida de 2 unidades executa sem erro'
)
union all
-- P0-04 / EST-009: repetir a MESMA baixa (mesma OS/peça/quantidade) na
-- sequência deve ser bloqueada pela janela de deduplicação de 5s.
select throws_ok(
  $$ select rpc_baixar_peca_os('11111111-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 2) $$,
  'P0001', null,
  'EST-009: repetir a mesma baixa (duplo clique) deve ser bloqueada pela dedup de 5s'
);

rollback;
