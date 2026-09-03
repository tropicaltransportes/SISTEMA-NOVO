-- BUG-ORC-CLASSIFICACAO-03 — ORC-TIPO-001..010. Causa raiz:
-- rpc_dados_pdf_orcamento (20260814111000_p1c_relatorios.sql) nunca
-- devolvia peca_id/servico_id/natureza no array de itens — o frontend
-- (OrcamentoPdf.vue/pdfOrcamento.js) já filtrava corretamente por
-- `item.natureza === 'peca'` desde a FEATURE-SERVICOS-01, mas como o campo
-- nunca chegava, `natureza` era sempre undefined e TODO item caía em "Mão
-- de Obra". Corrigido em 20260902100000_p5_fix_bug_orc_classificacao03.sql
-- (só adiciona os 3 campos que faltavam — nenhuma mudança de frontend).
--
-- Reproduz o cenário real reportado (seção 9 do pedido): 9 peças (subtotal
-- R$2.143,54) + 1 serviço avulso (R$230,00) = R$2.373,54, que hoje aparecia
-- 100% como "Mão de Obra".
begin;
select plan(10);

create temporary table tests_130_results (seq serial, line text);
grant insert, select on tests_130_results to authenticated, anon;
grant usage, select on tests_130_results_seq_seq to authenticated, anon;

-- orcamentos/orcamento_itens têm "revoke update from authenticated" (todo
-- write de aprovação passa por RPC em produção) — bypass de teste via
-- function SECURITY DEFINER, mesma convenção já usada em
-- supabase/tests/090_cancelamento_os.sql/050_regressao_garantia.sql.
-- Precisa ser criada ANTES de trocar de papel (CREATE FUNCTION no schema
-- "tests" exige privilégio de dono, que "authenticated" não tem).
create or replace function tests._orc130_aprovar_e_criar_os()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_os uuid;
begin
  insert into orcamentos (id, veiculo_id, cliente_id, criado_por, status) values
    ('f0000000-0000-0000-0000-00000000000b', 'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', auth.uid(), 'rascunho');
  insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
    ('f0000000-0000-0000-0000-00000000000b', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Peça ORC130b', 1, 50);
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values
    ('f0000000-0000-0000-0000-00000000000b', 'PGTAP Mão de obra ORC130b', 1, 80);
  update orcamentos set status = 'enviado', autorizado_por_nome = 'PGTAP', comprovante_path = 'x' where id = 'f0000000-0000-0000-0000-00000000000b';
  update orcamento_itens set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema', autorizado_por_nome = 'PGTAP', autorizado_em = now(), registrado_por = auth.uid()
    where orcamento_id = 'f0000000-0000-0000-0000-00000000000b';
  update orcamentos set status = 'aprovado' where id = 'f0000000-0000-0000-0000-00000000000b';

  v_os := rpc_criar_os('f0000000-0000-0000-0000-000000000002'::uuid, 'externa'::tipo_os, 'f0000000-0000-0000-0000-00000000000b'::uuid);
  perform rpc_transicionar_os(v_os, 'em_diagnostico'::status_os);
  perform rpc_transicionar_os(v_os, 'em_execucao'::status_os);
  return v_os;
end;
$$;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario, 'PGTAP Admin ORC130'));

insert into clientes (id, tipo, nome) values ('f0000000-0000-0000-0000-000000000001', 'externo', 'PGTAP Cliente ORC130');
insert into veiculos (id, cliente_id, placa) values ('f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', 'PGTAPF01');
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('f0000000-0000-0000-0000-000000000003', 'PGTAP_ORC130_PECA', 'PGTAP Retentor Teste ORC130', 'UN', 10, 20, 1);
insert into servicos (id, codigo, nome, preco_referencia, ativo) values
  ('f0000000-0000-0000-0000-000000000004', 'PGTAP-ORC130', 'PGTAP Serviço Cadastrado ORC130', 100, true);

-- Cenário real: orçamento com 9 peças (R$2.143,54) + 1 serviço avulso (R$230,00).
insert into orcamentos (id, veiculo_id, cliente_id, criado_por) values
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', auth.uid());
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Retentor do Comando', 1, 75.00),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Disco de Freio Dianteiro', 2, 272.66),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Jogo de Junta da Tampa de Válvula', 1, 163.25),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Kit de Correias Dentadas', 1, 818.37),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Correia 6PK1560 Gates', 1, 162.00),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Óleo 5w30 Lubrax Top', 5, 49.72),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Retentor da Polia', 1, 51.00),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Retentor do Comando GM02178', 1, 36.00),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000003', 'PGTAP Filtro de Óleo WOE313 Wega', 1, 44.00);
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values
  ('f0000000-0000-0000-0000-00000000000a', 'PGTAP Retirada de Vazamentos e Troca de Discos de Freio Dianteiros', 1, 230.00);

do $$
declare
  v_dados jsonb;
  v_itens jsonb;
  v_subtotal_pecas numeric;
  v_subtotal_mao_obra numeric;
begin
  v_dados := rpc_dados_pdf_orcamento('f0000000-0000-0000-0000-00000000000a');
  v_itens := v_dados -> 'itens';

  select coalesce(sum((i->>'valor_total_original')::numeric), 0) into v_subtotal_pecas
    from jsonb_array_elements(v_itens) i where i->>'natureza' = 'peca';
  select coalesce(sum((i->>'valor_total_original')::numeric), 0) into v_subtotal_mao_obra
    from jsonb_array_elements(v_itens) i where i->>'natureza' <> 'peca';

  insert into tests_130_results (line) select is(
    (select count(*)::int from jsonb_array_elements(v_itens) i where i->>'natureza' = 'peca'),
    9,
    'ORC-TIPO-005 (cenário real): rpc_dados_pdf_orcamento classifica exatamente 9 itens como peça'
  );
  insert into tests_130_results (line) select is(
    round(v_subtotal_pecas, 2), 2143.54::numeric,
    'ORC-TIPO-005: subtotal peças do cenário real = R$ 2.143,54'
  );
  insert into tests_130_results (line) select is(
    round(v_subtotal_mao_obra, 2), 230.00::numeric,
    'ORC-TIPO-006: subtotal mão de obra do cenário real = R$ 230,00 (não R$ 2.373,54)'
  );
  insert into tests_130_results (line) select is(
    round(v_subtotal_pecas + v_subtotal_mao_obra, 2), 2373.54::numeric,
    'ORC-TIPO-007: total geral preservado = R$ 2.373,54'
  );
  insert into tests_130_results (line) select is(
    (select count(*)::int from jsonb_array_elements(v_itens) i where i->>'natureza' = 'peca' and i->>'peca_id' is not null),
    9,
    'ORC-TIPO-001: RPC devolve peca_id explícito em todo item peça (não obriga frontend a reconstruir por heurística)'
  );
end $$;

-- ORC-TIPO-002/003: serviço cadastrado x serviço avulso, natureza distinta e estrutural.
insert into orcamento_itens (orcamento_id, servico_id, descricao, quantidade, valor_unitario) values
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-000000000004', 'PGTAP Serviço Cadastrado ORC130', 1, 100);

insert into tests_130_results (line) select is(
  (select natureza from orcamento_itens where orcamento_id = 'f0000000-0000-0000-0000-00000000000a' and peca_id = 'f0000000-0000-0000-0000-000000000003' limit 1),
  'peca', 'ORC-TIPO-001: item com peca_id -> natureza = peca (coluna gerada, estrutural)'
);
insert into tests_130_results (line) select is(
  (select natureza from orcamento_itens where servico_id = 'f0000000-0000-0000-0000-000000000004'),
  'servico_cadastrado', 'ORC-TIPO-002: item com servico_id -> natureza = servico_cadastrado (estrutural, não pelo nome)'
);
insert into tests_130_results (line) select is(
  (select natureza from orcamento_itens where orcamento_id = 'f0000000-0000-0000-0000-00000000000a' and descricao like 'PGTAP Retirada%'),
  'servico_avulso', 'ORC-TIPO-003: item sem peca_id/servico_id -> natureza = servico_avulso (mão de obra avulsa)'
);

-- ORC-TIPO-009: orçamento -> OS preserva natureza (mesma coluna, mesmo peca_id/servico_id).
select set_config('tests.orc130_os', tests._orc130_aprovar_e_criar_os()::text, true);

insert into tests_130_results (line) select is(
  (select natureza from orcamento_itens where orcamento_id = 'f0000000-0000-0000-0000-00000000000b' and peca_id is not null),
  'peca', 'ORC-TIPO-009: orçamento -> OS preserva peca_id/natureza (mesma linha, nenhuma reclassificação)'
);

-- ORC-TIPO-010: item de mão de obra (sem peca_id) não pode gerar movimento de estoque.
insert into tests_130_results (line) select throws_ok(
  format('select rpc_baixar_peca_os(%L::uuid, %L::uuid, 1, null, %L::uuid, null)',
    current_setting('tests.orc130_os'),
    'f0000000-0000-0000-0000-000000000003',
    (select id from orcamento_itens where orcamento_id = 'f0000000-0000-0000-0000-00000000000b' and descricao = 'PGTAP Mão de obra ORC130b')),
  'P0001', null,
  'ORC-TIPO-010: tentar baixar peça vinculada a um item que não é peça (mão de obra) é bloqueado'
);

select line from tests_130_results order by seq;

rollback;
