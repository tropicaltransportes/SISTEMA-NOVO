-- ETAPA 4 (P1-A) — item C: ORC-016, impedir criação duplicada de orçamento
-- por duplo clique / retry de rede. Criação de orçamento (V1) é feita por
-- INSERT direto na tabela (não por RPC — ver orcamentos_insert_v1 em
-- 20260806130100_orcamentos.sql), então desabilitar o botão no frontend não
-- é suficiente contra um retry de rede real (a mesma requisição HTTP
-- reenviada pelo browser/proxy, ou duas abas). Mesmo mecanismo já usado com
-- sucesso em estoque_movimentos.idempotency_key (EST-009, ETAPA 3): coluna
-- opcional preenchida pelo cliente + índice único parcial — a 2ª tentativa
-- com a MESMA chave sempre falha no banco, não importa quantas vezes ou
-- quão rápido for repetida.
alter table orcamentos add column if not exists client_request_id uuid;

create unique index if not exists ux_orcamentos_client_request_id
  on orcamentos (client_request_id)
  where client_request_id is not null;

comment on column orcamentos.client_request_id is
  'UUID gerado pelo frontend uma única vez por abertura do formulário "Novo Orçamento" e reenviado sem trocar em caso de retry/duplo clique. Índice único parcial garante que a mesma chave nunca cria uma 2ª linha (ORC-016, ver docs/testing/TEST_REPORT_P1A.md). NULL permitido e repetível (linhas antigas, ou inserts que não passam pela idempotência, ex.: rpc_criar_versao_orcamento).';
