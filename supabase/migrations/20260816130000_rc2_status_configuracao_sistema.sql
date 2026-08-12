-- ETAPA 8 (RC2) — seção 2: bootstrap / configuração inicial.
--
-- Achado do RC1 (ver docs/testing/TEST_REPORT_RC1.md, seções 7/8): depois de
-- um rebuild limpo (`db reset --linked`), `anexos_config` fica vazia e
-- bloqueia upload de fotos até um administrador configurá-la manualmente.
--
-- Causa raiz investigada nesta rodada (RC2): a migration
-- 20260814110000_p1c_config_administrativa.sql já TENTA semear valores
-- iniciais para `desconto_config` (10%) e `anexos_config` (5MB, jpeg/png/
-- webp) via `insert into ... select ... from profiles where perfil =
-- 'administrador_tecnico' ... limit 1`. Essa migration roda ANTES do
-- `supabase/seed.sql` (migrations sempre aplicam antes do seed, tanto em
-- `db reset --linked` quanto em qualquer criação de projeto nova), e o
-- administrador técnico só é criado DEPOIS, pelo seed (ambiente de
-- QA) ou manualmente por um humano (produção). Ou seja: numa instalação
-- limpa não existe NENHUMA linha em `profiles` com
-- perfil = 'administrador_tecnico' no momento em que essa migration roda —
-- o `select` não encontra nenhuma linha, o `insert ... select` insere ZERO
-- linhas, silenciosamente (não é um erro de SQL, só não insere nada). Por
-- isso `anexos_config` (e, no mesmo mecanismo, `desconto_config`) ficam
-- vazias após um rebuild limpo. `custo_hora_config` e `centro_custo` nunca
-- tiveram sequer uma tentativa de seed automático — sempre dependeram de
-- configuração manual.
--
-- Não corrigimos esse "seed automático" (não é o objetivo desta rodada
-- preencher valor de negócio nenhum por migration — o roteiro da ETAPA 8
-- proíbe isso explicitamente) — na verdade, o comportamento correto e
-- desejado é justamente este: nenhuma configuração de negócio deve nascer
-- sozinha com valores fictícios em produção. A migration antiga não é
-- alterada (regra permanente do projeto). Em vez disso, esta migration cria
-- um mecanismo de VERIFICAÇÃO explícita, para que uma instalação incompleta
-- nunca pareça operacional silenciosamente.

-- ============================================================
-- rpc_status_configuracao_sistema — retorna, item a item, se a configuração
-- inicial obrigatória está presente. Não inventa nem preenche nada; só
-- reporta o estado real encontrado no banco.
-- ============================================================
create or replace function rpc_status_configuracao_sistema()
returns table (
  item text,
  configurado boolean,
  detalhe text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para consultar status de configuração inicial do sistema';
  end if;

  return query
  select
    'administrador_tecnico'::text as item,
    exists(select 1 from profiles p where p.perfil = 'administrador_tecnico' and p.ativo) as configurado,
    (select 'Ativos: ' || count(*)::text from profiles p where p.perfil = 'administrador_tecnico' and p.ativo) as detalhe

  union all
  select
    'custo_hora_config'::text,
    exists(select 1 from custo_hora_config),
    coalesce(
      (select 'Vigente: R$ ' || to_char(custo_hora_vigente(), 'FM999999990.00') || '/h'
         from custo_hora_config limit 1),
      'Nenhum valor de custo/hora cadastrado — obrigatório antes de encerrar OS interna'
    )

  union all
  select
    'desconto_config'::text,
    exists(select 1 from desconto_config),
    coalesce(
      (select 'Teto vigente: ' || percentual_maximo::text || '% (habilitado=' || habilitado::text || ')'
         from desconto_config_vigente()),
      'Nenhum teto de desconto cadastrado — nenhum desconto pode ser concedido'
    )

  union all
  select
    'anexos_config'::text,
    exists(select 1 from anexos_config),
    coalesce(
      (select 'Máx ' || (tamanho_maximo_bytes / 1048576.0)::numeric(10,1)::text || 'MB, MIME: ' || array_to_string(mime_permitidos, ', ')
         from anexos_config_vigente()),
      'Nenhum limite de anexos cadastrado — upload de fotos/comprovantes ficará bloqueado'
    )

  union all
  select
    'centro_custo'::text,
    exists(select 1 from centro_custo where ativo),
    (select 'Ativos: ' || count(*)::text from centro_custo where ativo)

  union all
  select
    'checklist_template'::text,
    exists(select 1 from checklist_templates where ativo),
    (select 'Ativos: ' || count(*)::text from checklist_templates where ativo);
end;
$$;

comment on function rpc_status_configuracao_sistema is
  'ETAPA 8 (RC2) seção 2. Verificação de configuração inicial (bootstrap) do sistema — não preenche nada, só reporta o que já existe. Usado pela tela administrativa para exibir CONFIGURADO/PENDENTE por item, evitando que uma instalação incompleta pareça operacional. Restrito a encarregado/suporte_administrativo/administrador_tecnico (mesmo critério de leitura de custo_hora_config/desconto_config) via checagem interna tem_perfil() — mesmo padrão das demais rpc_ deste projeto (falha fechado para anon/executor, sem depender de REVOKE explícito).';
