-- ORC-009, ORC-010, ORC-011, ORC-012 — NÃO EXECUTADO (ver supabase/tests/README.md).
begin;
select plan(4);
\i _helpers.sql

select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario));

insert into clientes (id, tipo, nome) values ('33333333-3333-3333-3333-333333333333', 'externo', 'Cliente Teste ORC');
insert into veiculos (id, cliente_id, placa) values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'TST0001');
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', auth.uid());

-- ORC-009: quantidade zero bloqueada por CHECK (quantidade > 0).
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item qtd zero', 0, 10) $$,
  '23514', null,
  'ORC-009: quantidade zero deve ser bloqueada pelo CHECK da tabela'
);

-- ORC-010: quantidade negativa bloqueada.
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item qtd negativa', -1, 10) $$,
  '23514', null,
  'ORC-010: quantidade negativa deve ser bloqueada pelo CHECK da tabela'
);

-- ORC-011: preço negativo bloqueado.
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item preço negativo', 1, -10) $$,
  '23514', null,
  'ORC-011: valor_unitario negativo deve ser bloqueado pelo CHECK da tabela'
);

-- ORC-012: total consistente — valor_total é coluna gerada (quantidade * valor_unitario)
-- e o trigger recalc_valor_total_orcamento soma os itens no orçamento pai.
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('55555555-5555-5555-5555-555555555555', 'Item válido', 3, 100);

select is(
  (select valor_total from orcamentos where id = '55555555-5555-5555-5555-555555555555'),
  300.00::numeric,
  'ORC-012: valor_total do orçamento reconcilia com soma dos itens (3 x R$100)'
);

select * from finish();
rollback;
