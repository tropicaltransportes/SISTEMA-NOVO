-- LIB-001, LIB-002, LIB-003 — executado via `supabase db query --linked -f`.
-- Monta OS externas concluídas idênticas, cada uma variando só a condição
-- financeira, e confirma que rpc_liberar_os segue exatamente BR-023.
begin;
select plan(4);

-- Helper local: cria orçamento aprovado simples e a OS externa já 'concluida'.
-- Precisa ser criada ANTES de trocar de papel (CREATE FUNCTION no schema
-- "tests" exige privilégio de dono/superusuário, que "authenticated" não tem).
create or replace function tests._preparar_os_concluida(p_sufixo text) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orc uuid; v_os uuid;
begin
  insert into orcamentos (veiculo_id, cliente_id, criado_por, status)
    values ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', auth.uid(), 'rascunho')
    returning id into v_orc;
  insert into orcamento_itens (orcamento_id, descricao, quantidade, valor_unitario) values (v_orc, 'PGTAP Serviço ' || p_sufixo, 1, 500);
  update orcamentos set status = 'enviado', autorizado_por_nome = 'Teste', comprovante_path = 'x' where id = v_orc;
  -- ETAPA 5 (P1-B)/APR-002: aprovação passou a ser por ITEM — o fixture
  -- bypassava a máquina de estados direto no orçamento (comentário original
  -- acima), então precisa também aprovar o(s) item(ns) para que
  -- rpc_criar_os (que agora exige ao menos 1 item com status_aprovacao =
  -- 'aprovado') aceite converter. Este teste (LIB-00x) não é sobre
  -- aprovação — só precisa de um orçamento 100% aprovado como fixture.
  update orcamento_itens
    set status_aprovacao = 'aprovado', meio_aprovacao = 'sistema',
        autorizado_por_nome = 'Teste', autorizado_em = now(), registrado_por = auth.uid()
    where orcamento_id = v_orc;
  update orcamentos set status = 'aprovado' where id = v_orc;
  v_os := rpc_criar_os('77777777-7777-7777-7777-777777777777'::uuid, 'externa'::tipo_os, v_orc);
  -- força a OS direto para 'concluida' via update de teste (bypassa a máquina de estados só para montar o fixture)
  update ordens_servico set status = 'concluida' where id = v_os;
  return v_os;
end;
$$;

select tests.autenticar_como(tests.criar_usuario_teste('administrador_tecnico'::perfil_usuario));

insert into clientes (id, tipo, nome) values ('66666666-6666-6666-6666-666666666666', 'externo', 'PGTAP Cliente Teste LIB');
insert into veiculos (id, cliente_id, placa) values ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', 'PGTAP003');

-- LIB-002: termo de ciência de débito, sem pagamento -> liberação permitida.
-- ETAPA 4 (P1-A)/DOC-005: rpc_registrar_termo_ciencia agora valida que o
-- objeto existe de fato em storage.objects (ver
-- 20260812097000_p1a_doc005_valida_storage.sql) — este teste roda só em SQL
-- (sem passar pela API de Storage), então precisa inserir a linha
-- correspondente em storage.objects para simular o upload real antes de
-- chamar a RPC, senão o teste passaria a falhar por um motivo NOVO e
-- correto (path inexistente), não relacionado ao que LIB-002 verifica.
do $$
declare v_os uuid; v_cob uuid;
begin
  v_os := tests._preparar_os_concluida('LIB002');
  v_cob := rpc_criar_cobranca('66666666-6666-6666-6666-666666666666'::uuid, array[v_os], null);
  insert into storage.objects (bucket_id, name) values ('comprovantes', 'termos/pgtap-teste-' || v_cob::text || '.pdf');
  -- RC1: rpc_registrar_termo_ciencia(uuid, text) (2 params) foi removida em
  -- 20260815120000_rc1_fix_overload_orfao_termo_ciencia.sql (overload órfão
  -- que contornava a Decisão 8 — ver o comentário na própria migration).
  -- Assinatura única agora exige p_responsavel_nome.
  perform rpc_registrar_termo_ciencia(v_cob, 'termos/pgtap-teste-' || v_cob::text || '.pdf', 'PGTAP Responsável Teste', '000.000.000-00', null);
  perform rpc_liberar_os(v_os);
  perform set_config('tests.lib002_os', v_os::text, true);
end $$;

-- DOC-005 (ETAPA 4 P1-A): path que não existe no Storage deve ser rejeitado
-- pela mesma RPC, mesmo com todos os outros dados válidos.
do $$
declare v_os uuid; v_cob uuid;
begin
  v_os := tests._preparar_os_concluida('DOC005');
  v_cob := rpc_criar_cobranca('66666666-6666-6666-6666-666666666666'::uuid, array[v_os], null);
  perform set_config('tests.doc005_cobranca', v_cob::text, true);
end $$;

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

select throws_ok(
  format('select rpc_liberar_os(%L)', tests._preparar_os_concluida('LIB003')),
  'P0001', 'OS externa exige cobrança gerada antes da liberação',
  'LIB-003: OS externa concluída sem cobrança nenhuma deve ser bloqueada na liberação'
)
union all
select is(
  (select status from ordens_servico where id = current_setting('tests.lib002_os')::uuid),
  'liberada',
  'LIB-002: liberação com Termo de Ciência de Débito (sem pagamento) deve ser permitida'
)
union all
select is(
  (select status from ordens_servico where id = current_setting('tests.lib001_os')::uuid),
  'liberada',
  'LIB-001: liberação com cobrança quitada deve ser permitida'
)
union all
select throws_ok(
  format('select rpc_registrar_termo_ciencia(%L, %L, %L, %L, %L)', current_setting('tests.doc005_cobranca')::uuid, 'caminho/inexistente-doc005.pdf', 'PGTAP Responsável Teste', '000.000.000-00', null),
  'P0001', null,
  'DOC-005: termo com path inexistente no Storage deve ser rejeitado'
);

rollback;
