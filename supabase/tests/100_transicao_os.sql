-- ETAPA OS-FLOW-03 — OS-FLOW-001..006, OS-AP-003, OS-ADP-002..004 —
-- executado via `npx supabase db query --linked -f`. Cobre o bloqueio de
-- transição/conclusão com apontamento aberto e o retorno controlado de
-- fase (aguardando_teste -> em_execucao -> em_diagnostico), acrescentados
-- em 20260819180000_p2e_os_fluxo_transicoes.sql. Ver
-- docs/testing/BUSINESS_RULES.md BR-052/BR-053.
--
-- OS-ADP-001 (peça adicional aprovada aparece no escopo da OS como
-- "aprovada/pendente de utilização") é comportamento de apresentação
-- (frontend) — não testável por pgTAP, verificado por clique real no
-- browser (ver docs/testing/TEST_REPORT_OS_FLOW03.md).
begin;
select plan(16);

create temporary table tests_100_results (seq serial, line text);
grant insert, select on tests_100_results to authenticated, anon;
grant usage, select on tests_100_results_seq_seq to authenticated, anon;

-- ============================================================
-- Helper: OS interna simples em 'em_execucao' (sem apontamento).
-- ============================================================
create or replace function tests._flow100_os_em_execucao()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os uuid;
begin
  v_os := rpc_criar_os('f3000000-0000-0000-0000-000000000002'::uuid, 'interna'::tipo_os);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  return v_os;
end;
$$;

-- Helper: monta uma OS externa liberada (orçamento aprovado -> concluida
-- via bypass de teste -> cobrança quitada -> rpc_liberar_os), pro
-- OS-FLOW-006. Precisa ser SECURITY DEFINER (não um do $$ $$ anônimo,
-- e precisa ser criada AQUI, antes de tests.autenticar_como() trocar de
-- papel) porque escreve direto em orcamentos/orcamento_itens/
-- ordens_servico — mesmo motivo de tests._preparar_os_concluida em
-- supabase/tests/040_liberacao.sql (esses writes normalmente só passam
-- por RPC; o papel "authenticated" de teste não tem GRANT direto neles).
create or replace function tests._flow100_os_liberada()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_orc uuid; v_os uuid; v_cob uuid; v_parcela uuid; v_item uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('f3000000-0000-0000-0000-000000000004', 'f3000000-0000-0000-0000-000000000003', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values (v_orc, 'PGTAP Serviço FLOW006', 1, 500)
    returning id into v_item;
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid() where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('f3000000-0000-0000-0000-000000000004'::uuid, 'externa'::tipo_os, v_orc);
  -- ETAPA OS-ESCOPO-04: cobrança só soma item efetivamente executado.
  perform rpc_marcar_item_orcamento_execucao(v_item, 'executado');
  update ordens_servico set status = 'concluida' where id = v_os;
  v_cob := rpc_criar_cobranca('f3000000-0000-0000-0000-000000000003'::uuid, array[v_os], null);
  perform rpc_parcelar_cobranca(v_cob, jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'valor', 500, 'vencimento', current_date)));
  select id into v_parcela from parcelas where cobranca_id = v_cob;
  perform rpc_registrar_recebimento(v_parcela, 500, 'pix', current_date);
  perform rpc_liberar_os(v_os);
  return v_os;
end;
$$;

-- ============================================================
-- Fixtures compartilhadas
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin 100'));

insert into clientes (id, tipo, nome) values
  ('f3000000-0000-0000-0000-000000000001', 'interno', 'PGTAP Cliente Interno FLOW03'),
  ('f3000000-0000-0000-0000-000000000003', 'externo', 'PGTAP Cliente Externo FLOW03');
insert into veiculos (id, cliente_id, placa) values
  ('f3000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000001', 'PGF03A'),
  ('f3000000-0000-0000-0000-000000000004', 'f3000000-0000-0000-0000-000000000003', 'PGF03B');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('f3000000-0000-0000-0000-000000000005', 'PGTAP-FLOW03', 'PGTAP Peça FLOW03', 'UN', 100, 10, 0);

-- ============================================================
-- OS-FLOW-001 — Execução + apontamento aberto -> avançar para Teste: BLOQUEADO.
-- ============================================================
do $$
declare v_os uuid; v_exec uuid;
begin
  v_os := tests._flow100_os_em_execucao();
  insert into os_executores (os_id, usuario_id, etapa, inicio) values (v_os, auth.uid(), 'execucao', now()) returning id into v_exec;
  perform set_config('tests.flow001_os', v_os::text, true);
end $$;

insert into tests_100_results (line)
select throws_ok(
  format('select rpc_transicionar_os(%L, %L::status_os)', current_setting('tests.flow001_os')::uuid, 'aguardando_teste'),
  'P0001', 'Finalize o apontamento em andamento antes de transicionar esta OS.',
  'OS-FLOW-001: Execução + apontamento aberto -> avançar para Teste é bloqueado'
);

-- ============================================================
-- OS-FLOW-002 — fecha o apontamento, avançar para Teste passa.
-- ============================================================
update os_executores set fim = now() where os_id = current_setting('tests.flow001_os')::uuid and fim is null;

insert into tests_100_results (line)
select lives_ok(
  format('select rpc_transicionar_os(%L, %L::status_os)', current_setting('tests.flow001_os')::uuid, 'aguardando_teste'),
  'OS-FLOW-002: com apontamento fechado, avançar para Teste é permitido'
);
insert into tests_100_results (line)
select is(
  (select status::text from ordens_servico where id = current_setting('tests.flow001_os')::uuid),
  'aguardando_teste',
  'OS-FLOW-002: status realmente virou aguardando_teste'
);

-- ============================================================
-- OS-AP-003 — mesma OS (agora em Teste), com NOVO apontamento aberto,
-- tentar concluir: BLOQUEADO (item 11 do pedido).
-- ============================================================
insert into os_executores (os_id, usuario_id, etapa, inicio) values (current_setting('tests.flow001_os')::uuid, auth.uid(), 'teste', now());

insert into tests_100_results (line)
select throws_ok(
  format('select rpc_concluir_os(%L)', current_setting('tests.flow001_os')::uuid),
  'P0001', 'Finalize o apontamento em andamento antes de concluir esta OS.',
  'OS-AP-003: OS em Teste com apontamento aberto não pode ser concluída'
);

update os_executores set fim = now() where os_id = current_setting('tests.flow001_os')::uuid and fim is null;

-- ============================================================
-- OS-FLOW-003 — Teste -> Retornar para Execução com motivo: PASSA + audita.
-- ============================================================
insert into tests_100_results (line)
select lives_ok(
  format('select rpc_transicionar_os(%L, %L::status_os, %L)', current_setting('tests.flow001_os')::uuid, 'em_execucao', 'Vazamento identificado durante teste final.'),
  'OS-FLOW-003: Teste -> Execução com motivo é permitido'
);
insert into tests_100_results (line)
select is(
  (select status::text from ordens_servico where id = current_setting('tests.flow001_os')::uuid),
  'em_execucao',
  'OS-FLOW-003: status voltou para em_execucao'
);
insert into tests_100_results (line)
select is(
  (select motivo from auditoria_eventos where entidade = 'ordens_servico' and entidade_id = current_setting('tests.flow001_os')::uuid and acao = 'OS_RETORNOU_PARA_EXECUCAO' order by criado_em desc limit 1),
  'Vazamento identificado durante teste final.',
  'OS-FLOW-003: evento OS_RETORNOU_PARA_EXECUCAO auditado com o motivo certo'
);

-- ============================================================
-- OS-FLOW-004 — Teste -> Execução SEM motivo: BLOQUEADO (fixture própria).
-- ============================================================
do $$
declare v_os uuid; v_exec uuid;
begin
  v_os := tests._flow100_os_em_execucao();
  insert into os_executores (os_id, usuario_id, etapa, inicio) values (v_os, auth.uid(), 'execucao', now()) returning id into v_exec;
  update os_executores set fim = now() where id = v_exec;
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);
  perform set_config('tests.flow004_os', v_os::text, true);
end $$;

insert into tests_100_results (line)
select throws_ok(
  format('select rpc_transicionar_os(%L, %L::status_os)', current_setting('tests.flow004_os')::uuid, 'em_execucao'),
  'P0001', 'Retornar de aguardando_teste para em_execucao exige motivo (mínimo 5 caracteres) — ação auditável',
  'OS-FLOW-004: Teste -> Execução sem motivo é bloqueado'
);

-- ============================================================
-- OS-FLOW-005 — ciclo Execução -> Teste -> Execução -> Teste, histórico
-- preservado (nenhum apontamento antigo é reaberto/apagado).
-- ============================================================
do $$
declare v_os uuid; v_exec1 uuid; v_exec2 uuid; v_exec3 uuid;
begin
  v_os := tests._flow100_os_em_execucao();
  insert into os_executores (os_id, usuario_id, etapa, inicio) values (v_os, auth.uid(), 'execucao', now()) returning id into v_exec1;
  update os_executores set fim = now() where id = v_exec1;
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);

  insert into os_executores (os_id, usuario_id, etapa, inicio) values (v_os, auth.uid(), 'teste', now()) returning id into v_exec2;
  update os_executores set fim = now() where id = v_exec2;
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os, 'Retorno de teste 1 — regressão do OS-FLOW-005.');

  insert into os_executores (os_id, usuario_id, etapa, inicio) values (v_os, auth.uid(), 'execucao', now()) returning id into v_exec3;
  update os_executores set fim = now() where id = v_exec3;
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);

  perform set_config('tests.flow005_os', v_os::text, true);
  perform set_config('tests.flow005_exec1', v_exec1::text, true);
end $$;

insert into tests_100_results (line)
select is(
  (select status::text from ordens_servico where id = current_setting('tests.flow005_os')::uuid),
  'aguardando_teste',
  'OS-FLOW-005: ciclo Execução->Teste->Execução->Teste termina em Teste'
);
insert into tests_100_results (line)
select is(
  (select count(*)::int from os_executores where os_id = current_setting('tests.flow005_os')::uuid),
  3,
  'OS-FLOW-005: 3 apontamentos distintos existem (nenhum reaproveitado)'
);
insert into tests_100_results (line)
select is(
  (select fim is not null from os_executores where id = current_setting('tests.flow005_exec1')::uuid),
  true,
  'OS-FLOW-005: o apontamento mais antigo continua fechado (não foi reaberto pelo retorno)'
);

-- ============================================================
-- OS-FLOW-006 — Liberada -> Execução: BLOQUEADO (liberada não é origem de
-- nenhuma tupla, forward ou retrocesso).
-- ============================================================
select set_config('tests.flow006_os', tests._flow100_os_liberada()::text, true);

insert into tests_100_results (line)
select throws_ok(
  format('select rpc_transicionar_os(%L, %L::status_os)', current_setting('tests.flow006_os')::uuid, 'em_execucao'),
  'P0001', null,
  'OS-FLOW-006: Liberada -> Execução é bloqueado (transição não permitida)'
);

-- ============================================================
-- OS-ADP-002/003/004 — peça de adicional: aprovado != utilizado; item
-- rejeitado nunca pode ser utilizado. Regra já existente (rpc_baixar_peca_os
-- e a separação status_aprovacao/execucao_status não foram alteradas nesta
-- etapa) — cobertura explícita pedida no item 33.
-- ============================================================
do $$
declare v_os uuid; v_adicional uuid; v_item_ok uuid; v_item_rej uuid;
begin
  v_os := tests._flow100_os_em_execucao();
  v_adicional := rpc_criar_os_adicional(v_os, 'PGTAP FLOW03: peça extra identificada', gen_random_uuid());
  perform rpc_incluir_item_os_adicional(v_adicional, 'f3000000-0000-0000-0000-000000000005'::uuid, 'PGTAP Peça adicional', 5, 10, null);
  select id into v_item_ok from os_adicional_itens where adicional_id = v_adicional;
  perform rpc_decidir_item_os_adicional(v_item_ok, 'aprovado', 'sistema', 'PGTAP Cliente Teste', null, null);

  v_adicional := rpc_criar_os_adicional(v_os, 'PGTAP FLOW03: peça extra rejeitada', gen_random_uuid());
  perform rpc_incluir_item_os_adicional(v_adicional, 'f3000000-0000-0000-0000-000000000005'::uuid, 'PGTAP Peça adicional rejeitada', 2, 10, null);
  select id into v_item_rej from os_adicional_itens where adicional_id = v_adicional;
  perform rpc_decidir_item_os_adicional(v_item_rej, 'rejeitado', 'sistema', 'PGTAP Cliente Teste', null, null);

  perform set_config('tests.adp_os', v_os::text, true);
  perform set_config('tests.adp_item_ok', v_item_ok::text, true);
  perform set_config('tests.adp_item_rej', v_item_rej::text, true);
end $$;

insert into tests_100_results (line)
select is(
  (select execucao_status from os_adicional_itens where id = current_setting('tests.adp_item_ok')::uuid),
  'pendente',
  'OS-ADP-002: item aprovado ainda não utilizado continua execucao_status=pendente (aprovado != utilizado)'
);

insert into tests_100_results (line)
select lives_ok(
  format('select rpc_baixar_peca_os(%L, %L, %L, p_os_adicional_item_id := %L)', current_setting('tests.adp_os')::uuid, 'f3000000-0000-0000-0000-000000000005'::uuid, 5, current_setting('tests.adp_item_ok')::uuid),
  'OS-ADP-003: registrar utilização (baixa) do item aprovado é permitido'
);
insert into tests_100_results (line)
select is(
  (select execucao_status from os_adicional_itens where id = current_setting('tests.adp_item_ok')::uuid),
  'executado',
  'OS-ADP-003: após baixar a quantidade toda aprovada, execucao_status vira executado'
);

insert into tests_100_results (line)
select throws_ok(
  format('select rpc_baixar_peca_os(%L, %L, %L, p_os_adicional_item_id := %L)', current_setting('tests.adp_os')::uuid, 'f3000000-0000-0000-0000-000000000005'::uuid, 1, current_setting('tests.adp_item_rej')::uuid),
  'P0001', null,
  'OS-ADP-004: item de adicional rejeitado nunca pode ser utilizado (baixa bloqueada)'
);

select line from tests_100_results order by seq;

rollback;
