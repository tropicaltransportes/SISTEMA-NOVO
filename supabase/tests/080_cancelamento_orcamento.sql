-- FEATURE-ORCAMENTO-EXCLUSAO-01 — ORC-DEL-001..010, ORC-CAN-001..006,
-- ORC-REST-001..003, ORC-CONC-001 — executado via
-- `supabase db query --linked -f`. Cobre exclusão lógica de rascunho,
-- cancelamento formal pós-rascunho, bloqueio por OS ativa, RBAC, motivo
-- obrigatório, idempotência e restauração administrativa.
--
-- ORC-CONC-001 (concorrência real de duas sessões): pgTAP roda numa única
-- transação/sessão (mesmo motivo documentado em supabase/tests/README.md
-- para EST-013/EST-016/NFR-001/002/GAR-008), então este arquivo só prova o
-- INVARIANTE de estado final testando as duas ordens de execução possíveis
-- sequencialmente (excluir-depois-enviar e enviar-depois-excluir) — não
-- exercita a contenção real do `for update`. A prova de duas chamadas HTTP
-- verdadeiramente simultâneas fica no script dedicado
-- docs/testing/scripts/etapa8_orcexclusao_concorrencia.sh, mesmo padrão de
-- docs/testing/scripts/etapa7_concorrencia_*.sh.
begin;
select plan(32);

-- `supabase db query -f` só devolve o resultado da ÚLTIMA instrução do
-- arquivo — acumula cada asserção nesta tabela temporária (mesmo padrão de
-- supabase/tests/070_servicos.sql) para conseguir ver todas as linhas TAP.
create temporary table tests_080_results (seq serial, line text);
grant insert, select on tests_080_results to authenticated, anon;
grant usage, select on tests_080_results_seq_seq to authenticated, anon;

-- ============================================================
-- Fixtures compartilhadas: cliente/veículo interno (evita exigir
-- autorização de cliente externo para chegar a 'aprovado').
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado 080'));
insert into clientes (id, tipo, nome) values ('c8000000-0000-0000-0000-000000000001', 'interno', 'PGTAP Cliente Teste ORC-EXCLUSAO');
insert into veiculos (id, cliente_id, placa) values ('c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', 'PGTAP080');

-- ============================================================
-- ORC-DEL-001/002: rascunho sem OS, encarregado exclui com motivo válido.
-- ============================================================
select set_config('tests.enc080_id', auth.uid()::text, true);
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e1000000-0000-0000-0000-000000000001', 'PGTAP Item rascunho a excluir', 1, 100);

insert into tests_080_results (line)
select lives_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000001', 'Criado por engano em teste') $$,
  'ORC-DEL-001: rascunho sem OS pode ser excluído por encarregado'
);

-- RLS: não-admin (mesmo o próprio encarregado que acabou de excluir) deixa
-- de ver a linha imediatamente — checado ANTES de trocar de perfil, ainda
-- como o encarregado que excluiu.
insert into tests_080_results (line)
select is(
  (select count(*)::int from orcamentos where id = 'e1000000-0000-0000-0000-000000000001'),
  0,
  'ORC-DEL-001c: orçamento excluído não aparece nem para quem excluiu, se não for administrador_tecnico (RLS)'
);

-- deleted_at/deleted_by e a contagem de itens só são verificáveis por quem
-- a RLS deixa ver a linha excluída (administrador_tecnico) — SECURITY
-- DEFINER dentro da RPC não tem esse problema (ignora RLS), mas um SELECT
-- direto de teste tem.
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin 080'));
insert into tests_080_results (line)
select is(
  (select deleted_at is not null and deleted_by::text = current_setting('tests.enc080_id') from orcamentos where id = 'e1000000-0000-0000-0000-000000000001'),
  true,
  'ORC-DEL-001b: deleted_at/deleted_by preenchidos após exclusão'
);
insert into tests_080_results (line)
select is(
  (select count(*)::int from orcamento_itens where orcamento_id = 'e1000000-0000-0000-0000-000000000001'),
  1,
  'ORC-DEL-002: itens do rascunho excluído continuam no banco (histórico preservado)'
);
insert into tests_080_results (line)
select is(
  (select count(*)::int from orcamentos where id = 'e1000000-0000-0000-0000-000000000001'),
  1,
  'ORC-DEL-001d: administrador_tecnico continua vendo o orçamento excluído (RLS)'
);

-- Idempotência: repetir a exclusão nunca reprocessa nem corrompe estado.
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000001', 'Segunda tentativa') $$,
  'P0001', null,
  'ORC-DEL-BONUS-01: excluir um rascunho já excluído é bloqueado (idempotência), não reprocessa'
);

-- ============================================================
-- ORC-DEL-003/004: enviado / aprovado → tentar excluir. BLOQUEADO.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado 080b'));
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e1000000-0000-0000-0000-000000000002', 'PGTAP Item enviado', 1, 100);
select rpc_enviar_orcamento('e1000000-0000-0000-0000-000000000002');

insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000003', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e1000000-0000-0000-0000-000000000003', 'PGTAP Item aprovado', 1, 100);
select rpc_enviar_orcamento('e1000000-0000-0000-0000-000000000003');
select rpc_aprovar_orcamento('e1000000-0000-0000-0000-000000000003');

insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000002', 'Tentativa em enviado') $$,
  'P0001', null,
  'ORC-DEL-003: orçamento enviado não pode ser excluído'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000003', 'Tentativa em aprovado') $$,
  'P0001', null,
  'ORC-DEL-004: orçamento aprovado não pode ser excluído'
);

-- ============================================================
-- ORC-DEL-005/006: orçamento aprovado + OS ativa vinculada.
-- Excluir e cancelar de forma destrutiva devem ser bloqueados.
-- ============================================================
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000004', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e1000000-0000-0000-0000-000000000004', 'PGTAP Item com OS', 1, 100);
select rpc_enviar_orcamento('e1000000-0000-0000-0000-000000000004');
select rpc_aprovar_orcamento('e1000000-0000-0000-0000-000000000004');
select rpc_criar_os('c8000000-0000-0000-0000-000000000002', 'interna'::tipo_os, 'e1000000-0000-0000-0000-000000000004');

insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000004', 'Tentativa com OS ativa') $$,
  'P0001', null,
  'ORC-DEL-005: orçamento convertido em OS ativa não pode ser excluído'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_cancelar_orcamento('e1000000-0000-0000-0000-000000000004', 'Tentativa de cancelar com OS ativa') $$,
  'P0001', null,
  'ORC-DEL-006: orçamento com OS ativa não pode ser cancelado (regra de bloqueio por OS, BR-008/BR-046)'
);

-- ============================================================
-- ORC-DEL-007/008/009: RBAC — executor, anon e usuário inativo bloqueados.
-- ============================================================
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000005', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());

select tests.autenticar_como(tests.criar_usuario_teste('executor'::perfil_usuario, 'PGTAP Executor 080'));
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000005', 'Executor tentando excluir') $$,
  'P0001', null,
  'ORC-DEL-007: executor não consegue excluir orçamento'
);

select tests.autenticar_como_anon();
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000005', 'Anon tentando excluir') $$,
  'P0001', null,
  'ORC-DEL-008: anon não consegue excluir orçamento'
);

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin 080b'));
do $$
declare v_id uuid;
begin
  v_id := tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Inativo 080');
  update profiles set ativo = false where id = v_id;
  perform set_config('tests.inativo_080_id', v_id::text, true);
end $$;
select tests.autenticar_como(current_setting('tests.inativo_080_id')::uuid);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000005', 'Inativo tentando excluir') $$,
  'P0001', null,
  'ORC-DEL-009: usuário inativo (profiles.ativo=false) bloqueado mesmo com perfil encarregado'
);

-- ============================================================
-- ORC-DEL-010: exclusão sem motivo (ou motivo curto demais). BLOQUEADO.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado 080c'));
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e1000000-0000-0000-0000-000000000006', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e1000000-0000-0000-0000-000000000006', 'PGTAP Item rascunho motivo invalido', 1, 100);

insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000006', null) $$,
  'P0001', null,
  'ORC-DEL-010: exclusão sem motivo é bloqueada'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000006', 'abc') $$,
  'P0001', null,
  'ORC-DEL-010b: exclusão com motivo abaixo de 5 caracteres é bloqueada'
);

-- ============================================================
-- ORC-CAN-001..006: cancelamento formal pós-rascunho.
-- ============================================================
select rpc_enviar_orcamento('e1000000-0000-0000-0000-000000000006'); -- reaproveita o rascunho acima, agora com motivo válido no cancelamento
insert into tests_080_results (line)
select lives_ok(
  $$ select rpc_cancelar_orcamento('e1000000-0000-0000-0000-000000000006', 'Cliente desistiu do serviço') $$,
  'ORC-CAN-001: orçamento enviado sem OS pode ser cancelado com motivo válido'
);
insert into tests_080_results (line)
select is(
  (select status::text from orcamentos where id = 'e1000000-0000-0000-0000-000000000006'),
  'cancelado',
  'ORC-CAN-001b: status muda para cancelado, histórico (linha) mantido'
);
insert into tests_080_results (line)
select is(
  (select cancelado_por is not null and cancelado_em is not null and cancelamento_motivo = 'Cliente desistiu do serviço'
     from orcamentos where id = 'e1000000-0000-0000-0000-000000000006'),
  true,
  'ORC-CAN-001c: cancelado_por/cancelado_em/cancelamento_motivo registrados'
);

insert into tests_080_results (line)
select throws_ok(
  $$ insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
     values ('e1000000-0000-0000-0000-000000000006', 'Item pos cancelamento', 1, 10) $$,
  '42501', null,
  'ORC-CAN-002: orçamento cancelado não pode receber novo item (RLS exige status=rascunho)'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_aplicar_desconto_orcamento('e1000000-0000-0000-0000-000000000006', 10, null, 'Desconto pos cancelamento') $$,
  'P0001', null,
  'ORC-CAN-003: orçamento cancelado não pode receber desconto'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_enviar_orcamento('e1000000-0000-0000-0000-000000000006') $$,
  'P0001', null,
  'ORC-CAN-004: orçamento cancelado não pode ser (re)enviado'
);
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_criar_os('c8000000-0000-0000-0000-000000000002', 'interna'::tipo_os, 'e1000000-0000-0000-0000-000000000006') $$,
  'P0001', null,
  'ORC-CAN-005: orçamento cancelado não pode gerar OS'
);
insert into tests_080_results (line)
select is(
  (select rpc_dados_pdf_orcamento('e1000000-0000-0000-0000-000000000006') -> 'orcamento' ->> 'status'),
  'cancelado',
  'ORC-CAN-006: PDF continua disponível e indica status cancelado'
);

-- Idempotência de cancelamento.
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_cancelar_orcamento('e1000000-0000-0000-0000-000000000006', 'Segunda tentativa') $$,
  'P0001', null,
  'ORC-CAN-BONUS-01: cancelar um orçamento já cancelado é bloqueado (idempotência)'
);

-- RBAC de cancelamento (não numerado na especificação original, cobertura extra).
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e2000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e2000000-0000-0000-0000-000000000001', 'PGTAP Item RBAC cancelamento', 1, 100);
select rpc_enviar_orcamento('e2000000-0000-0000-0000-000000000001');
select tests.autenticar_como(tests.criar_usuario_teste('executor'::perfil_usuario, 'PGTAP Executor Cancelamento'));
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_cancelar_orcamento('e2000000-0000-0000-0000-000000000001', 'Executor tentando cancelar') $$,
  'P0001', null,
  'ORC-CAN-BONUS-02: executor não consegue cancelar orçamento'
);

-- ============================================================
-- ORC-REST-001/002/003: restauração administrativa.
-- ============================================================
-- REST-001: administrador_tecnico restaura o rascunho excluído em DEL-001.
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin Restaura'));
insert into tests_080_results (line)
select lives_ok(
  $$ select rpc_restaurar_orcamento_excluido('e1000000-0000-0000-0000-000000000001', 'Restaurado após confirmação com o cliente') $$,
  'ORC-REST-001: administrador_tecnico restaura orçamento excluído'
);
insert into tests_080_results (line)
select is(
  (select deleted_at from orcamentos where id = 'e1000000-0000-0000-0000-000000000001'),
  null,
  'ORC-REST-001b: deleted_at volta a null após restauração'
);
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado Verifica Restauro'));
insert into tests_080_results (line)
select is(
  (select count(*)::int from orcamentos where id = 'e1000000-0000-0000-0000-000000000001'),
  1,
  'ORC-REST-001c: orçamento restaurado volta a aparecer para perfil não-admin (RLS)'
);

-- REST-002: encarregado (perfil que PODE excluir) não pode restaurar.
select rpc_excluir_orcamento_rascunho('e1000000-0000-0000-0000-000000000005', 'Exclusão para testar RBAC de restauração');
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_restaurar_orcamento_excluido('e1000000-0000-0000-0000-000000000005', null) $$,
  'P0001', null,
  'ORC-REST-002: encarregado não consegue restaurar orçamento excluído (só administrador_tecnico)'
);

-- REST-003: restaurar orçamento que nunca foi excluído. Bloqueado.
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin Restaura Invalido'));
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_restaurar_orcamento_excluido('e1000000-0000-0000-0000-000000000002', null) $$,
  'P0001', null,
  'ORC-REST-003: restaurar orçamento que não está excluído é bloqueado'
);

-- ============================================================
-- ORC-CONC-001: invariante de concorrência (ver nota no topo do arquivo).
-- Duas ordens de execução possíveis para exclusão vs envio do mesmo
-- rascunho — em nenhuma delas o estado final é enviado+deleted_at juntos.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado Concorrencia'));

-- Ordem A: exclui primeiro, depois tenta enviar -> enviar deve falhar.
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e4000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e4000000-0000-0000-0000-000000000001', 'PGTAP Item concorrencia A', 1, 100);
select rpc_excluir_orcamento_rascunho('e4000000-0000-0000-0000-000000000001', 'Vence a corrida: exclusão primeiro');
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_enviar_orcamento('e4000000-0000-0000-0000-000000000001') $$,
  'P0001', null,
  'ORC-CONC-001a: se a exclusão vence a corrida, o envio subsequente é bloqueado (nunca enviado+deleted_at)'
);

-- Ordem B: envia primeiro, depois tenta excluir -> exclusão deve falhar.
insert into orcamentos (id, veiculo_id, cliente_id, criado_por)
values ('e4000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
values ('e4000000-0000-0000-0000-000000000002', 'PGTAP Item concorrencia B', 1, 100);
select rpc_enviar_orcamento('e4000000-0000-0000-0000-000000000002');
insert into tests_080_results (line)
select throws_ok(
  $$ select rpc_excluir_orcamento_rascunho('e4000000-0000-0000-0000-000000000002', 'Vence a corrida: envio primeiro') $$,
  'P0001', null,
  'ORC-CONC-001b: se o envio vence a corrida, a exclusão subsequente é bloqueada (nunca enviado+deleted_at)'
);

select line from tests_080_results order by seq;

rollback;
