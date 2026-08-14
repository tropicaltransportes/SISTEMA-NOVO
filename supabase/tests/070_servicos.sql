-- FEATURE-SERVICOS-01 — SERV-001..010, SERV-ORC-001..003 — executado via
-- `supabase db query --linked -f`. Cobre RBAC/RLS do catálogo de serviços,
-- geração de código, inativação (soft-disable), e a regra crítica de
-- snapshot imutável no item de orçamento.
begin;
select plan(16);

-- `supabase db query -f` só devolve o resultado da ÚLTIMA instrução do
-- arquivo — diferente de psql interativo. Para conseguir ver todas as 16
-- linhas TAP (ok/not ok) de uma vez, cada asserção é acumulada nesta tabela
-- temporária e só a SELECT final (antes do rollback) é lida pelo runner.
create temporary table tests_070_results (seq serial, line text);
grant insert, select on tests_070_results to authenticated, anon;
grant usage, select on tests_070_results_seq_seq to authenticated, anon;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario));

insert into clientes (id, tipo, nome) values ('99999999-9999-9999-9999-999999999999', 'externo', 'PGTAP Cliente Teste SERV');
insert into veiculos (id, cliente_id, placa) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '99999999-9999-9999-9999-999999999999', 'PGTAP004');
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '99999999-9999-9999-9999-999999999999', auth.uid());

-- SERV-001: criar serviço sem código explícito -> gerado automaticamente (SV-XXX).
do $$
declare v_id uuid;
begin
  v_id := rpc_criar_servico('PGTAP Substituição de compressor', 450.00);
  perform set_config('tests.serv001_id', v_id::text, true);
end $$;

-- SERV-002/003 fixture: um segundo serviço com código fixo, para testar duplicidade.
do $$
declare v_id uuid;
begin
  v_id := rpc_criar_servico('PGTAP Carga de gás', 200.00, 'SV-PGTAP01');
  perform set_config('tests.serv_fixo_id', v_id::text, true);
end $$;

-- SERV-004/005/006 fixture: serviço a ser inativado.
do $$
declare v_id uuid;
begin
  v_id := rpc_criar_servico('PGTAP Alinhamento', 120.00);
  perform set_config('tests.serv004_id', v_id::text, true);
end $$;
select rpc_inativar_servico(current_setting('tests.serv004_id')::uuid);

-- SERV-ORC-001/002 fixture: serviço vinculado a itens de orçamento.
do $$
declare v_servico_id uuid; v_item_id uuid;
begin
  v_servico_id := rpc_criar_servico('PGTAP Troca de embreagem', 450.00);
  perform set_config('tests.servA_id', v_servico_id::text, true);
  insert into orcamento_itens (orcamento_id, servico_id, descricao, quantidade, valor_unitario, codigo_servico_snapshot)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', v_servico_id, 'PGTAP Troca de embreagem', 1, 450.00,
    (select codigo from servicos where id = v_servico_id))
  returning id into v_item_id;
  perform set_config('tests.orc001_item_id', v_item_id::text, true);
end $$;

do $$
declare v_id uuid; v_item uuid;
begin
  v_id := rpc_criar_servico('PGTAP Revisão de freios', 450.00);
  perform set_config('tests.servB_id', v_id::text, true);
  insert into orcamento_itens (orcamento_id, servico_id, descricao, quantidade, valor_unitario, codigo_servico_snapshot)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', v_id, 'PGTAP Revisão de freios', 1, 480.00,
    (select codigo from servicos where id = v_id))
  returning id into v_item;
  perform set_config('tests.orc002_item_id', v_item::text, true);
end $$;

-- Após o fixture de SERV-ORC-001, altera o catálogo — o item já lançado não
-- pode mudar (regra crítica, instrução seção 8).
select rpc_atualizar_servico(current_setting('tests.servA_id')::uuid, 'PGTAP Troca de embreagem', 520.00);

-- Fixture dedicado (não depende de linha pré-existente em pecas) para o
-- teste de CHECK abaixo (peca_id + servico_id juntos no mesmo item).
do $$
declare v_id uuid;
begin
  insert into pecas (sku, descricao) values ('PGTAP-SERV-BONUS', 'PGTAP Peça bônus') returning id into v_id;
  perform set_config('tests.peca_bonus_id', v_id::text, true);
end $$;

insert into tests_070_results (line)
select throws_ok(
  format('select rpc_criar_servico(%L, %L, %L)', 'PGTAP Carga de gás duplicado', 300.00, 'SV-PGTAP01'),
  '23505', null,
  'SERV-002: código de serviço duplicado deve ser bloqueado (UNIQUE)'
)
union all
select throws_ok(
  format('select rpc_criar_servico(%L, %L)', 'PGTAP Serviço preço inválido', -10.00),
  'P0001', null,
  'SERV-003: preço de referência negativo deve ser bloqueado'
)
union all
select matches(
  (select codigo from servicos where id = current_setting('tests.serv001_id')::uuid),
  '^SV-\d{3}$',
  'SERV-001: código gerado automaticamente segue o padrão SV-XXX'
)
union all
select is(
  (select ativo from servicos where id = current_setting('tests.serv004_id')::uuid),
  false,
  'SERV-004: rpc_inativar_servico marca ativo=false (soft-disable)'
)
union all
select is(
  (select count(*)::int from servicos where id = current_setting('tests.serv004_id')::uuid and ativo = true),
  0,
  'SERV-005: serviço inativo não aparece no filtro usado para nova seleção (ativo=true)'
)
union all
select is(
  (select count(*)::int from servicos where id = current_setting('tests.serv004_id')::uuid),
  1,
  'SERV-006: serviço inativo continua visível (histórico/tela administrativa não filtra ativo)'
)
union all
select is(
  (select valor_unitario from orcamento_itens where id = current_setting('tests.orc001_item_id')::uuid),
  450.00::numeric,
  'SERV-ORC-001: alterar o preço do catálogo depois não muda o item de orçamento já salvo (snapshot)'
)
union all
select is(
  (select preco_referencia from servicos where id = current_setting('tests.servB_id')::uuid),
  450.00::numeric,
  'SERV-ORC-002: preço editado no item do orçamento (480) não altera o preço de referência do catálogo (450)'
)
union all
select is(
  (select valor_unitario from orcamento_itens where id = current_setting('tests.orc002_item_id')::uuid),
  480.00::numeric,
  'SERV-ORC-002b: item de orçamento preserva o preço efetivamente lançado (480), diferente da referência'
)
union all
select throws_ok(
  format(
    $sql$ insert into orcamento_itens (orcamento_id, peca_id, servico_id, descricao, quantidade, valor_unitario)
          values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', %L, %L, 'PGTAP inválido', 1, 10) $sql$,
    current_setting('tests.peca_bonus_id')::uuid, current_setting('tests.servA_id')::uuid
  ),
  '23514', null,
  'SERV-ORC-BONUS: CHECK orcamento_itens_peca_ou_servico_nao_ambos bloqueia peca_id e servico_id juntos'
);

-- SERV-ORC-003: mão de obra avulsa continua funcionando, sem servico_id.
-- natureza é coluna GERADA (peca_id e servico_id ambos null => 'servico_avulso').
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'PGTAP Serviço especial avulso', 1, 300.00);

insert into tests_070_results (line)
select is(
  (select count(*)::int from orcamento_itens
    where orcamento_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and natureza = 'servico_avulso' and servico_id is null and peca_id is null),
  1,
  'SERV-ORC-003: mão de obra avulsa (sem catálogo) continua funcionando'
);

-- SERV-007: executor não pode criar serviço.
select tests.autenticar_como(tests.criar_usuario_teste('executor'::perfil_usuario));
insert into tests_070_results (line)
select throws_ok(
  $$ select rpc_criar_servico('PGTAP Executor tentando criar', 100.00) $$,
  'P0001', null,
  'SERV-007: executor não consegue criar serviço no catálogo'
);

-- SERV-008: suporte_administrativo consegue criar (RBAC espelha Peças).
select tests.autenticar_como(tests.criar_usuario_teste('suporte_administrativo'::perfil_usuario));
insert into tests_070_results (line)
select isnt(
  rpc_criar_servico('PGTAP Criado por suporte', 90.00),
  null,
  'SERV-008: suporte_administrativo consegue criar serviço no catálogo'
);

-- SERV-009: anon bloqueado (RPC e SELECT).
select tests.autenticar_como_anon();
insert into tests_070_results (line)
select throws_ok(
  $$ select rpc_criar_servico('PGTAP Anon tentando criar', 100.00) $$,
  'P0001', null,
  'SERV-009: anon não consegue criar serviço via RPC'
);
insert into tests_070_results (line)
select is(
  (select count(*)::int from servicos),
  0,
  'SERV-009b: anon não consegue ler o catálogo (RLS bloqueia SELECT)'
);

-- SERV-010: usuário autenticado mas inativo (profiles.ativo=false) bloqueado.
-- Precisa voltar a um papel com permissão de UPDATE em profiles (policy
-- "profiles_update_admin" — só administrador_tecnico) ANTES de desativar o
-- usuário de teste; a atualização abaixo roda com o papel da sessão atual
-- (DO block não é SECURITY DEFINER), diferente de tests.criar_usuario_teste.
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario));
do $$
declare v_id uuid;
begin
  v_id := tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Inativo');
  update profiles set ativo = false where id = v_id;
  perform set_config('tests.inativo_id', v_id::text, true);
end $$;
select tests.autenticar_como(current_setting('tests.inativo_id')::uuid);
insert into tests_070_results (line)
select throws_ok(
  $$ select rpc_criar_servico('PGTAP Inativo tentando criar', 100.00) $$,
  'P0001', null,
  'SERV-010: usuário inativo (profiles.ativo=false) bloqueado mesmo autenticado'
);

select line from tests_070_results order by seq;

rollback;
