-- REG-GAR-001 — teste de regressão PERMANENTE (ETAPA 7/RC1, seção 5 do
-- roteiro de homologação final).
--
-- Contexto real do bug (TEST_REPORT_P1C.md, seção 5): a migration
-- 20260813100300_p1b_estoque_execucao_adicional.sql (P1-B), ao acrescentar o
-- ramo "peça de item ADICIONAL da própria OS" em rpc_baixar_peca_os, derrubou
-- SILENCIOSAMENTE o ramo de OS de GARANTIA (introduzido no P1-A, baseado em
-- os_origem_id) — a suíte de regressão da época não tinha nenhum cenário de
-- baixa em OS de garantia, então ninguém percebeu. Corrigido em
-- 20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql (ramo de garantia
-- verificado PRIMEIRO). Este arquivo fecha essa lacuna de cobertura de forma
-- permanente: cobre os DOIS jeitos de uma OS de garantia referenciar o item
-- original (item de ORÇAMENTO original e item de ADICIONAL original), porque
-- se o ramo de garantia for removido de novo por engano:
--   - no caminho do item de ADICIONAL, o erro visível seria "Item de
--     adicional não pertence a esta OS" (era o efeito real observado no
--     P1-C, porque o ramo B — adicional da própria OS — roda antes e vê
--     os_id da OS ORIGINAL, não da OS de garantia);
--   - no caminho do item de ORÇAMENTO original, o efeito seria PIOR e
--     silencioso: como uma OS de garantia nunca tem orcamento_id preenchido,
--     nenhum ramo do if/elsif dispararia, a função pularia direto para
--     `rpc_registrar_saida_estoque_completa` SEM NENHUM limite de
--     quantidade coberta pela garantia — baixa ilimitada, sem erro.
-- As asserções 3 e 4 abaixo travam justamente esse segundo caso.
begin;

select plan(4);

-- Precisam ser criadas ANTES de trocar de papel (CREATE FUNCTION no schema
-- "tests" exige privilégio de dono, que "authenticated" não tem) e como
-- SECURITY DEFINER, porque fazem UPDATE direto em orcamentos/ordens_servico
-- para montar o fixture rapidamente — mesma convenção de
-- supabase/tests/040_liberacao.sql (tests._preparar_os_concluida).
create or replace function tests._reggar_ramo1_item_original()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc uuid; v_item uuid; v_os uuid; v_gar uuid; v_cob uuid; v_parcela uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status) values
    ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
    (v_orc, 'aaaaaaaa-0000-0000-0000-000000000003', 'PGTAP Serviço com peça (item original)', 3, 100)
    returning id into v_item;
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
    autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid() where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;

  v_os := rpc_criar_os('aaaaaaaa-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, v_orc);
  -- bypassa a máquina de estados só para montar o fixture rapidamente (mesma
  -- convenção já usada em supabase/tests/040_liberacao.sql) — o que este
  -- teste verifica é o comportamento de rpc_baixar_peca_os numa OS de
  -- GARANTIA, não o percurso completo de estados até 'concluida'.
  update ordens_servico set status = 'concluida' where id = v_os;
  v_cob := rpc_criar_cobranca('aaaaaaaa-0000-0000-0000-000000000001'::uuid, array[v_os], null);
  perform rpc_parcelar_cobranca(v_cob, jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'valor', 300, 'vencimento', current_date)));
  select id into v_parcela from parcelas where cobranca_id = v_cob;
  perform rpc_registrar_recebimento(v_parcela, 300, 'pix', current_date);
  perform rpc_liberar_os(v_os);

  v_gar := rpc_criar_os_garantia(v_os, array[v_item], null);
  perform rpc_transicionar_os(v_gar, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_gar, 'em_execucao'::status_os);

  -- A CHAMADA REAL que a regressão do P1-B quebrava: baixa de peça numa OS
  -- de GARANTIA vinculada ao item ORIGINAL do orçamento. Se o ramo de
  -- garantia for removido/reordenado de novo, esta chamada aborta a
  -- transação inteira (erro alto e visível), exatamente como
  -- supabase/tests/040_liberacao.sql já faz para rpc_liberar_os.
  perform rpc_baixar_peca_os(v_gar, 'aaaaaaaa-0000-0000-0000-000000000003'::uuid, 1, null, v_item, null);

  perform set_config('tests.reggar_item_original', v_item::text, true);
  perform set_config('tests.reggar_os_garantia_original', v_gar::text, true);
end;
$$;

create or replace function tests._reggar_ramo2_item_adicional()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os uuid; v_adic uuid; v_item uuid; v_gar uuid;
begin
  v_os := rpc_criar_os('aaaaaaaa-0000-0000-0000-000000000006'::uuid, 'interna'::tipo_os);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);

  v_adic := rpc_criar_os_adicional(v_os, 'PGTAP REG-GAR-001 adicional');
  v_item := rpc_incluir_item_os_adicional(v_adic, 'aaaaaaaa-0000-0000-0000-000000000004'::uuid, 'PGTAP item adicional', 3, 10, 'PGTAP');
  perform rpc_decidir_item_os_adicional(v_item, 'aprovado', 'sistema', 'Teste');

  update ordens_servico set status = 'concluida' where id = v_os;
  perform rpc_liberar_os(v_os);

  v_gar := rpc_criar_os_garantia(v_os, null, array[v_item]);
  perform rpc_transicionar_os(v_gar, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_gar, 'em_execucao'::status_os);

  -- A CHAMADA REAL para o caminho de item de ADICIONAL — era este caminho
  -- que, antes da correção, lançava explicitamente "Item de adicional não
  -- pertence a esta OS" (P1-C).
  perform rpc_baixar_peca_os(v_gar, 'aaaaaaaa-0000-0000-0000-000000000004'::uuid, 1, null, null, v_item);

  perform set_config('tests.reggar_item_adicional', v_item::text, true);
  perform set_config('tests.reggar_os_garantia_adicional', v_gar::text, true);
end;
$$;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario));

insert into clientes (id, tipo, nome) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'externo', 'PGTAP Cliente REG-GAR-001'),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'interno', 'PGTAP Cliente Interno REG-GAR-001');
insert into veiculos (id, cliente_id, placa) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'PGTAP004'),
  ('aaaaaaaa-0000-0000-0000-000000000006', 'aaaaaaaa-0000-0000-0000-000000000005', 'PGTAP005');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('aaaaaaaa-0000-0000-0000-000000000003', 'PGTAP_REGGAR_PECA_ORIGINAL', 'PGTAP Peça garantia item original', 'UN', 20, 10, 1),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'PGTAP_REGGAR_PECA_ADICIONAL', 'PGTAP Peça garantia item adicional', 'UN', 20, 10, 1);

-- Ramo 1: garantia de item do ORÇAMENTO ORIGINAL (orcamento_item_id). OS
-- externa completa: orçamento aprovado -> OS -> concluída -> cobrança
-- quitada -> liberada -> garantia -> em_execucao -> baixa de peça.
select tests._reggar_ramo1_item_original();

-- Ramo 2: garantia de item de ADICIONAL da OS original (os_adicional_item_id).
-- OS interna: sem cobrança, concluída -> liberada -> garantia -> em_execucao
-- -> baixa de peça.
select tests._reggar_ramo2_item_adicional();

select is(
  (select count(*)::int from estoque_movimentos
    where origem_tipo = 'os' and origem_id = current_setting('tests.reggar_os_garantia_original')::uuid
      and orcamento_item_id = current_setting('tests.reggar_item_original')::uuid and tipo = 'saida' and quantidade = 1),
  1,
  'REG-GAR-001 (item original): movimento de saída gravado com o vínculo correto (orcamento_item_id, origem = OS de garantia)'
)
union all
select is(
  (select count(*)::int from estoque_movimentos
    where origem_tipo = 'os' and origem_id = current_setting('tests.reggar_os_garantia_adicional')::uuid
      and os_adicional_item_id = current_setting('tests.reggar_item_adicional')::uuid and tipo = 'saida' and quantidade = 1),
  1,
  'REG-GAR-001 (item adicional): movimento de saída gravado com o vínculo correto (os_adicional_item_id, origem = OS de garantia)'
)
union all
select throws_ok(
  format('select rpc_baixar_peca_os(%L::uuid, %L::uuid, 5, null, %L::uuid, null)',
    current_setting('tests.reggar_os_garantia_original'), 'aaaaaaaa-0000-0000-0000-000000000003', current_setting('tests.reggar_item_original')),
  'P0001', null,
  'REG-GAR-001 (item original): quantidade acima do saldo coberto pela garantia (aprovado 3, já baixado 1, pedindo 5) é bloqueada — prova que o teto NÃO é ignorado silenciosamente'
)
union all
select is(
  (select saldo_atual from pecas where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  19::numeric,
  'REG-GAR-001: saldo da peça do item original reflete exatamente 1 unidade baixada (20 - 1 = 19), sem baixa extra da tentativa bloqueada'
);

rollback;
