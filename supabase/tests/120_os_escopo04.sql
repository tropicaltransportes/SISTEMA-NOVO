-- ETAPA OS-ESCOPO-04 — OS-SCOPE-001..007 (seções 28-34 do pedido).
-- "Aprovado" deixa de significar "obrigatoriamente executado/utilizado":
-- OS pode concluir com escopo menor que o orçamento; encarregado/admin
-- podem editar (reduzir) quantidade e remover item ainda não utilizado do
-- escopo operacional, sem tocar no orçamento aprovado (histórico intacto).
begin;
select plan(15);

-- db query --linked -f só devolve o resultset do ÚLTIMO statement — mesmo
-- padrão de supabase/tests/090_cancelamento_os.sql: acumula cada resultado
-- numa tabela temporária e só no fim faz um único select final.
create temporary table tests_120_results (seq serial, line text);
grant insert, select on tests_120_results to authenticated, anon;
grant usage, select on tests_120_results_seq_seq to authenticated, anon;

-- Helper: orçamento aprovado com N itens (peça ou mão de obra) + veículo/
-- cliente próprios (mesmo padrão de tests._can090_orcamento_aprovado em
-- 090_cancelamento_os.sql).
create or replace function tests._esc04_orcamento_aprovado(
  p_veiculo_id uuid, p_cliente_id uuid, p_itens jsonb,
  out v_orc uuid, out v_item_ids uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_item_id uuid;
begin
  v_item_ids := array[]::uuid[];
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values (p_veiculo_id, p_cliente_id, auth.uid(), 'rascunho')
    returning id into v_orc;
  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
      values (v_orc, nullif(v_item->>'peca_id', '')::uuid, v_item->>'descricao', (v_item->>'quantidade')::numeric, (v_item->>'valor_unitario')::numeric)
      returning id into v_item_id;
    v_item_ids := array_append(v_item_ids, v_item_id);
  end loop;
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid() where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
end;
$$;

-- ordens_servico tem "revoke update from authenticated" (todo write passa
-- por RPC) — bypass de teste para atribuir o checklist vazio (mesma
-- convenção de tests._can090_forcar_concluida em 090_cancelamento_os.sql).
create or replace function tests._esc04_definir_checklist(p_os_id uuid, p_template_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update ordens_servico set checklist_template_id = p_template_id where id = p_os_id;
end;
$$;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin ESC04'));

insert into clientes (id, tipo, nome) values
  ('e5000000-0000-0000-0000-000000000001', 'externo', 'PGTAP Cliente ESC04'),
  ('e5000000-0000-0000-0000-000000000005', 'interno', 'PGTAP Cliente Interno ESC04');
insert into veiculos (id, cliente_id, placa) values
  ('e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001', 'PGTAPE04'),
  ('e5000000-0000-0000-0000-000000000006', 'e5000000-0000-0000-0000-000000000005', 'PGTAPE05');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('e5000000-0000-0000-0000-000000000003', 'PGTAP_ESC04_PECA_A', 'PGTAP Peça A ESC04', 'UN', 50, 20, 1),
  ('e5000000-0000-0000-0000-000000000004', 'PGTAP_ESC04_PECA_B', 'PGTAP Peça B ESC04', 'UN', 50, 20, 1);
-- Checklist vazio (sem itens obrigatórios, sem exigência de foto) — isola o
-- teste no gate de escopo, não no de checklist/fotos (mesma convenção já
-- usada em supabase/tests/110_documento_final_os.sql: aquele bypassa
-- rpc_concluir_os inteiro; aqui precisamos chamar a RPC de verdade, então
-- montamos um checklist que nunca bloqueia sozinho).
insert into checklist_templates (id, nome) values ('e5000000-0000-0000-0000-000000000099', 'PGTAP Checklist Vazio ESC04');

-- ============================================================
-- OS-SCOPE-001: concluir sem usar toda a peça aprovada nem todo serviço.
-- ============================================================
do $$
declare
  v_orc uuid; v_items uuid[]; v_item_a uuid; v_item_b uuid; v_item_c uuid; v_os uuid;
  v_doc jsonb;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(
      jsonb_build_object('peca_id', 'e5000000-0000-0000-0000-000000000003', 'descricao', 'PGTAP Peça A SCOPE001', 'quantidade', 2, 'valor_unitario', 50),
      jsonb_build_object('peca_id', 'e5000000-0000-0000-0000-000000000004', 'descricao', 'PGTAP Peça B SCOPE001 (não utilizada)', 'quantidade', 1, 'valor_unitario', 30),
      jsonb_build_object('descricao', 'PGTAP Serviço C SCOPE001', 'quantidade', 1, 'valor_unitario', 100)
    ));
  v_item_a := v_items[1]; v_item_b := v_items[2]; v_item_c := v_items[3];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  perform tests._esc04_definir_checklist(v_os, 'e5000000-0000-0000-0000-000000000099');
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  perform rpc_baixar_peca_os(v_os, 'e5000000-0000-0000-0000-000000000003'::uuid, 2, null, v_item_a, null);
  perform rpc_marcar_item_orcamento_execucao(v_item_c, 'executado');
  -- Peça B nunca é baixada — deliberadamente não utilizada.
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);
  perform set_config('tests.scope001_os', v_os::text, true);
end $$;

insert into tests_120_results (line) select lives_ok(
  format('select rpc_concluir_os(%L)', current_setting('tests.scope001_os')::uuid),
  'OS-SCOPE-001: OS conclui normalmente mesmo com peça aprovada não utilizada e sem exigir dispensa manual item a item'
);

insert into tests_120_results (line) select is(
  jsonb_array_length(rpc_documento_final_os(current_setting('tests.scope001_os')::uuid) -> 'pecas'),
  1,
  'OS-SCOPE-001: documento final lista só a peça efetivamente utilizada (A), não a não utilizada (B)'
);

insert into tests_120_results (line) select is(
  (rpc_documento_final_os(current_setting('tests.scope001_os')::uuid) -> 'resumo_financeiro' ->> 'valor_final')::numeric,
  200.00,
  'OS-SCOPE-001: valor final reflete só o executado (2×50 peça A + 100 serviço C = 200), não o total aprovado (2×50+1×30+100=230)'
);

-- ============================================================
-- OS-SCOPE-002: remover item aprovado ainda não utilizado.
-- ============================================================
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid; v_escopo_id uuid;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('descricao', 'PGTAP Item SCOPE002', 'quantidade', 1, 'valor_unitario', 80)));
  v_item := v_items[1];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  select id into v_escopo_id from os_escopo_itens where os_id = v_os and orcamento_item_id = v_item;
  perform rpc_remover_item_escopo_os(v_escopo_id, 'PGTAP: não foi necessário durante a execução');
  perform set_config('tests.scope002_escopo', v_escopo_id::text, true);
  perform set_config('tests.scope002_item', v_item::text, true);
end $$;

insert into tests_120_results (line) select is(
  (select execucao_status from os_escopo_itens where id = current_setting('tests.scope002_escopo')::uuid),
  'cancelado',
  'OS-SCOPE-002: item removido some do escopo operacional (execucao_status=cancelado)'
);
insert into tests_120_results (line) select is(
  (select status_aprovacao from orcamento_itens where id = current_setting('tests.scope002_item')::uuid),
  'aprovado',
  'OS-SCOPE-002: orçamento histórico permanece intacto (item continua aprovado, não é apagado nem alterado)'
);
insert into tests_120_results (line) select is(
  (select count(*)::int from auditoria_eventos where entidade = 'os_escopo_itens' and entidade_id = current_setting('tests.scope002_escopo')::uuid and acao = 'os_item_removido'),
  1,
  'OS-SCOPE-002: remoção é auditada'
);

-- ============================================================
-- OS-SCOPE-003: editar quantidade (reduzir) — estoque/documento respeitam
-- o novo teto, orçamento histórico continua com a quantidade original.
-- ============================================================
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid; v_escopo_id uuid;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('peca_id', 'e5000000-0000-0000-0000-000000000003', 'descricao', 'PGTAP Item SCOPE003', 'quantidade', 5, 'valor_unitario', 20)));
  v_item := v_items[1];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  select id into v_escopo_id from os_escopo_itens where os_id = v_os and orcamento_item_id = v_item;
  perform rpc_editar_item_escopo_os(v_escopo_id, p_quantidade => 3, p_motivo => 'PGTAP: reduzido conforme necessidade real');
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  perform rpc_baixar_peca_os(v_os, 'e5000000-0000-0000-0000-000000000003'::uuid, 3, null, v_item, null);
  perform set_config('tests.scope003_os', v_os::text, true);
  perform set_config('tests.scope003_item', v_item::text, true);
  perform set_config('tests.scope003_peca', 'e5000000-0000-0000-0000-000000000003', true);
end $$;

insert into tests_120_results (line) select throws_ok(
  format('select rpc_baixar_peca_os(%L::uuid, %L::uuid, 1, null, %L::uuid, null)',
    current_setting('tests.scope003_os'), current_setting('tests.scope003_peca'), current_setting('tests.scope003_item')),
  'P0001', null,
  'OS-SCOPE-003: baixar além do escopo reduzido (3) é bloqueado mesmo o orçamento tendo aprovado 5'
);
insert into tests_120_results (line) select is(
  (select quantidade from orcamento_itens where id = current_setting('tests.scope003_item')::uuid),
  5::numeric,
  'OS-SCOPE-003: quantidade aprovada no orçamento histórico continua 5 (edição de escopo não reescreve o orçamento)'
);
insert into tests_120_results (line) select is(
  (rpc_documento_final_os(current_setting('tests.scope003_os')::uuid) -> 'pecas' -> 0 ->> 'quantidade')::numeric,
  3::numeric,
  'OS-SCOPE-003: documento final reflete a quantidade efetivamente utilizada (3), não a aprovada (5)'
);

-- ============================================================
-- OS-SCOPE-004: aumentar quantidade acima do aprovado é bloqueado — exige
-- Adicional, nunca edição direta de escopo.
-- ============================================================
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid; v_escopo_id uuid;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('descricao', 'PGTAP Item SCOPE004', 'quantidade', 3, 'valor_unitario', 10)));
  v_item := v_items[1];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  select id into v_escopo_id from os_escopo_itens where os_id = v_os and orcamento_item_id = v_item;
  perform set_config('tests.scope004_escopo', v_escopo_id::text, true);
end $$;

insert into tests_120_results (line) select throws_ok(
  format('select rpc_editar_item_escopo_os(%L::uuid, p_quantidade => 5, p_motivo => %L)', current_setting('tests.scope004_escopo')::uuid, 'PGTAP: tentativa de aumento'),
  'P0001', null,
  'OS-SCOPE-004: aumentar quantidade além do aprovado (3 -> 5) é bloqueado — deve usar Adicional'
);

-- ============================================================
-- OS-SCOPE-005: item já utilizado (parcial) não pode ser removido.
-- ============================================================
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid; v_escopo_id uuid;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('peca_id', 'e5000000-0000-0000-0000-000000000003', 'descricao', 'PGTAP Item SCOPE005', 'quantidade', 5, 'valor_unitario', 20)));
  v_item := v_items[1];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  perform rpc_baixar_peca_os(v_os, 'e5000000-0000-0000-0000-000000000003'::uuid, 2, null, v_item, null);
  select id into v_escopo_id from os_escopo_itens where os_id = v_os and orcamento_item_id = v_item;
  perform set_config('tests.scope005_escopo', v_escopo_id::text, true);
end $$;

insert into tests_120_results (line) select throws_ok(
  format('select rpc_remover_item_escopo_os(%L::uuid, %L)', current_setting('tests.scope005_escopo')::uuid, 'PGTAP: tentativa de remover já utilizado'),
  'P0001', null,
  'OS-SCOPE-005: item com utilização parcial (baixa já registrada) não pode ser removido do escopo — exige estorno formal'
);

-- ============================================================
-- OS-SCOPE-006: serviço já executado não pode ser removido do escopo.
-- ============================================================
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid; v_escopo_id uuid;
begin
  select * into v_orc, v_items from tests._esc04_orcamento_aprovado(
    'e5000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('descricao', 'PGTAP Serviço SCOPE006', 'quantidade', 1, 'valor_unitario', 150)));
  v_item := v_items[1];
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  perform rpc_marcar_item_orcamento_execucao(v_item, 'executado');
  select id into v_escopo_id from os_escopo_itens where os_id = v_os and orcamento_item_id = v_item;
  perform set_config('tests.scope006_escopo', v_escopo_id::text, true);
end $$;

insert into tests_120_results (line) select is(
  (select execucao_status from os_escopo_itens where id = current_setting('tests.scope006_escopo')::uuid),
  'executado',
  'OS-SCOPE-006 (pré-condição): marcar execução pela via legada também sincroniza o escopo novo'
);
insert into tests_120_results (line) select throws_ok(
  format('select rpc_remover_item_escopo_os(%L::uuid, %L)', current_setting('tests.scope006_escopo')::uuid, 'PGTAP: tentativa de remover já executado'),
  'P0001', null,
  'OS-SCOPE-006: serviço já executado não pode ser removido/apagado do escopo — histórico não desaparece'
);

-- ============================================================
-- OS-SCOPE-007: adicional aprovado e não executado não bloqueia conclusão
-- e não entra no documento final.
-- ============================================================
do $$
declare v_os uuid; v_adic uuid; v_item_adic uuid; v_doc jsonb;
begin
  v_os := rpc_criar_os('e5000000-0000-0000-0000-000000000006'::uuid, 'interna'::tipo_os);
  perform tests._esc04_definir_checklist(v_os, 'e5000000-0000-0000-0000-000000000099');
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  v_adic := rpc_criar_os_adicional(v_os, 'PGTAP SCOPE007 adicional identificado');
  v_item_adic := rpc_incluir_item_os_adicional(v_adic, null, 'PGTAP Item adicional SCOPE007 não executado', 1, 60, 'PGTAP');
  perform rpc_decidir_item_os_adicional(v_item_adic, 'aprovado', 'sistema', 'PGTAP Responsável');
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);
  perform set_config('tests.scope007_os', v_os::text, true);
end $$;

insert into tests_120_results (line) select lives_ok(
  format('select rpc_concluir_os(%L)', current_setting('tests.scope007_os')::uuid),
  'OS-SCOPE-007: adicional aprovado mas não executado não bloqueia a conclusão da OS'
);
insert into tests_120_results (line) select is(
  jsonb_array_length(rpc_documento_final_os(current_setting('tests.scope007_os')::uuid) -> 'mao_de_obra'),
  0,
  'OS-SCOPE-007: item de adicional aprovado mas não executado não entra no documento final'
);

select line from tests_120_results order by seq;

rollback;
