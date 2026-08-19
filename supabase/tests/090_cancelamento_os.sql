-- FEATURE-OS-CANCELAMENTO-01 — OS-DEL-001..009, OS-REST-001..004,
-- OS-CAN-001..009, OS-FIN-CAN-001..004, OS-CONC-001/002 — executado via
-- `supabase db query --linked -f`. Cobre exclusão lógica de OS "virgem",
-- cancelamento formal (apontamentos, adicionais, estoque, mão de obra,
-- garantia), bloqueio financeiro/liberação/garantia, RBAC, motivo
-- obrigatório, idempotência e restauração administrativa.
--
-- OS-CONC-001/002 (concorrência real de duas sessões): mesma ressalva
-- documentada em supabase/tests/080_cancelamento_orcamento.sql e
-- supabase/tests/README.md — pgTAP roda numa única transação/sessão, então
-- este arquivo só prova o INVARIANTE de estado final testando as duas
-- ordens de execução possíveis sequencialmente, não a contenção real do
-- `for update`.
begin;
select plan(50);

create temporary table tests_090_results (seq serial, line text);
grant insert, select on tests_090_results to authenticated, anon;
grant usage, select on tests_090_results_seq_seq to authenticated, anon;

-- ============================================================
-- Helpers (precisam ser criados ANTES de trocar de papel — CREATE FUNCTION
-- no schema "tests" exige privilégio de dono, que "authenticated" não tem).
-- ============================================================

-- Monta uma OS EXTERNA concluída com cobrança quitada e liberada — mesma
-- receita de supabase/tests/040_liberacao.sql (tests._preparar_os_concluida).
-- Retorna também o item aprovado (v_item) — rpc_criar_os_garantia exige ao
-- menos um item original vinculado, nunca uma garantia "solta".
create or replace function tests._can090_os_liberada(p_sufixo text, out v_os uuid, out v_item uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc uuid; v_cob uuid; v_parcela uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('d9000000-0000-0000-0000-000000000004', 'd9000000-0000-0000-0000-000000000003', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'PGTAP Serviço ' || p_sufixo, 1, 500)
    returning id into v_item;
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid() where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000004'::uuid, 'externa'::tipo_os, v_orc);
  update ordens_servico set status = 'concluida' where id = v_os;
  v_cob := rpc_criar_cobranca('d9000000-0000-0000-0000-000000000003'::uuid, array[v_os], null);
  perform rpc_parcelar_cobranca(v_cob, jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'valor', 500, 'vencimento', current_date)));
  select id into v_parcela from parcelas where cobranca_id = v_cob;
  perform rpc_registrar_recebimento(v_parcela, 500, 'pix', current_date);
  perform rpc_liberar_os(v_os);
end;
$$;

-- Monta uma OS EXTERNA concluída com cobrança ATIVA (status 'aberta', sem
-- parcela/recebimento) mas NÃO liberada — para os testes financeiros
-- FIN-CAN-002/004.
create or replace function tests._can090_os_com_cobranca_aberta(p_sufixo text, out v_os uuid, out v_cob uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('d9000000-0000-0000-0000-000000000004', 'd9000000-0000-0000-0000-000000000003', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'PGTAP Serviço ' || p_sufixo, 1, 500);
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid() where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000004'::uuid, 'externa'::tipo_os, v_orc);
  update ordens_servico set status = 'concluida' where id = v_os;
  v_cob := rpc_criar_cobranca('d9000000-0000-0000-0000-000000000003'::uuid, array[v_os], null);
end;
$$;

-- Cria um orçamento aprovado com N itens (peça ou mão de obra) num único
-- INSERT/UPDATE em lote — SECURITY DEFINER porque orcamentos/orcamento_itens
-- têm RLS que só libera essas mutações para quem é dono (criado_por) em
-- status específico; rodar isso dentro de um "do $$ $$" anônimo no corpo do
-- teste (fora de uma function) executaria com o privilégio real da role
-- "authenticated" e esbarraria no "revoke" de outras tabelas do mesmo fluxo
-- — mesmo problema, mesma solução, então centralizado aqui uma única vez.
-- p_itens: jsonb array de {"peca_id": uuid|null, "descricao": text,
-- "quantidade": numeric, "valor_unitario": numeric}.
create or replace function tests._can090_orcamento_aprovado(
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

-- ordens_servico também tem "revoke update from authenticated" — bypass de
-- teste para forçar 'concluida' rapidamente (mesma convenção de
-- supabase/tests/040_liberacao.sql e 050_regressao_garantia.sql, só que lá
-- o bypass mora dentro de uma function SECURITY DEFINER e aqui também).
create or replace function tests._can090_forcar_concluida(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update ordens_servico set status = 'concluida' where id = p_os_id;
end;
$$;

-- Fluxo completo de garantia: OS externa liberada -> rpc_criar_os_garantia
-- -> origem vira 'reaberta_garantia'. Retorna (origem, filha).
create or replace function tests._can090_garantia(p_sufixo text, out v_origem uuid, out v_filha uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item uuid;
begin
  select os.v_os, os.v_item into v_origem, v_item from tests._can090_os_liberada(p_sufixo) as os;
  v_filha := rpc_criar_os_garantia(v_origem, array[v_item], null);
end;
$$;

-- OS interna simples (sem orçamento), avançada até o status pedido.
-- 'concluida' usa bypass direto (mesma convenção de tests/040 e tests/050 —
-- não é o que este teste verifica, só precisa de uma OS concluida rápida).
create or replace function tests._can090_os_interna(p_status status_os default 'aberta'::status_os)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os uuid;
begin
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000002'::uuid, 'interna'::tipo_os);
  if p_status = 'aberta' then
    return v_os;
  end if;
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  if p_status = 'em_diagnostico' then
    return v_os;
  end if;
  if p_status = 'aguardando_aprovacao' then
    perform rpc_transicionar_os(v_os, 'aguardando_aprovacao'::status_os);
    return v_os;
  end if;
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  if p_status = 'em_execucao' then
    return v_os;
  end if;
  perform rpc_transicionar_os(v_os, 'aguardando_teste'::status_os);
  if p_status = 'aguardando_teste' then
    return v_os;
  end if;
  update ordens_servico set status = 'concluida' where id = v_os;
  return v_os;
end;
$$;

-- estoque_movimentos e cobrancas/cobranca_origens têm
-- "revoke insert ... from authenticated" (todo write passa por RPC) — os
-- fixtures DEL-003/DEL-007 abaixo precisam fabricar esses registros
-- diretamente (cenário estruturalmente inalcançável pelo fluxo real com a
-- OS em 'aberta', só para testar a guarda em isolamento), então usam um
-- helper SECURITY DEFINER (mesmo motivo de todo o resto deste arquivo).
create or replace function tests._can090_fabricar_movimento(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into estoque_movimentos (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por)
  values ('d9000000-0000-0000-0000-000000000005', 'saida'::tipo_movimento_estoque, 'os'::origem_movimento, p_os_id, 1, 10, 9, auth.uid());
end;
$$;

create or replace function tests._can090_fabricar_cobranca_vinculada(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cob uuid;
begin
  insert into cobrancas (cliente_id, valor_total, criado_por) values ('d9000000-0000-0000-0000-000000000001', 100, auth.uid()) returning id into v_cob;
  insert into cobranca_origens (cobranca_id, os_id) values (v_cob, p_os_id);
end;
$$;

-- ============================================================
-- Fixtures compartilhadas.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin 090'));

insert into clientes (id, tipo, nome) values
  ('d9000000-0000-0000-0000-000000000001', 'interno', 'PGTAP Cliente Interno OS-CANCELAMENTO'),
  ('d9000000-0000-0000-0000-000000000003', 'externo', 'PGTAP Cliente Externo OS-CANCELAMENTO');
insert into veiculos (id, cliente_id, placa) values
  ('d9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', 'PGTAP090A'),
  ('d9000000-0000-0000-0000-000000000004', 'd9000000-0000-0000-0000-000000000003', 'PGTAP090B');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('d9000000-0000-0000-0000-000000000005', 'PGTAP_090_PECA', 'PGTAP Peça OS-CANCELAMENTO', 'UN', 10, 10, 1);
insert into checklist_templates (id, nome) values ('d9000000-0000-0000-0000-000000000006', 'PGTAP Checklist 090');
insert into checklist_template_itens (id, template_id, descricao, obrigatorio) values
  ('d9000000-0000-0000-0000-000000000007', 'd9000000-0000-0000-0000-000000000006', 'PGTAP Item checklist', false);

-- ============================================================
-- OS-DEL-001: OS aberta virgem, encarregado exclui com motivo válido.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado DEL001'));
select set_config('tests.enc090_id', auth.uid()::text, true);
select set_config('tests.del001_os', tests._can090_os_interna()::text, true);

insert into tests_090_results (line)
select lives_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del001_os')::uuid, 'Criada por engano em teste'),
  'OS-DEL-001: OS aberta virgem pode ser excluída por encarregado'
);
insert into tests_090_results (line)
select is(
  (select count(*)::int from ordens_servico where id = current_setting('tests.del001_os')::uuid),
  0,
  'OS-DEL-001b: OS excluída não aparece nem para quem excluiu, se não for administrador_tecnico (RLS)'
);

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin DEL001'));
insert into tests_090_results (line)
select is(
  (select deleted_at is not null and deleted_by::text = current_setting('tests.enc090_id') and deleted_reason = 'Criada por engano em teste'
     from ordens_servico where id = current_setting('tests.del001_os')::uuid),
  true,
  'OS-DEL-001c: deleted_at/deleted_by/deleted_reason preenchidos após exclusão'
);
insert into tests_090_results (line)
select is(
  (select count(*)::int from ordens_servico where id = current_setting('tests.del001_os')::uuid),
  1,
  'OS-DEL-001d: administrador_tecnico continua vendo a OS excluída (RLS)'
);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del001_os')::uuid, 'Segunda tentativa'),
  'P0001', null,
  'OS-DEL-BONUS-01: excluir uma OS já excluída é bloqueada (idempotência)'
);

-- ============================================================
-- OS-DEL-002..007: cada rastro operacional, isoladamente, bloqueia
-- exclusão e a mensagem redireciona para Cancelar OS.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado DEL002'));

-- DEL-002: apontamento.
select set_config('tests.del002_os', tests._can090_os_interna()::text, true);
insert into os_executores (os_id, usuario_id, etapa, inicio)
values (current_setting('tests.del002_os')::uuid, auth.uid(), 'diagnostico'::etapa_execucao, now());
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del002_os')::uuid, 'Tentativa com apontamento'),
  'P0001', null,
  'OS-DEL-002: OS com apontamento não pode ser excluída'
);

-- DEL-003: movimento de estoque (inserido diretamente — estruturalmente
-- inalcançável em 'aberta' pelo fluxo real, já que rpc_baixar_peca_os só
-- roda em diagnostico/execucao; guarda de defesa em profundidade).
select set_config('tests.del003_os', tests._can090_os_interna()::text, true);
select tests._can090_fabricar_movimento(current_setting('tests.del003_os')::uuid);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del003_os')::uuid, 'Tentativa com movimento de estoque'),
  'P0001', null,
  'OS-DEL-003: OS com movimentação de estoque não pode ser excluída'
);

-- DEL-004: foto (via RPC real — não há restrição de status para foto).
select set_config('tests.del004_os', tests._can090_os_interna()::text, true);
insert into storage.objects (bucket_id, name, metadata)
values ('os-fotos', current_setting('tests.del004_os') || '/antes/pgtap-090.jpg', jsonb_build_object('mimetype', 'image/jpeg', 'size', 1000));
select rpc_registrar_foto_os(current_setting('tests.del004_os')::uuid, 'antes', current_setting('tests.del004_os') || '/antes/pgtap-090.jpg');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del004_os')::uuid, 'Tentativa com foto'),
  'P0001', null,
  'OS-DEL-004: OS com foto anexada não pode ser excluída'
);

-- DEL-005: adicional (via RPC real — permitido em 'aberta').
select set_config('tests.del005_os', tests._can090_os_interna()::text, true);
select rpc_criar_os_adicional(current_setting('tests.del005_os')::uuid, 'PGTAP adicional em OS aberta');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del005_os')::uuid, 'Tentativa com adicional'),
  'P0001', null,
  'OS-DEL-005: OS com adicional registrado não pode ser excluída'
);

-- DEL-006: resposta de checklist (via insert direto — permitido em
-- 'aberta' pela RLS).
select set_config('tests.del006_os', tests._can090_os_interna()::text, true);
insert into os_checklist_respostas (os_id, template_item_id, ok, respondido_por, respondido_em)
values (current_setting('tests.del006_os')::uuid, 'd9000000-0000-0000-0000-000000000007', true, auth.uid(), now());
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del006_os')::uuid, 'Tentativa com checklist respondido'),
  'P0001', null,
  'OS-DEL-006: OS com resposta de checklist não pode ser excluída'
);

-- DEL-007: cobrança vinculada (inserida diretamente — estruturalmente
-- inalcançável em 'aberta' pelo fluxo real, já que rpc_criar_cobranca só
-- aceita OS concluida; guarda de defesa em profundidade).
select set_config('tests.del007_os', tests._can090_os_interna()::text, true);
select tests._can090_fabricar_cobranca_vinculada(current_setting('tests.del007_os')::uuid);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del007_os')::uuid, 'Tentativa com cobranca'),
  'P0001', null,
  'OS-DEL-007: OS já vinculada a cobrança não pode ser excluída'
);

-- ============================================================
-- OS-DEL-008: OS com status <> 'aberta'. BLOQUEADO.
-- ============================================================
select set_config('tests.del008_os', tests._can090_os_interna('em_diagnostico'::status_os)::text, true);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del008_os')::uuid, 'Tentativa fora de aberta'),
  'P0001', null,
  'OS-DEL-008: OS em em_diagnostico não pode ser excluída (só aberta)'
);

-- ============================================================
-- OS-DEL-009: OS de garantia. BLOQUEADO (mesmo ainda virgem/aberta).
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin DEL009'));
select set_config('tests.del009_filha', (select v_filha from tests._can090_garantia('DEL009'))::text, true);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.del009_filha')::uuid, 'Tentativa de excluir OS de garantia'),
  'P0001', null,
  'OS-DEL-009: OS de garantia não pode ser excluída, mesmo virgem'
);

-- ============================================================
-- OS-DEL RBAC + motivo obrigatório.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado DEL-RBAC'));
select set_config('tests.delrbac_os', tests._can090_os_interna()::text, true);

select tests.autenticar_como(tests.criar_usuario_teste('executor'::perfil_usuario, 'PGTAP Executor DEL-RBAC'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.delrbac_os')::uuid, 'Executor tentando excluir'),
  'P0001', null,
  'OS-DEL-RBAC-a: executor não consegue excluir OS'
);

select tests.autenticar_como_anon();
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.delrbac_os')::uuid, 'Anon tentando excluir'),
  'P0001', null,
  'OS-DEL-RBAC-b: anon não consegue excluir OS'
);

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin DEL-RBAC-inativo'));
do $$
declare v_id uuid;
begin
  v_id := tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Inativo DEL-RBAC');
  update profiles set ativo = false where id = v_id;
  perform set_config('tests.del_rbac_inativo_id', v_id::text, true);
end $$;
select tests.autenticar_como(current_setting('tests.del_rbac_inativo_id')::uuid);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.delrbac_os')::uuid, 'Inativo tentando excluir'),
  'P0001', null,
  'OS-DEL-RBAC-c: usuário inativo bloqueado mesmo com perfil encarregado'
);

select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado DEL-motivo'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, null)', current_setting('tests.delrbac_os')::uuid),
  'P0001', null,
  'OS-DEL-motivo-a: exclusão sem motivo é bloqueada'
);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_excluir_os_rascunho(%L, %L)', current_setting('tests.delrbac_os')::uuid, 'abc'),
  'P0001', null,
  'OS-DEL-motivo-b: exclusão com motivo abaixo de 5 caracteres é bloqueada'
);

-- ============================================================
-- OS-REST-001..004: restauração administrativa.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin REST'));
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_restaurar_os_excluida(%L, %L)', current_setting('tests.del001_os')::uuid, 'Restaurado após confirmação'),
  'OS-REST-001: administrador_tecnico restaura OS excluída'
);
insert into tests_090_results (line)
select is(
  (select deleted_at from ordens_servico where id = current_setting('tests.del001_os')::uuid),
  null,
  'OS-REST-001b: deleted_at volta a null após restauração'
);
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado Verifica REST'));
insert into tests_090_results (line)
select is(
  (select count(*)::int from ordens_servico where id = current_setting('tests.del001_os')::uuid),
  1,
  'OS-REST-001c: OS restaurada volta a aparecer para perfil não-admin (RLS)'
);

-- REST-002: encarregado (perfil que PODE excluir) não pode restaurar.
-- OS virgem nova, dedicada (del002_os tem apontamento, não seria excluível).
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado REST002'));
select set_config('tests.rest002_os', tests._can090_os_interna()::text, true);
select rpc_excluir_os_rascunho(current_setting('tests.rest002_os')::uuid, 'Exclusão para testar RBAC de restauração');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_restaurar_os_excluida(%L, null)', current_setting('tests.rest002_os')::uuid),
  'P0001', null,
  'OS-REST-002: encarregado não consegue restaurar OS excluída (só administrador_tecnico)'
);

-- REST-003: restaurar OS que nunca foi excluída. Bloqueado.
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin REST003'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_restaurar_os_excluida(%L, null)', current_setting('tests.del008_os')::uuid),
  'P0001', null,
  'OS-REST-003: restaurar OS que não está excluída é bloqueado'
);

-- REST-004: exclusão libera o orçamento para reconversão (fix de migration
-- 20260818170300); e, uma vez reconvertido, restaurar a OS original antiga
-- passa a ser bloqueado (outra OS ativa para o mesmo orçamento).
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado REST004'));
do $$
declare v_orc uuid; v_items uuid[]; v_os1 uuid;
begin
  select * into v_orc, v_items from tests._can090_orcamento_aprovado(
    'd9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('descricao', 'PGTAP Item REST004', 'quantidade', 1, 'valor_unitario', 100)));
  v_os1 := rpc_criar_os('d9000000-0000-0000-0000-000000000002'::uuid, 'interna'::tipo_os, v_orc);
  perform rpc_excluir_os_rascunho(v_os1, 'Criada por engano — orçamento será reconvertido');
  perform set_config('tests.rest004_orc', v_orc::text, true);
  perform set_config('tests.rest004_os1', v_os1::text, true);
end $$;
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_criar_os(%L, %L::tipo_os, %L)', 'd9000000-0000-0000-0000-000000000002'::uuid, 'interna', current_setting('tests.rest004_orc')::uuid),
  'OS-REST-004a: excluir a OS libera o orçamento para reconversão (BR-008 ignora OS soft-deleted)'
);
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin REST004'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_restaurar_os_excluida(%L, null)', current_setting('tests.rest004_os1')::uuid),
  'P0001', null,
  'OS-REST-004b: restaurar a OS excluída original é bloqueado depois que o orçamento já foi reconvertido em outra OS ativa'
);

-- ============================================================
-- OS-CAN-001: cancela de cada um dos 6 status permitidos.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN001'));
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('aberta'::status_os), 'Cancelar a partir de aberta'),
  'OS-CAN-001a: cancela OS em aberta'
);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('em_diagnostico'::status_os), 'Cancelar a partir de em_diagnostico'),
  'OS-CAN-001b: cancela OS em em_diagnostico'
);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('aguardando_aprovacao'::status_os), 'Cancelar a partir de aguardando_aprovacao'),
  'OS-CAN-001c: cancela OS em aguardando_aprovacao'
);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('em_execucao'::status_os), 'Cancelar a partir de em_execucao'),
  'OS-CAN-001d: cancela OS em em_execucao'
);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('aguardando_teste'::status_os), 'Cancelar a partir de aguardando_teste'),
  'OS-CAN-001e: cancela OS em aguardando_teste'
);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('concluida'::status_os), 'Cancelar a partir de concluida'),
  'OS-CAN-001f: cancela OS em concluida (sem cobrança vinculada)'
);

-- ============================================================
-- OS-CAN-002: liberada / reaberta_garantia bloqueados.
-- tests._can090_os_liberada/_can090_garantia chamam rpc_criar_cobranca
-- internamente, que exige suporte_administrativo/administrador_tecnico —
-- por isso todo este bloco roda autenticado como administrador_tecnico
-- (rpc_cancelar_os também aceita esse perfil).
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin CAN002'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_cancelar_os(%L, %L)', (select v_os from tests._can090_os_liberada('CAN002LIB')), 'Tentativa em liberada'),
  'P0001', null,
  'OS-CAN-002a: OS liberada não pode ser cancelada'
);
select set_config('tests.can002_origem', (select v_origem from tests._can090_garantia('CAN002GAR'))::text, true);
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.can002_origem')::uuid, 'Tentativa em reaberta_garantia'),
  'P0001', null,
  'OS-CAN-002b: OS origem em reaberta_garantia não pode ser cancelada'
);

-- ============================================================
-- OS-CAN-003: idempotência do cancelamento.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN003'));
select set_config('tests.can003_os', tests._can090_os_interna('aberta'::status_os)::text, true);
select rpc_cancelar_os(current_setting('tests.can003_os')::uuid, 'Primeiro cancelamento');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.can003_os')::uuid, 'Segunda tentativa'),
  'P0001', null,
  'OS-CAN-003: cancelar uma OS já cancelada é bloqueado (idempotência)'
);

-- ============================================================
-- OS-CAN-004: apontamento em aberto é encerrado pelo cancelamento.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN004'));
select set_config('tests.can004_os', tests._can090_os_interna('em_execucao'::status_os)::text, true);
select tests.autenticar_como(tests.criar_usuario_teste('executor'::perfil_usuario, 'PGTAP Executor CAN004'));
do $$
declare v_exec_id uuid;
begin
  insert into os_executores (os_id, usuario_id, etapa, inicio)
  values (current_setting('tests.can004_os')::uuid, auth.uid(), 'execucao'::etapa_execucao, now())
  returning id into v_exec_id;
  perform set_config('tests.can004_exec_id', v_exec_id::text, true);
end $$;
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN004b'));
select rpc_cancelar_os(current_setting('tests.can004_os')::uuid, 'Cancelamento com apontamento aberto');
insert into tests_090_results (line)
select is(
  (select fim is not null from os_executores where id = current_setting('tests.can004_exec_id')::uuid),
  true,
  'OS-CAN-004: apontamento em aberto é encerrado (fim preenchido) ao cancelar a OS'
);

-- ============================================================
-- OS-CAN-005: adicional aguardando_aprovacao fecha formalmente.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN005'));
select set_config('tests.can005_os', tests._can090_os_interna('em_diagnostico'::status_os)::text, true);
select set_config('tests.can005_adic', rpc_criar_os_adicional(current_setting('tests.can005_os')::uuid, 'PGTAP adicional a fechar')::text, true);
select rpc_cancelar_os(current_setting('tests.can005_os')::uuid, 'Cancelamento com adicional pendente');
insert into tests_090_results (line)
select is(
  (select status from os_adicionais where id = current_setting('tests.can005_adic')::uuid),
  'rejeitado',
  'OS-CAN-005: adicional aguardando_aprovacao vira rejeitado ao cancelar a OS'
);

-- ============================================================
-- OS-CAN-006/007: estorno de peça e reabertura de item de mão de obra.
-- Um único orçamento com 2 itens (peça + mão de obra) cobre os dois.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN006'));
do $$
declare v_orc uuid; v_items uuid[]; v_item_peca uuid; v_item_mo uuid; v_os uuid;
begin
  select * into v_orc, v_items from tests._can090_orcamento_aprovado(
    'd9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001',
    jsonb_build_array(
      jsonb_build_object('peca_id', 'd9000000-0000-0000-0000-000000000005', 'descricao', 'PGTAP Item com peça CAN006', 'quantidade', 3, 'valor_unitario', 50),
      jsonb_build_object('descricao', 'PGTAP Item mão de obra CAN007', 'quantidade', 1, 'valor_unitario', 200)
    ));
  v_item_peca := v_items[1];
  v_item_mo := v_items[2];
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000002'::uuid, 'interna'::tipo_os, v_orc);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  perform rpc_baixar_peca_os(v_os, 'd9000000-0000-0000-0000-000000000005'::uuid, 1, null, v_item_peca, null);
  perform rpc_marcar_item_orcamento_execucao(v_item_mo, 'parcial');
  perform set_config('tests.can006_os', v_os::text, true);
  perform set_config('tests.can006_item_peca', v_item_peca::text, true);
  perform set_config('tests.can007_item_mo', v_item_mo::text, true);
end $$;
insert into tests_090_results (line)
select is(
  (select saldo_atual from pecas where id = 'd9000000-0000-0000-0000-000000000005'),
  9::numeric,
  'OS-CAN-006-pre: saldo da peça reflete a baixa antes do cancelamento (10 - 1 = 9)'
);
select rpc_cancelar_os(current_setting('tests.can006_os')::uuid, 'Cancelamento com peça baixada e item de mão de obra parcial');
insert into tests_090_results (line)
select is(
  (select saldo_atual from pecas where id = 'd9000000-0000-0000-0000-000000000005'),
  10::numeric,
  'OS-CAN-006: saldo da peça é restaurado (estorno) ao cancelar a OS'
);
insert into tests_090_results (line)
select is(
  (select execucao_status from orcamento_itens where id = current_setting('tests.can006_item_peca')::uuid),
  'pendente',
  'OS-CAN-006b: execucao_status do item com peça volta a pendente (sincronização automática do estorno)'
);
insert into tests_090_results (line)
select is(
  (select execucao_status from orcamento_itens where id = current_setting('tests.can007_item_mo')::uuid),
  'pendente',
  'OS-CAN-007: item de mão de obra (sem peça, sem ledger próprio) volta a pendente ao cancelar a OS'
);

-- ============================================================
-- OS-CAN-008: cancelar uma OS de garantia devolve a origem para liberada.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin CAN008'));
do $$
declare v_origem uuid; v_filha uuid;
begin
  select * into v_origem, v_filha from tests._can090_garantia('CAN008');
  perform set_config('tests.can008_origem', v_origem::text, true);
  perform set_config('tests.can008_filha', v_filha::text, true);
end $$;
select rpc_cancelar_os(current_setting('tests.can008_filha')::uuid, 'Garantia aberta por engano');
insert into tests_090_results (line)
select is(
  (select status::text from ordens_servico where id = current_setting('tests.can008_origem')::uuid),
  'liberada',
  'OS-CAN-008: cancelar OS de garantia devolve a origem para liberada'
);

-- ============================================================
-- OS-CAN-009: rpc_transicionar_os rejeita 'cancelada'.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CAN009'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_transicionar_os(%L, %L::status_os)', tests._can090_os_interna('aberta'::status_os), 'cancelada'),
  'P0001', null,
  'OS-CAN-009: rpc_transicionar_os rejeita cancelada — redireciona para rpc_cancelar_os'
);

-- ============================================================
-- OS-FIN-CAN-001..004: bloqueios financeiros.
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin FIN001'));
select set_config('tests.fin001_os', (select v_os from tests._can090_os_liberada('FIN001'))::text, true);
-- liberada já bloqueia por si só (CAN-002a); para provar especificamente o
-- bloqueio por RECEBIMENTO, usamos um "quase liberada": concluida com
-- cobrança quitada, mas sem chamar rpc_liberar_os.
do $$
declare v_orc uuid; v_items uuid[]; v_os uuid; v_cob uuid; v_parcela uuid;
begin
  select * into v_orc, v_items from tests._can090_orcamento_aprovado(
    'd9000000-0000-0000-0000-000000000004', 'd9000000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object('descricao', 'PGTAP FIN001', 'quantidade', 1, 'valor_unitario', 500)));
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000004'::uuid, 'externa'::tipo_os, v_orc);
  perform tests._can090_forcar_concluida(v_os);
  v_cob := rpc_criar_cobranca('d9000000-0000-0000-0000-000000000003'::uuid, array[v_os], null);
  perform rpc_parcelar_cobranca(v_cob, jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'valor', 500, 'vencimento', current_date)));
  select id into v_parcela from parcelas where cobranca_id = v_cob;
  perform rpc_registrar_recebimento(v_parcela, 500, 'pix', current_date);
  perform set_config('tests.fin001b_os', v_os::text, true);
end $$;
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado FIN001'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.fin001b_os')::uuid, 'Tentativa com recebimento confirmado'),
  'P0001', null,
  'OS-FIN-CAN-001: OS com recebimento confirmado não pode ser cancelada'
);

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin FIN002'));
do $$
declare v_os uuid; v_cob uuid;
begin
  select * into v_os, v_cob from tests._can090_os_com_cobranca_aberta('FIN002');
  perform set_config('tests.fin002_os', v_os::text, true);
  perform set_config('tests.fin002_cob', v_cob::text, true);
end $$;
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado FIN002'));
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.fin002_os')::uuid, 'Tentativa com cobranca ativa sem pagamento'),
  'P0001', null,
  'OS-FIN-CAN-002: OS com cobrança ativa (sem pagamento) não pode ser cancelada diretamente'
);

select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado FIN003'));
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', tests._can090_os_interna('concluida'::status_os), 'Cancelamento sem cobrança nenhuma'),
  'OS-FIN-CAN-003: OS concluida sem cobrança nenhuma pode ser cancelada normalmente'
);

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin FIN004'));
select rpc_cancelar_cobranca(current_setting('tests.fin002_cob')::uuid);
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado FIN004'));
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.fin002_os')::uuid, 'Cobranca cancelada manualmente, agora cancela a OS'),
  'OS-FIN-CAN-004: depois de cancelar a cobrança manualmente, a OS pode ser cancelada'
);

-- ============================================================
-- OS-CONC-001/002: invariante de concorrência (ver nota no topo do
-- arquivo — pgTAP não modela duas sessões reais).
-- ============================================================
select tests.autenticar_como(tests.criar_usuario_teste('encarregado'::perfil_usuario, 'PGTAP Encarregado CONC'));

-- CONC-001a: cancela vence a corrida -> baixar peça depois é bloqueado
-- (nunca peça baixada numa OS já cancelada, mesmo sem given lock real aqui).
select set_config('tests.conc001a_os', tests._can090_os_interna('em_execucao'::status_os)::text, true);
select rpc_cancelar_os(current_setting('tests.conc001a_os')::uuid, 'Vence a corrida: cancelamento primeiro');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_baixar_peca_os(%L, %L, 1)', current_setting('tests.conc001a_os')::uuid, 'd9000000-0000-0000-0000-000000000005'::uuid),
  'P0001', null,
  'OS-CONC-001a: se o cancelamento vence a corrida, a baixa de peça subsequente é bloqueada'
);

-- CONC-001b: ordem inversa — baixa vence primeiro, cancelamento subsequente
-- ainda funciona e estorna a peça já baixada (sem estado impossível).
do $$
declare v_orc uuid; v_items uuid[]; v_item uuid; v_os uuid;
begin
  select * into v_orc, v_items from tests._can090_orcamento_aprovado(
    'd9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object('peca_id', 'd9000000-0000-0000-0000-000000000005', 'descricao', 'PGTAP Item CONC001b', 'quantidade', 1, 'valor_unitario', 50)));
  v_item := v_items[1];
  v_os := rpc_criar_os('d9000000-0000-0000-0000-000000000002'::uuid, 'interna'::tipo_os, v_orc);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  perform rpc_baixar_peca_os(v_os, 'd9000000-0000-0000-0000-000000000005'::uuid, 1, null, v_item, null);
  perform set_config('tests.conc001b_os', v_os::text, true);
end $$;
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.conc001b_os')::uuid, 'Vence a corrida: baixa primeiro, cancelamento depois'),
  'OS-CONC-001b: se a baixa vence a corrida, o cancelamento subsequente ainda funciona e estorna'
);

-- CONC-002: concluir vs cancelar — nunca as duas transições convivem.
select set_config('tests.conc002a_os', tests._can090_os_interna('aguardando_teste'::status_os)::text, true);
select rpc_cancelar_os(current_setting('tests.conc002a_os')::uuid, 'Vence a corrida: cancelamento primeiro');
insert into tests_090_results (line)
select throws_ok(
  format('select rpc_concluir_os(%L)', current_setting('tests.conc002a_os')::uuid),
  'P0001', null,
  'OS-CONC-002a: se o cancelamento vence a corrida, concluir depois é bloqueado (nunca concluida+cancelada)'
);

select set_config('tests.conc002b_os', tests._can090_os_interna('concluida'::status_os)::text, true);
insert into tests_090_results (line)
select lives_ok(
  format('select rpc_cancelar_os(%L, %L)', current_setting('tests.conc002b_os')::uuid, 'Vence a corrida: conclusão primeiro, cancelamento depois'),
  'OS-CONC-002b: se a conclusão vence a corrida, cancelar depois ainda é permitido (concluida é cancelável) — sem estado impossível'
);

select line from tests_090_results order by seq;

rollback;
