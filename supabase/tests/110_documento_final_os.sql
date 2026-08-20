-- ETAPA DOC-OS-FINAL-01 — cobertura de rpc_documento_final_os (documento
-- comercial de conclusão da OS). Executado via
-- `npx supabase db query --linked -f` contra o projeto DEV/QA
-- (jzjbiejmcaygwycvqggm), dentro de begin/rollback (nenhum dado residual).
--
-- DESVIO DELIBERADO do cenário literal do pedido (item 47: "5 abraçadeiras
-- aprovadas, 3 efetivamente utilizadas"): confirmado com o dono do projeto
-- (ver comentário no topo de 20260820190000_p3_doc_os_final01.sql) que a
-- máquina de estados atual não permite concluir uma OS com um item aprovado
-- parcialmente baixado — só 100% baixado (executado) ou 0% baixado
-- (cancelado, e só a partir de pendente). Este arquivo usa 3 aprovadas/3
-- utilizadas (100%) para o item de adicional, preservando os MESMOS valores
-- finais do exemplo do pedido (peças 1.750+15=1.765, mão de obra 550, bruto
-- 2.315), e cobre separadamente (DOC-OS-06/07) os casos que o pedido também
-- pede — aprovado com zero utilizado, serviço aprovado não executado — que
-- são plenamente alcançáveis hoje e são o que realmente prova que a RPC
-- nunca fatura o que não foi de fato entregue.
begin;
select plan(14);

create temporary table tests_110_results (seq serial, line text);
grant insert, select on tests_110_results to authenticated, anon;
grant usage, select on tests_110_results_seq_seq to authenticated, anon;

-- ============================================================
-- Fixture principal: OS externa com orçamento (peça executada + mão de obra
-- executada + peça rejeitada + mão de obra aprovada-não-executada) e um
-- adicional (peça aprovada/executada + peça rejeitada). Força 'concluida'
-- por UPDATE direto (mesmo padrão já usado em tests._preparar_os_concluida,
-- supabase/tests/040_liberacao.sql) — o que está sob teste aqui é a leitura
-- da RPC nova, não a máquina de estados (já coberta em 100_transicao_os.sql).
-- ============================================================
create or replace function tests._doc110_os_externa_concluida()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc uuid; v_os uuid;
  v_item_peca uuid; v_item_mo uuid; v_item_peca_rej uuid; v_item_mo_nao_exec uuid;
  v_adicional uuid; v_adic_item_ok uuid; v_adic_item_rej uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('f5000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', auth.uid(), 'rascunho')
    returning id into v_orc;

  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'f5000000-0000-0000-0000-000000000005', 'PGTAP Bomba dagua', 1, 1750)
    returning id into v_item_peca;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'PGTAP Revisao geral', 1, 550)
    returning id into v_item_mo;
  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'f5000000-0000-0000-0000-000000000005', 'PGTAP Filtro rejeitado', 2, 100)
    returning id into v_item_peca_rej;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'PGTAP Servico aprovado nao executado', 1, 300)
    returning id into v_item_mo_nao_exec;

  update orcamentos set status = 'enviado', autorizado_por_nome = 'PGTAP Cliente', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'PGTAP Cliente', autorizado_em = now(), registrado_por = auth.uid()
    where id in (v_item_peca, v_item_mo, v_item_mo_nao_exec);
  update orcamento_itens set status_aprovacao = 'rejeitado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'PGTAP Cliente', autorizado_em = now(), registrado_por = auth.uid()
    where id = v_item_peca_rej;
  update orcamentos set status = 'aprovado' where id = v_orc;

  v_os := rpc_criar_os('f5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);

  -- Peça executada 100% (única quantidade aprovada é 1) — item efetivamente utilizado.
  perform rpc_baixar_peca_os(v_os, 'f5000000-0000-0000-0000-000000000005'::uuid, 1, p_orcamento_item_id := v_item_peca);
  -- Mão de obra marcada executada manualmente (não passa por estoque).
  perform rpc_marcar_item_orcamento_execucao(v_item_mo, 'executado');
  -- "Serviço aprovado mas não executado" (item 15/51 do pedido): a
  -- representação real e alcançável hoje é 'cancelado' com motivo — deixar
  -- 'pendente' para sempre bloquearia a conclusão de verdade via
  -- rpc_concluir_os (mesmo achado documentado no topo da migration da RPC).
  -- rpc_marcar_item_orcamento_execucao permite cancelar a partir de
  -- 'pendente' (guarda em 20260814110800_p1c_cancelamento_item_aprovado.sql).
  perform rpc_marcar_item_orcamento_execucao(v_item_mo_nao_exec, 'cancelado', 'PGTAP DOC110: servico dispensado antes de iniciar');
  -- v_item_peca_rej fica rejeitado (nunca baixado).

  v_adicional := rpc_criar_os_adicional(v_os, 'PGTAP DOC110: abracadeiras extras identificadas', gen_random_uuid());
  perform rpc_incluir_item_os_adicional(v_adicional, 'f5000000-0000-0000-0000-000000000005'::uuid, 'PGTAP Abracadeira', 3, 5, null);
  select id into v_adic_item_ok from os_adicional_itens where adicional_id = v_adicional;
  perform rpc_decidir_item_os_adicional(v_adic_item_ok, 'aprovado', 'sistema', 'PGTAP Cliente', null, null);
  perform rpc_baixar_peca_os(v_os, 'f5000000-0000-0000-0000-000000000005'::uuid, 3, p_os_adicional_item_id := v_adic_item_ok);

  v_adicional := rpc_criar_os_adicional(v_os, 'PGTAP DOC110: mangueira extra identificada, depois recusada', gen_random_uuid());
  perform rpc_incluir_item_os_adicional(v_adicional, 'f5000000-0000-0000-0000-000000000005'::uuid, 'PGTAP Mangueira rejeitada', 2, 20, null);
  select id into v_adic_item_rej from os_adicional_itens where adicional_id = v_adicional;
  perform rpc_decidir_item_os_adicional(v_adic_item_rej, 'rejeitado', 'sistema', 'PGTAP Cliente', null, null);

  -- Bypass deliberado (mesmo padrão de tests._preparar_os_concluida,
  -- supabase/tests/040_liberacao.sql): força concluida sem passar pelo gate
  -- completo de rpc_concluir_os (que também exige checklist/fotos, fora do
  -- escopo deste arquivo — já coberto em 100_transicao_os.sql). O que está
  -- sob teste aqui é só a leitura da RPC nova.
  update ordens_servico set status = 'concluida' where id = v_os;

  perform set_config('tests.doc110_os', v_os::text, true);
  perform set_config('tests.doc110_item_peca', v_item_peca::text, true);
  return v_os;
end;
$$;

-- Helper adicional (precisa ser criado ANTES da troca de papel abaixo — só o
-- dono do schema "tests" tem CREATE FUNCTION nele; "authenticated" só tem USAGE).
create or replace function tests._doc110_item_aprovado_zero_utilizado()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_orc uuid; v_os uuid; v_item uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('f5000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario)
    values (v_orc, 'f5000000-0000-0000-0000-000000000005', 'PGTAP Peca aprovada zero utilizada', 5, 20)
    returning id into v_item;
  update orcamentos set status = 'enviado', autorizado_por_nome = 'PGTAP Cliente', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'PGTAP Cliente', autorizado_em = now(), registrado_por = auth.uid() where id = v_item;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('f5000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  return v_os;
end;
$$;

-- custo_medio não é gravável direto por "authenticated" (só via RPC de
-- estoque) — helper SECURITY DEFINER só para simular a mudança de catálogo
-- do teste DOC-OS-09, criado antes da troca de papel pelo mesmo motivo acima.
create or replace function tests._doc110_forcar_custo_medio(p_peca_id uuid, p_valor numeric)
returns void
language sql
security definer
set search_path = public
as $$
  update pecas set custo_medio = p_valor where id = p_peca_id;
$$;

-- Fixture da OS interna (DOC-OS-10/11) precisa de UPDATE direto em
-- ordens_servico (bloqueado para "authenticated") — mesmo motivo dos
-- helpers acima, criado aqui por SECURITY DEFINER.
create or replace function tests._doc110_os_interna_concluida()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_os uuid;
begin
  v_os := rpc_criar_os('f5000000-0000-0000-0000-000000000004'::uuid, 'interna'::tipo_os);
  update ordens_servico
    set status = 'concluida', custo_pecas = 120.00, custo_mao_obra = 80.00, custo_total = 200.00, custo_calculado_em = now()
    where id = v_os;
  return v_os;
end;
$$;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin 110'));

insert into clientes (id, tipo, nome) values
  ('f5000000-0000-0000-0000-000000000001', 'externo', 'PGTAP Cliente Externo DOC110'),
  ('f5000000-0000-0000-0000-000000000003', 'interno', 'PGTAP Cliente Interno DOC110');
insert into veiculos (id, cliente_id, placa) values
  ('f5000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', 'PGDOC01'),
  ('f5000000-0000-0000-0000-000000000004', 'f5000000-0000-0000-0000-000000000003', 'PGDOC02');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('f5000000-0000-0000-0000-000000000005', 'PGTAP-DOC110', 'PGTAP Peca DOC110', 'UN', 100, 900, 0);

select set_config('tests.doc110_os', tests._doc110_os_externa_concluida()::text, true);

-- ============================================================
-- DOC-OS-01/02/03: peças e mão de obra mostram só o efetivamente utilizado,
-- nos mesmos valores do exemplo do pedido (item 47).
-- ============================================================
insert into tests_110_results (line)
select is(
  (select jsonb_array_length(rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'pecas')),
  2,
  'DOC-OS-01: pecas mostra exatamente 2 linhas (executada do orcamento + executada do adicional; rejeitada de fora)'
);
insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'resumo_financeiro' ->> 'subtotal_pecas')::numeric),
  1765.00,
  'DOC-OS-02: subtotal pecas = 1750 (orcamento) + 15 (3 x R$5 do adicional) = 1765, igual ao exemplo do pedido'
);
insert into tests_110_results (line)
select is(
  (select jsonb_array_length(rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'mao_de_obra')),
  1,
  'DOC-OS-03: mao_de_obra mostra só o item executado (aprovado-nao-executado fica de fora)'
);
insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'resumo_financeiro' ->> 'subtotal_mao_obra')::numeric),
  550.00,
  'DOC-OS-03b: subtotal mao de obra = 550, igual ao exemplo do pedido'
);

-- ============================================================
-- DOC-OS-04: item rejeitado (orcamento) nunca aparece nem entra no valor final.
-- ============================================================
insert into tests_110_results (line)
select ok(
  not exists (
    select 1 from jsonb_array_elements(rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'pecas') p
    where p ->> 'descricao' = 'PGTAP Filtro rejeitado'
  ),
  'DOC-OS-04: item de orcamento rejeitado nunca aparece na lista de pecas'
);

-- ============================================================
-- DOC-OS-05: item de adicional rejeitado nunca aparece.
-- ============================================================
insert into tests_110_results (line)
select ok(
  not exists (
    select 1 from jsonb_array_elements(rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'pecas') p
    where p ->> 'descricao' = 'PGTAP Mangueira rejeitada'
  ),
  'DOC-OS-05: item de adicional rejeitado nunca aparece na lista de pecas'
);

-- ============================================================
-- DOC-OS-06 (item 49 do pedido): item aprovado com ZERO utilizado (nunca
-- baixado) não aparece nas pecas nem entra no valor final. RPC não depende
-- de status da OS, então testamos isolado, sem forçar 'concluida'.
--
-- A criação da fixture precisa estar em um comando SEPARADO da leitura da
-- RPC (achado real durante a verificação desta etapa): chamar a função
-- VOLATILE que grava (tests._doc110_item_aprovado_zero_utilizado) dentro da
-- MESMA instrução que chama a função STABLE que lê (rpc_documento_final_os)
-- faz a leitura usar o snapshot já fixado no início daquela instrução —
-- anterior às gravações feitas pela própria chamada, dentro da mesma
-- instrução. Duas instruções sequenciais (como já fazem todos os outros
-- testes deste arquivo via current_setting) resolve.
-- ============================================================
select set_config('tests.doc110_os_zero', tests._doc110_item_aprovado_zero_utilizado()::text, true);

insert into tests_110_results (line)
select is(
  (select jsonb_array_length(rpc_documento_final_os(current_setting('tests.doc110_os_zero')::uuid) -> 'pecas')),
  0,
  'DOC-OS-06: item aprovado (5 unidades) com zero baixado nunca aparece nas pecas (aprovado != utilizado)'
);

-- ============================================================
-- DOC-OS-07: servico aprovado mas nao executado (fixture principal) nao entra
-- no valor final.
-- ============================================================
insert into tests_110_results (line)
select ok(
  not exists (
    select 1 from jsonb_array_elements(rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'mao_de_obra') mo
    where mo ->> 'descricao' = 'PGTAP Servico aprovado nao executado'
  ),
  'DOC-OS-07: servico aprovado e nao executado nunca aparece na mao de obra'
);

-- ============================================================
-- DOC-OS-08 (item 23): VALOR FINAL calculado bate exatamente com a cobranca
-- real gerada pela mesma formula oficial (rpc_criar_cobranca).
-- ============================================================
do $$
declare v_cob uuid;
begin
  v_cob := rpc_criar_cobranca('f5000000-0000-0000-0000-000000000001'::uuid, array[current_setting('tests.doc110_os')::uuid], null);
  perform set_config('tests.doc110_cobranca', v_cob::text, true);
end $$;

insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'resumo_financeiro' ->> 'valor_final')::numeric),
  (select valor_total from cobrancas where id = current_setting('tests.doc110_cobranca')::uuid),
  'DOC-OS-08: valor_final do documento bate exatamente com cobrancas.valor_total (mesma formula)'
);
insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'resumo_financeiro' ->> 'valor_final')::numeric),
  2315.00,
  'DOC-OS-08b: valor_final = 2315, igual ao bruto do exemplo do pedido (sem desconto/acrescimo nesta fixture)'
);
insert into tests_110_results (line)
select is(
  (rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'cobranca' ->> 'status'),
  'aberta',
  'DOC-OS-08c: bloco cobranca aparece com o status real, depois que a cobranca de fato existe'
);

-- ============================================================
-- DOC-OS-09 (item 52): snapshot — alterar custo_medio da peca depois da
-- conclusao nao muda o valor_unitario/valor_total ja documentado (a coluna
-- de venda nunca fez join vivo com o catalogo, ver
-- 20260817140000_p2_servicos_catalogo.sql).
-- ============================================================
select tests._doc110_forcar_custo_medio('f5000000-0000-0000-0000-000000000005'::uuid, 9999);

insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os')::uuid) -> 'resumo_financeiro' ->> 'subtotal_pecas')::numeric),
  1765.00,
  'DOC-OS-09: subtotal pecas continua 1765 mesmo depois de mudar pecas.custo_medio (snapshot preservado)'
);

-- ============================================================
-- DOC-OS-10/11: cliente interno nunca gera cobranca ficticia; custo_interno
-- reflete o snapshot ja existente da OS (calcular_e_snapshot_custo_interno_os).
-- ============================================================
select set_config('tests.doc110_os_interna', tests._doc110_os_interna_concluida()::text, true);

insert into tests_110_results (line)
select is(
  (rpc_documento_final_os(current_setting('tests.doc110_os_interna')::uuid) -> 'cobranca'),
  'null'::jsonb,
  'DOC-OS-10: OS interna nunca mostra bloco de cobranca'
);
insert into tests_110_results (line)
select is(
  ((rpc_documento_final_os(current_setting('tests.doc110_os_interna')::uuid) -> 'custo_interno' ->> 'custo_total')::numeric),
  200.00,
  'DOC-OS-11: custo_interno.custo_total reflete o snapshot ja calculado na OS (nunca convertido em valor de venda)'
);

select line from tests_110_results order by seq;

rollback;
