-- ETAPA 4 (P1-A) — item B: CAD-004, impedir duplicidade indevida de
-- documento de cliente (docs/testing/TEST_REPORT_EXECUTION_02.md linha 310:
-- "seed.sql inseriu 2 clientes com mesmo documento sem erro" — FALHOU
-- confirmado por execução real).
--
-- Regra: dois clientes ATIVOS (deleted_at is null) não podem ter o mesmo
-- documento depois de normalizado (só dígitos — remove ponto/traço/barra/
-- espaço, cobre CPF e CNPJ com máscaras diferentes representando o mesmo
-- número). documento NULL é permitido e pode repetir livremente (cliente
-- interno da frota própria não tem documento — BR-001). Cliente INATIVO
-- (soft delete via deleted_at) não conta para a checagem: permite reativar
-- o mesmo documento em um cadastro novo depois de um cadastro antigo ser
-- inativado, sem ficar "preso" para sempre por um registro morto.
create or replace function normalizar_documento(p_documento text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(p_documento, ''), '\D', '', 'g'), '')
$$;

comment on function normalizar_documento is
  'Remove tudo que não é dígito (ponto, traço, barra, espaço) para comparar CPF/CNPJ com máscaras diferentes como o mesmo documento. Retorna NULL se não sobrar nenhum dígito. Usado pelo índice único parcial de clientes.documento (CAD-004, ver docs/testing/TEST_REPORT_P1A.md).';

-- Corrige o dado de teste que provava o bug antes da correção (seed.sql
-- criava b...0005/b...0006 deliberadamente com o mesmo documento). Depois
-- desta migration o índice único bloquearia esse INSERT — o dado existente
-- também precisa deixar de violar a nova regra, senão a criação do índice
-- falha. b...0006 passa a ter um documento distinto (mesmo padrão de CNPJ
-- fictício, só muda o último dígito), documentado e espelhado em seed.sql.
update clientes
  set documento = '44444444000105'
  where id = 'b0000000-0000-0000-0000-000000000006'
    and documento = '44444444000104';

create unique index uq_clientes_documento_normalizado_ativo
  on clientes (normalizar_documento(documento))
  where documento is not null and deleted_at is null;
