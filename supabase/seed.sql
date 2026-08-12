-- ============================================================
-- MASSA DE TESTE DETERMINÍSTICA — ERP Oficina
-- ============================================================
-- Só DADOS (nenhum DDL). Todos os registros usam UUID fixo (namespaces por
-- entidade abaixo) e nome/sku/placa prefixados TESTE_/QA_/AUTOMATED_TEST_,
-- para nunca se confundir com dado real de negócio.
--
-- Autorizado como ambiente de desenvolvimento/teste descartável — ver
-- docs/testing/TEST_REPORT_EXECUTION_02.md. Reexecutável: a primeira seção
-- apaga (em ordem segura de FK) qualquer massa anterior gerada por este
-- mesmo arquivo antes de recriar, então rodar de novo "reseta" o cenário de
-- teste sem depender de estado deixado por execuções anteriores.
--
-- Namespaces de UUID fixo (dígito líder indica a entidade):
--   a0000000-... usuários (auth.users/profiles)
--   b0000000-... clientes
--   c0000000-... veículos
--   d0000000-... peças
--   e0000000-... orçamentos (+ itens em e1...)
--   f0000000-... ordens de serviço
--   10000000-... cobranças/parcelas/recebimentos/termos
--   20000000-... checklist templates/itens
--
-- Senha de teste única para todos os usuários seedados (conta descartável,
-- exclusiva deste ambiente de dev/teste): Teste@2026!Qa

-- ============================================================
-- 0) LIMPEZA (ordem segura de FK) — idempotente, roda mesmo na 1ª vez
-- ============================================================
delete from recebimentos where parcela_id in (select id from parcelas where cobranca_id::text like '10000000-%');
delete from parcelas where cobranca_id::text like '10000000-%';
delete from termos_ciencia_debito where cobranca_id::text like '10000000-%';
delete from cobranca_origens where cobranca_id::text like '10000000-%';
delete from cobrancas where id::text like '10000000-%';
delete from estoque_movimentos where origem_id::text like 'f0000000-%' or origem_id::text like 'd0000000-%';
delete from os_checklist_respostas where os_id::text like 'f0000000-%';
delete from os_executores where os_id::text like 'f0000000-%';
delete from ordens_servico where id::text like 'f0000000-%';
delete from orcamento_acrescimos where orcamento_id::text like 'e0000000-%';
delete from orcamento_itens where orcamento_id::text like 'e0000000-%';
delete from orcamentos where id::text like 'e0000000-%';
delete from checklist_template_itens where template_id::text like '20000000-%';
delete from checklist_templates where id::text like '20000000-%';
delete from pecas where id::text like 'd0000000-%';
delete from veiculos where id::text like 'c0000000-%';
delete from clientes where id::text like 'b0000000-%';
delete from auth.users where id::text like 'a0000000-%';

-- ============================================================
-- 1) USUÁRIOS DE TESTE (auth.users -> trigger cria profiles automaticamente)
-- ============================================================
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, last_sign_in_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'teste.executor@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Executor"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'teste.encarregado@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Encarregado"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'teste.suporte@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Suporte_Administrativo"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'teste.admin@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Administrador_Tecnico"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'teste.diretoria@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Diretoria"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated',
   'teste.inativo@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Usuario_Inativo"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated',
   'teste.semperfil@qa.local', extensions.crypt('Teste@2026!Qa', extensions.gen_salt('bf')), now(), now(),
   '{"provider":"email","providers":["email"]}', '{"nome":"TESTE_Sem_Profile"}', now(), now(), '', '', '', '');

-- Ajusta os perfis (handle_new_user sempre cria como 'executor').
update profiles set perfil = 'executor', nome = 'TESTE_Executor' where id = 'a0000000-0000-0000-0000-000000000001';
update profiles set perfil = 'encarregado', nome = 'TESTE_Encarregado' where id = 'a0000000-0000-0000-0000-000000000002';
update profiles set perfil = 'suporte_administrativo', nome = 'TESTE_Suporte_Administrativo' where id = 'a0000000-0000-0000-0000-000000000003';
update profiles set perfil = 'administrador_tecnico', nome = 'TESTE_Administrador_Tecnico' where id = 'a0000000-0000-0000-0000-000000000004';
update profiles set perfil = 'diretoria', nome = 'TESTE_Diretoria' where id = 'a0000000-0000-0000-0000-000000000005';
update profiles set perfil = 'executor', ativo = false, nome = 'TESTE_Usuario_Inativo' where id = 'a0000000-0000-0000-0000-000000000006';
-- a0000000-...-0007: "autenticado sem profile" — tem sessão válida no Auth,
-- mas nenhuma linha em profiles (current_perfil() retorna NULL para ele,
-- igual a um chamador anônimo).
delete from profiles where id = 'a0000000-0000-0000-0000-000000000007';

-- ============================================================
-- 2) CLIENTES
-- ============================================================
insert into clientes (id, tipo, nome, documento, telefone, email) values
  ('b0000000-0000-0000-0000-000000000001', 'externo', 'TESTE_Cliente_Externo_Normal', '11111111000101', '(11) 90000-0001', 'contato@testeexternonormal.qa'),
  ('b0000000-0000-0000-0000-000000000002', 'interno', 'TESTE_Cliente_Interno', null, '(11) 90000-0002', 'contato@testeinterno.qa'),
  ('b0000000-0000-0000-0000-000000000003', 'externo', 'TESTE_Cliente_Inadimplente', '22222222000102', '(11) 90000-0003', 'contato@testeinadimplente.qa'),
  ('b0000000-0000-0000-0000-000000000004', 'externo', 'TESTE_Cliente_Garantia', '33333333000103', '(11) 90000-0004', 'contato@testegarantia.qa'),
  ('b0000000-0000-0000-0000-000000000005', 'externo', 'TESTE_Cliente_Duplicidade_A', '44444444000104', '(11) 90000-0005', 'a@testeduplicidade.qa'),
  ('b0000000-0000-0000-0000-000000000006', 'externo', 'TESTE_Cliente_Duplicidade_B', '44444444000105', '(11) 90000-0006', 'b@testeduplicidade.qa');
-- Nota CAD-004 (ETAPA 4 P1-A): b...05 e b...06 tinham PROPOSITALMENTE o
-- MESMO documento até a ETAPA 3, para provar por execução real que não
-- havia unique constraint (achado FALHOU, ver TEST_REPORT_EXECUTION_02.md).
-- A partir da ETAPA 4 existe uq_clientes_documento_normalizado_ativo (ver
-- 20260812091000_p1a_cad004_documento_unico.sql) — manter os dois com o
-- mesmo documento aqui quebraria o seed (23505). b...06 passou a usar um
-- documento distinto (só o último dígito muda); o cenário de duplicidade em
-- si continua coberto por teste real, criando os dois registros em tempo de
-- execução (docs/testing/scripts/etapa4_cad004_orc016.sh), não mais via seed.

-- ============================================================
-- 3) VEÍCULOS (placas ficticias, prefixo TST)
-- ============================================================
insert into veiculos (id, cliente_id, placa, prefixo, modelo, ano) values
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'TST0A01', 'QA01', 'TESTE_Modelo_Generico', 2020),
  ('c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'TST0A02', 'QA02', 'TESTE_Modelo_Generico', 2021),
  ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000003', 'TST0A03', 'QA03', 'TESTE_Modelo_Generico', 2019),
  ('c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000004', 'TST0A04', 'QA04', 'TESTE_Modelo_Generico', 2022);

-- ============================================================
-- 4) ESTOQUE — peças + movimentação inicial de entrada (ledger íntegro)
-- ============================================================
insert into pecas (id, sku, descricao, unidade, saldo_atual, custo_medio, estoque_minimo) values
  ('d0000000-0000-0000-0000-000000000001', 'QA_PECA_SALDO_OK', 'TESTE_Peça_Saldo_Suficiente', 'UN', 50, 20.00, 5),
  ('d0000000-0000-0000-0000-000000000002', 'QA_PECA_SALDO_BAIXO', 'TESTE_Peça_Saldo_Baixo', 'UN', 3, 15.00, 10),
  ('d0000000-0000-0000-0000-000000000003', 'QA_PECA_SALDO_ZERO', 'TESTE_Peça_Saldo_Zero', 'UN', 0, 10.00, 5),
  ('d0000000-0000-0000-0000-000000000004', 'QA_PECA_CONCORRENCIA', 'TESTE_Peça_Teste_Concorrência', 'UN', 10, 25.00, 2),
  ('d0000000-0000-0000-0000-000000000005', 'QA_PECA_ESTOQUE_10', 'TESTE_Peça_Estoque_Dez', 'UN', 10, 30.00, 2);

insert into estoque_movimentos (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por) values
  ('d0000000-0000-0000-0000-000000000001', 'entrada', 'nf_entrada', 'd0000000-0000-0000-0000-000000000001', 50, 20.00, 50, 'a0000000-0000-0000-0000-000000000003'),
  ('d0000000-0000-0000-0000-000000000002', 'entrada', 'nf_entrada', 'd0000000-0000-0000-0000-000000000002', 3, 15.00, 3, 'a0000000-0000-0000-0000-000000000003'),
  ('d0000000-0000-0000-0000-000000000004', 'entrada', 'nf_entrada', 'd0000000-0000-0000-0000-000000000004', 10, 25.00, 10, 'a0000000-0000-0000-0000-000000000003'),
  ('d0000000-0000-0000-0000-000000000005', 'entrada', 'nf_entrada', 'd0000000-0000-0000-0000-000000000005', 10, 30.00, 10, 'a0000000-0000-0000-0000-000000000003');

-- ============================================================
-- 5) CHECKLIST técnico (necessário para concluir OS)
-- ============================================================
insert into checklist_templates (id, nome, ativo) values
  ('20000000-0000-0000-0000-000000000001', 'TESTE_Checklist_Padrao', true);
insert into checklist_template_itens (id, template_id, descricao, obrigatorio) values
  ('20000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', 'TESTE_Item_Obrigatorio_1', true),
  ('20000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000001', 'TESTE_Item_Opcional_1', false);

-- ============================================================
-- 6) ORÇAMENTOS em cada estado relevante
-- ============================================================
-- e0000000-...-0001: rascunho
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, criado_por) values
  ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'rascunho', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'TESTE_Servico_Generico', 1, 100.00);

-- e0000000-...-0002: enviado (equivalente a "aguardando aprovação" — o
-- schema não distingue um status próprio para isso, ver BR-035)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, criado_por) values
  ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'enviado', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'TESTE_Servico_Generico', 1, 200.00);

-- e0000000-...-0003: aprovado, pronto para converter em OS (E2E-001 etc.)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, autorizado_por_nome, autorizado_em, comprovante_path, criado_por) values
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'aprovado', 'TESTE_Responsavel_Cliente', now(), 'comprovantes/teste-autorizacao-0003.pdf', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000005', 'TESTE_Servico_Para_OS', 2, 150.00);

-- e0000000-...-0004: aprovado, cliente inadimplente (para gerar OS concluída
-- sem pagamento — LIB-003 / cenário de bloqueio financeiro)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, autorizado_por_nome, autorizado_em, comprovante_path, criado_por) values
  ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000003', 1, 'aprovado', 'TESTE_Responsavel_Inadimplente', now(), 'comprovantes/teste-autorizacao-0004.pdf', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000004', null, 'TESTE_Servico_Sem_Peca', 1, 500.00);

-- e0000000-...-0005: rejeitado
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, criado_por) values
  ('e0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'rejeitado', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000005', 'TESTE_Servico_Rejeitado', 1, 80.00);

-- e0000000-...-0006: aprovado, dedicado à garantia (vira OS liberada há 10 dias)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, autorizado_por_nome, autorizado_em, comprovante_path, criado_por) values
  ('e0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000004', 1, 'aprovado', 'TESTE_Responsavel_Garantia', now(), 'comprovantes/teste-autorizacao-0006.pdf', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000001', 'TESTE_Servico_Garantia_Dentro_Prazo', 1, 300.00);

-- e0000000-...-0007: aprovado, dedicado à garantia fora do prazo (OS liberada há 100 dias)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, autorizado_por_nome, autorizado_em, comprovante_path, criado_por) values
  ('e0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000004', 1, 'aprovado', 'TESTE_Responsavel_Garantia', now(), 'comprovantes/teste-autorizacao-0007.pdf', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000007', 'd0000000-0000-0000-0000-000000000001', 'TESTE_Servico_Garantia_Fora_Prazo', 1, 300.00);

-- e0000000-...-0008: aprovado, dedicado ao teste de cancelamento com estoque
-- já baixado (OS-010/P0-05)
insert into orcamentos (id, veiculo_id, cliente_id, versao, status, autorizado_por_nome, autorizado_em, comprovante_path, criado_por) values
  ('e0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'aprovado', 'TESTE_Responsavel_Cancelamento', now(), 'comprovantes/teste-autorizacao-0008.pdf', 'a0000000-0000-0000-0000-000000000002');
insert into orcamento_itens (orcamento_id, peca_id, descricao, quantidade, valor_unitario) values
  ('e0000000-0000-0000-0000-000000000008', 'd0000000-0000-0000-0000-000000000004', 'TESTE_Servico_Cancelamento', 1, 120.00);

-- ============================================================
-- 7) ORDENS DE SERVIÇO
-- ============================================================
-- f...0001: interna, aberta, cancelável (frota própria, sem orçamento)
insert into ordens_servico (id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'interna', 'aberta', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- f...0002: interna, em_execucao
insert into ordens_servico (id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'interna', 'em_execucao', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- f...0003: interna, aguardando_teste (concluível), checklist já respondido
-- ok para o item obrigatório -> pronta para rpc_concluir_os
insert into ordens_servico (id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'interna', 'aguardando_teste', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');
insert into os_checklist_respostas (os_id, template_item_id, ok, respondido_por, respondido_em) values
  ('f0000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000011', true, 'a0000000-0000-0000-0000-000000000001', now());

-- f...0004: externa, concluída, cliente normal, SEM cobrança ainda (para
-- gerar cobrança/parcelamento/pagamento nos testes de ETAPA 4/6/7)
insert into ordens_servico (id, orcamento_id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'externa', 'concluida', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- f...0005: externa, concluída, cliente INADIMPLENTE, sem cobrança/termo —
-- fixture pronta para LIB-003 (bloqueio) e E2E-005
insert into ordens_servico (id, orcamento_id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000005', 'e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000003', 'externa', 'concluida', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- f...0006: externa, LIBERADA há 10 dias (dentro do prazo de garantia de 90d)
insert into ordens_servico (id, orcamento_id, veiculo_id, cliente_id, tipo, status, checklist_template_id, data_liberacao, criado_por) values
  ('f0000000-0000-0000-0000-000000000006', 'e0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000004', 'externa', 'liberada', '20000000-0000-0000-0000-000000000001', now() - interval '10 days', 'a0000000-0000-0000-0000-000000000002');

-- f...0007: externa, LIBERADA há 100 dias (fora do prazo de garantia de 90d)
insert into ordens_servico (id, orcamento_id, veiculo_id, cliente_id, tipo, status, checklist_template_id, data_liberacao, criado_por) values
  ('f0000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000004', 'externa', 'liberada', '20000000-0000-0000-0000-000000000001', now() - interval '100 days', 'a0000000-0000-0000-0000-000000000002');

-- f...0008: externa, ABERTA, com 2 unidades de QA_PECA_CONCORRENCIA já
-- baixadas — fixture dedicada ao teste de cancelamento com estoque (OS-010)
insert into ordens_servico (id, orcamento_id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000008', 'e0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'externa', 'em_diagnostico', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');
update pecas set saldo_atual = saldo_atual - 2 where id = 'd0000000-0000-0000-0000-000000000004';
insert into estoque_movimentos (peca_id, tipo, origem_tipo, origem_id, quantidade, custo_unitario, saldo_resultante, criado_por) values
  ('d0000000-0000-0000-0000-000000000004', 'saida', 'os', 'f0000000-0000-0000-0000-000000000008', 2, 25.00, 8, 'a0000000-0000-0000-0000-000000000001');

-- f...0009: externa, ABERTA, apta a receber múltiplos executores (EXE-002/E2E-007)
insert into ordens_servico (id, veiculo_id, cliente_id, tipo, status, checklist_template_id, criado_por) values
  ('f0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'interna', 'em_execucao', '20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

-- ============================================================
-- 8) FINANCEIRO — cobrança aberta / paga / parcial / parcelada / termo
-- ============================================================
-- 10000000-...-0001: cobrança ABERTA (recém-criada, sem parcelamento) sobre
-- OS f...0004 (para depois testar rpc_parcelar_cobranca/rpc_registrar_recebimento)
insert into cobrancas (id, cliente_id, valor_total, status, criado_por) values
  ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 300.00, 'aberta', 'a0000000-0000-0000-0000-000000000003');
insert into cobranca_origens (cobranca_id, os_id) values
  ('10000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000004');

-- 10000000-...-0002: cobrança QUITADA (paga integralmente, 1 parcela)
insert into cobrancas (id, cliente_id, valor_total, status, criado_por) values
  ('10000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000004', 300.00, 'quitada', 'a0000000-0000-0000-0000-000000000003');
insert into cobranca_origens (cobranca_id, os_id) values
  ('10000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000006');
insert into parcelas (id, cobranca_id, numero_parcela, valor, vencimento, status) values
  ('10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000002', 1, 300.00, current_date - 5, 'paga');
insert into recebimentos (parcela_id, valor_recebido, forma_pagamento, data_recebimento, criado_por) values
  ('10000000-0000-0000-0000-000000000021', 300.00, 'pix', current_date - 5, 'a0000000-0000-0000-0000-000000000003');

-- 10000000-...-0003: cobrança PARCIAL (parcelada em 2x, só a 1ª paga)
insert into cobrancas (id, cliente_id, valor_total, status, criado_por) values
  ('10000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000004', 300.00, 'parcial', 'a0000000-0000-0000-0000-000000000003');
insert into cobranca_origens (cobranca_id, os_id) values
  ('10000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000007');
insert into parcelas (id, cobranca_id, numero_parcela, valor, vencimento, status) values
  ('10000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000003', 1, 150.00, current_date - 3, 'paga'),
  ('10000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000003', 2, 150.00, current_date + 27, 'pendente');
insert into recebimentos (parcela_id, valor_recebido, forma_pagamento, data_recebimento, criado_por) values
  ('10000000-0000-0000-0000-000000000031', 150.00, 'boleto', current_date - 3, 'a0000000-0000-0000-0000-000000000003');

-- Sem fixture de "termo de ciência de débito" pré-criada: o teste real de
-- LIB-002 (ETAPA 7) cria o termo em tempo de execução chamando
-- rpc_registrar_termo_ciencia sobre a cobrança da OS f...0005 (inadimplente),
-- exatamente como um usuário real faria — mais fiel que pré-inserir.

-- ============================================================
-- Fim do seed. Resumo do que fica pronto para uso imediato pelos scripts de
-- teste (ETAPA 4 em diante):
--   Login (Teste@2026!Qa): teste.executor / teste.encarregado / teste.suporte
--     / teste.admin / teste.diretoria / teste.inativo / teste.semperfil
--     (todos @qa.local)
--   OS f...0004 (concluída, sem cobrança) -> testar geração de cobrança
--   OS f...0005 (concluída, cliente inadimplente) -> LIB-003 / E2E-005
--   OS f...0006 (liberada há 10d) -> GAR-002/E2E-006 (dentro do prazo)
--   OS f...0007 (liberada há 100d) -> GAR-003 (fora do prazo)
--   OS f...0008 (com baixa de estoque, aberta) -> OS-010/P0-05 (cancelar)
--   Peça d...0002 (saldo 3) -> EST-007 (tentar baixar mais que o saldo)
--   Peça d...0004 (saldo 10, 2 já comprometidas em f...0008)
-- ============================================================
