-- FEATURE-SERVICOS-01 — correção same-day da migration anterior
-- (20260817140000_p2_servicos_catalogo.sql).
--
-- Achado ao rodar a regressão pgTAP (supabase/tests/030_orcamento.sql,
-- 040_liberacao.sql): `natureza` como coluna manual com `default 'peca'` +
-- CHECK orcamento_itens_natureza_consistente quebrou fixtures existentes
-- que inserem orcamento_itens sem peca_id e SEM informar natureza (ex.:
-- `insert into orcamento_itens (orcamento_id, descricao, quantidade,
-- valor_unitario) values (...)`, o padrão usado tanto nos testes quanto no
-- frontend atual OrcamentosList.vue, que ainda não sabe da coluna
-- `natureza`). Com o default 'peca', essas linhas viravam
-- natureza='peca' + peca_id null, violando o CHECK.
--
-- Correção: `natureza` passa a ser coluna GERADA (generated always as,
-- stored), derivada de peca_id/servico_id — nunca definida manualmente,
-- então não existe mais divergência possível entre o valor e os dados reais
-- da linha, e nenhum código (teste ou frontend) precisa ser alterado para
-- continuar inserindo itens de peça/mão-de-obra avulsa como já fazia.
alter table orcamento_itens drop constraint if exists orcamento_itens_natureza_consistente;
alter table orcamento_itens drop constraint if exists orcamento_itens_natureza_valores;
alter table orcamento_itens drop column if exists natureza;

-- Continua proibido um item ser peça E serviço cadastrado ao mesmo tempo
-- (impossível de expressar isso via coluna gerada sozinha — ela só
-- prioriza peca_id nesse caso; a combinação em si precisa ser rejeitada).
alter table orcamento_itens add constraint orcamento_itens_peca_ou_servico_nao_ambos
  check (not (peca_id is not null and servico_id is not null));

alter table orcamento_itens add column natureza text generated always as (
  case
    when peca_id is not null then 'peca'
    when servico_id is not null then 'servico_cadastrado'
    else 'servico_avulso'
  end
) stored;

comment on column orcamento_itens.natureza is
  'Discriminador DERIVADO (generated always as, não gravável diretamente) de peca_id/servico_id: peca, servico_cadastrado ou servico_avulso. Quando servico_cadastrado, o snapshot imutável fica em codigo_servico_snapshot/tempo_estimado_minutos_snapshot/garantia_dias_snapshot. FEATURE-SERVICOS-01 (corrigido em 20260817140100 — a primeira versão, com natureza como coluna manual + DEFAULT, quebrava fixtures/uso existente que não informava a coluna).';
