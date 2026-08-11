-- ORC-009, ORC-010, ORC-011, ORC-012 — executado via `supabase db query --linked -f`.
begin;
select plan(4);

select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario));

insert into clientes (id, tipo, nome) values ('33333333-3333-3333-3333-333333333333', 'externo', 'PGTAP Cliente Teste ORC');
insert into veiculos (id, cliente_id, placa) values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'PGTAP002');
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', auth.uid());

-- Item válido, usado pela verificação ORC-012 abaixo (não é asserção em si).
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('55555555-5555-5555-5555-555555555555', 'PGTAP Item válido', 3, 100);

select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item qtd zero', 0, 10) $$,
  '23514', null,
  'ORC-009: quantidade zero deve ser bloqueada pelo CHECK da tabela'
)
union all
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item qtd negativa', -1, 10) $$,
  '23514', null,
  'ORC-010: quantidade negativa deve ser bloqueada pelo CHECK da tabela'
)
union all
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('55555555-5555-5555-5555-555555555555', 'Item preço negativo', 1, -10) $$,
  '23514', null,
  'ORC-011: valor_unitario negativo deve ser bloqueado pelo CHECK da tabela'
)
union all
select is(
  (select valor_total from orcamentos where id = '55555555-5555-5555-5555-555555555555'),
  300.00::numeric,
  'ORC-012: valor_total do orçamento reconcilia com soma dos itens (3 x R$100)'
);

rollback;
