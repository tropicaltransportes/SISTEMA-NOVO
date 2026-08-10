-- LIB-001, LIB-002, LIB-003 — NÃO EXECUTADO (ver supabase/tests/README.md).
-- Monta 3 OS externas concluídas idênticas, cada uma variando só a condição
-- financeira, e confirma que rpc_liberar_os segue exatamente BR-023.
begin;
select plan(3);
\i _helpers.sql

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario));

insert into clientes (id, tipo, nome) values ('66666666-6666-6666-6666-666666666666', 'externo', 'Cliente Teste LIB');
insert into veiculos (id, cliente_id, placa) values ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', 'TST0002');

-- Helper local: cria orçamento aprovado simples e a OS externa já 'concluida'.
create or replace function tests._preparar_os_concluida(p_sufixo text) returns uuid language plpgsql as $$
declare
  v_orc uuid; v_os uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values (v_orc, 'Serviço ' || p_sufixo, 1, 500);
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('77777777-7777-7777-7777-777777777777'::uuid, 'externa'::tipo_os, v_orc);
  -- força a OS direto para 'concluida' via updates internos de teste (bypassa a máquina de estados só para montar o fixture)
  update ordens_servico set status = 'concluida' where id = v_os;
  return v_os;
end;
$$;

-- LIB-003: sem pagamento e sem termo -> bloqueada.
select throws_ok(
  format('select rpc_liberar_os(%L)', tests._preparar_os_concluida('LIB003')),
  'P0001', 'OS externa exige cobrança gerada antes da liberação',
  'LIB-003: OS externa concluída sem cobrança nenhuma deve ser bloqueada na liberação'
);

-- LIB-002: termo de ciência de débito, sem pagamento -> liberação permitida.
do $$
declare v_os uuid; v_cob uuid;
begin
  v_os := tests._preparar_os_concluida('LIB002');
  v_cob := rpc_criar_cobranca('66666666-6666-6666-6666-666666666666'::uuid, array[v_os], null);
  perform rpc_registrar_termo_ciencia(v_cob, 'termos/teste.pdf');
  perform rpc_liberar_os(v_os);
  perform set_config('tests.lib002_os', v_os::text, true);
end $$;

select is(
  (select status from ordens_servico where id = current_setting('tests.lib002_os')::uuid),
  'liberada',
  'LIB-002: liberação com Termo de Ciência de Débito (sem pagamento) deve ser permitida'
);

-- LIB-001: cobrança quitada -> liberação permitida.
do $$
declare v_os uuid; v_cob uuid; v_parcela uuid;
begin
  v_os := tests._preparar_os_concluida('LIB001');
  v_cob := rpc_criar_cobranca('66666666-6666-6666-6666-666666666666'::uuid, array[v_os], null);
  perform rpc_parcelar_cobranca(v_cob, jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'valor', 500, 'vencimento', current_date)));
  select id into v_parcela from parcelas where cobranca_id = v_cob;
  perform rpc_registrar_recebimento(v_parcela, 500, 'pix', current_date);
  perform rpc_liberar_os(v_os);
  perform set_config('tests.lib001_os', v_os::text, true);
end $$;

select is(
  (select status from ordens_servico where id = current_setting('tests.lib001_os')::uuid),
  'liberada',
  'LIB-001: liberação com cobrança quitada deve ser permitida'
);

select * from finish();
rollback;
