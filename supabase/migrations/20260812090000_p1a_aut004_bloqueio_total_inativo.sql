-- ETAPA 4 (P1-A) — Decisão de negócio #2: estende a correção AUT-004 da
-- ETAPA 3 (docs/testing/TEST_REPORT_EXECUTION_03.md, seção 3).
--
-- O que a ETAPA 3 já corrigiu: current_perfil() passou a retornar NULL para
-- profiles.ativo=false, o que já bloqueia (fail-closed) TODA escrita/RPC que
-- valida perfil via current_perfil()/tem_perfil() — a esmagadora maioria das
-- policies de INSERT/UPDATE do projeto já usa esse padrão, então já ficaram
-- protegidas automaticamente (nenhuma mudança necessária nelas).
--
-- O que faltava (pedido explícito desta rodada): SELECT. Boa parte das
-- tabelas usa a policy "<tabela>_select_autenticado" com
-- `using (auth.uid() is not null)` — isso NÃO chama current_perfil(), então
-- um usuário com sessão válida no Auth mas profiles.ativo=false continuava
-- lendo clientes, veículos, orçamentos, OS, estoque, checklist etc.
-- normalmente. As tabelas do módulo financeiro e o bucket 'comprovantes' já
-- usavam `current_perfil() <> 'executor'`, que JÁ é fail-closed para
-- inativo (NULL <> 'executor' avalia NULL, tratado como falso pelo RLS) —
-- não precisam de nenhuma mudança, só confirmação por teste.
--
-- Ponto único de verificação: current_user_ativo(), reaproveitando
-- current_perfil() (já fail-closed) em vez de duplicar a lógica de
-- sessão+ativo em cada policy nova.
create or replace function current_user_ativo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select current_perfil() is not null
$$;

comment on function current_user_ativo is
  'true quando há sessão válida, profiles.ativo=true e perfil reconhecido. Reusa current_perfil() (fail-closed p/ sem-sessão e p/ ativo=false, ver ETAPA 3). Usado nas policies de SELECT que antes só checavam auth.uid() is not null, para bloquear leitura de usuário inativo (ETAPA 4 P1-A, decisão de negócio #2, ver docs/testing/TEST_REPORT_P1A.md).';

-- ============================================================
-- Troca "auth.uid() is not null" por "current_user_ativo()" em todas as
-- policies de SELECT que usavam o padrão antigo (ALTER POLICY preserva o
-- nome/tabela, só troca a expressão USING — não precisa DROP/CREATE).
-- ============================================================
alter policy "profiles_select_autenticado" on profiles
  using (current_user_ativo());

alter policy "clientes_select_autenticado" on clientes
  using (current_user_ativo());
alter policy "veiculos_select_autenticado" on veiculos
  using (current_user_ativo());

alter policy "solicitacoes_select_autenticado" on solicitacoes_servico
  using (current_user_ativo());

alter policy "pecas_select_autenticado" on pecas
  using (current_user_ativo());
alter policy "estoque_movimentos_select_autenticado" on estoque_movimentos
  using (current_user_ativo());
alter policy "nf_select_autenticado" on notas_fiscais_entrada
  using (current_user_ativo());
alter policy "nf_itens_select_autenticado" on nf_entrada_itens
  using (current_user_ativo());
alter policy "ajustes_estoque_select_autenticado" on ajustes_estoque
  using (current_user_ativo());

alter policy "vendas_avulsas_select_autenticado" on vendas_avulsas
  using (current_user_ativo());
alter policy "venda_itens_select_autenticado" on venda_avulsa_itens
  using (current_user_ativo());

alter policy "orcamentos_select_autenticado" on orcamentos
  using (current_user_ativo());
alter policy "orcamento_itens_select_autenticado" on orcamento_itens
  using (current_user_ativo());
alter policy "faixa_acrescimo_select_autenticado" on orcamento_faixa_acrescimo
  using (current_user_ativo());
alter policy "orcamento_acrescimos_select_autenticado" on orcamento_acrescimos
  using (current_user_ativo());

alter policy "checklist_templates_select_autenticado" on checklist_templates
  using (current_user_ativo());
alter policy "checklist_itens_select_autenticado" on checklist_template_itens
  using (current_user_ativo());
alter policy "os_select_autenticado" on ordens_servico
  using (current_user_ativo());
alter policy "os_executores_select_autenticado" on os_executores
  using (current_user_ativo());
alter policy "os_checklist_select_autenticado" on os_checklist_respostas
  using (current_user_ativo());

-- Financeiro e bucket 'comprovantes' NÃO precisam de ALTER: já usam
-- `current_perfil() <> 'executor'`, que já é NULL (=> falso) para usuário
-- inativo desde a ETAPA 3. Confirmado por teste real, não só por leitura de
-- código (ver docs/testing/TEST_REPORT_P1A.md).
