-- ETAPA P2 — FEATURE-SERVICOS-01: catálogo estruturado de Serviços/Mão de
-- obra. Objetivo: padronizar nomenclatura de mão de obra vendida (hoje
-- texto livre em orcamento_itens.descricao) com preço de referência, tempo
-- estimado e garantia, SEM confundir com custo_hora_config (custo interno
-- da hora trabalhada, inalterado — ver custo_hora_vigente() em
-- 20260814110000_p1c_config_administrativa.sql).
--
-- Regra crítica: preço de venda do serviço é REFERÊNCIA. O item de
-- orçamento sempre guarda snapshot (código/descrição/preço/tempo/garantia
-- no momento do lançamento) — mudar o catálogo no futuro nunca altera um
-- orçamento/PDF/OS já emitido. O PDF (OrcamentoPdf.vue) já renderiza só
-- orcamento_itens.descricao/valor_unitario (nunca faz join vivo com
-- pecas/servicos), então a imutabilidade histórica já é garantida por
-- construção — não precisa de nenhuma mudança no PDF.
--
-- DEV/QA apenas nesta rodada — nenhuma promoção para produção aqui.

-- ============================================================
-- servico_categorias — estrutura simples e administrável (não hardcode de
-- lista de categorias). Mesmo padrão de centro_custo. Cadastro/edição
-- restrito a administrador_tecnico (mais estrutural que o catálogo de
-- serviços em si).
-- ============================================================
create table servico_categorias (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references profiles(id) default auth.uid()
);

alter table servico_categorias enable row level security;

create policy "servico_categorias_select_autenticado" on servico_categorias
  for select
  using (current_user_ativo());

create policy "servico_categorias_insert_admin" on servico_categorias
  for insert
  with check (tem_perfil('administrador_tecnico'));

create policy "servico_categorias_update_admin" on servico_categorias
  for update
  using (tem_perfil('administrador_tecnico'))
  with check (tem_perfil('administrador_tecnico'));

-- Seed inicial: categorias conceituais citadas no pedido, como dado inicial
-- editável (não regra de negócio hardcoded) — administrador_tecnico pode
-- renomear/inativar/adicionar livremente depois.
insert into servico_categorias (nome) values
  ('Ar-condicionado'),
  ('Mecânica'),
  ('Elétrica'),
  ('Suspensão'),
  ('Freios'),
  ('Preventiva'),
  ('Diagnóstico');

-- ============================================================
-- Geração de código humano (SV-001, SV-002, ...). Não existe nenhum
-- mecanismo equivalente hoje no sistema (nem pecas.sku, nem clientes/OS) —
-- padrão novo, isolado a servicos. Não é DEFAULT de coluna: a RPC de
-- criação decide (gera automático quando p_codigo vem vazio, ou usa o
-- código customizado informado), então a função só é chamada
-- explicitamente dentro de rpc_criar_servico.
-- ============================================================
create sequence servicos_codigo_seq;

create or replace function gerar_codigo_servico()
returns text
language sql
as $$
  select 'SV-' || lpad(nextval('servicos_codigo_seq')::text, 3, '0')
$$;

revoke execute on function gerar_codigo_servico() from public, anon, authenticated;

-- ============================================================
-- servicos — catálogo de serviços/mão de obra vendida. preco_referencia é
-- preço comercial de REFERÊNCIA (o item do orçamento pode divergir, ver
-- snapshot em orcamento_itens abaixo). garantia_dias default 90 documenta
-- BR-024 (garantia usual de 90 dias) só como metadado de referência do
-- catálogo — NÃO altera o literal fixo de 90 dias em rpc_criar_os_garantia
-- (20260812096000_p1a_gar005_vinculo_garantia.sql), que continua igual.
-- checklist_template_id reaproveita checklist_templates já existente (não
-- duplica foto_antes_obrigatoria/foto_depois_obrigatoria, que já vivem lá).
-- ============================================================
create table servicos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nome text not null check (length(trim(nome)) > 0),
  categoria_id uuid references servico_categorias(id),
  descricao text,
  preco_referencia numeric(12,2) not null check (preco_referencia >= 0),
  tempo_estimado_minutos integer check (tempo_estimado_minutos > 0),
  garantia_dias integer not null default 90 check (garantia_dias >= 0),
  checklist_template_id uuid references checklist_templates(id),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references profiles(id),
  atualizado_em timestamptz,
  atualizado_por uuid references profiles(id)
);

create index idx_servicos_categoria on servicos (categoria_id);
create index idx_servicos_ativo on servicos (ativo);

alter table servicos enable row level security;

-- Todo perfil tem ao menos "consultar" o catálogo (instrução seção 13).
-- Inativo continua visível aqui de propósito — a regra de "não aparece
-- como opção padrão para novos orçamentos" é responsabilidade do
-- frontend/RPC (filtrar ativo=true ao listar opções de lançamento), não da
-- RLS, porque histórico e catálogo administrativo (tela de Serviços)
-- também precisam listar inativos.
create policy "servicos_select_autenticado" on servicos
  for select
  using (current_user_ativo());

-- Escrita espelha pecas (catálogo comercial irmão): suporte_administrativo
-- + administrador_tecnico. Encarregado só consulta/seleciona no orçamento.
create policy "servicos_insert_cadastro" on servicos
  for insert
  with check (tem_perfil('suporte_administrativo', 'administrador_tecnico'));

create policy "servicos_update_cadastro" on servicos
  for update
  using (tem_perfil('suporte_administrativo', 'administrador_tecnico'))
  with check (tem_perfil('suporte_administrativo', 'administrador_tecnico'));

-- Sem policy de delete: soft-disable apenas via ativo=false (nunca exclusão
-- física de serviço já utilizado historicamente, instrução seção 12).

-- ============================================================
-- Extensão aditiva de orcamento_itens: hoje a distinção peça/mão-de-obra é
-- só inferida no frontend (peca_id ? 'Peça' : 'Mão de obra',
-- OrcamentosList.vue). Introduz coluna explícita `natureza` + vínculo
-- opcional a servicos + snapshot imutável (código/tempo/garantia — a
-- descrição/preço já são o próprio snapshot hoje, copiados no insert, sem
-- join vivo).
-- ============================================================
alter table orcamento_itens add column servico_id uuid references servicos(id);
alter table orcamento_itens add column natureza text not null default 'peca';
alter table orcamento_itens add column codigo_servico_snapshot text;
alter table orcamento_itens add column tempo_estimado_minutos_snapshot integer;
alter table orcamento_itens add column garantia_dias_snapshot integer;

-- Backfill determinístico: mesma inferência que o frontend já faz hoje
-- (peca_id não nulo => peça; senão => mão de obra). Não é inferência de
-- correspondência com o novo catálogo (proibido, instrução seção 23) — só
-- torna explícito um discriminador que já era 100% determinado pela
-- nulidade de peca_id.
update orcamento_itens set natureza = case when peca_id is not null then 'peca' else 'servico_avulso' end;

alter table orcamento_itens add constraint orcamento_itens_natureza_valores
  check (natureza in ('peca', 'servico_cadastrado', 'servico_avulso'));

alter table orcamento_itens add constraint orcamento_itens_natureza_consistente
  check (
    (natureza = 'peca' and peca_id is not null and servico_id is null) or
    (natureza = 'servico_cadastrado' and servico_id is not null and peca_id is null) or
    (natureza = 'servico_avulso' and peca_id is null and servico_id is null)
  );

comment on column orcamento_itens.natureza is
  'Discriminador explícito do item: peca (peca_id preenchido), servico_cadastrado (servico_id preenchido, snapshot em codigo_servico_snapshot/tempo_estimado_minutos_snapshot/garantia_dias_snapshot) ou servico_avulso (mão de obra livre, sem vínculo a catálogo). FEATURE-SERVICOS-01.';

-- ============================================================
-- RPCs de escrita do catálogo. Diferente de orcamento_itens (escrita
-- direta via RLS), servicos usa RPC porque a auditoria obrigatória
-- (instrução seção 14) só pode ser chamada de dentro de SECURITY DEFINER —
-- registrar_auditoria está com REVOKE EXECUTE FROM anon, authenticated
-- (20260812093500_p1a_auditoria.sql). rpc_inativar_servico/rpc_ativar_servico
-- são nomes novos no projeto (não existe rpc_inativar_* hoje) — necessário
-- pelo mesmo motivo de auditoria.
-- ============================================================
create or replace function rpc_criar_servico(
  p_nome text,
  p_preco_referencia numeric,
  p_codigo text default null,
  p_categoria_id uuid default null,
  p_descricao text default null,
  p_tempo_estimado_minutos integer default null,
  p_garantia_dias integer default 90,
  p_checklist_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo text;
  v_novo_id uuid;
  v_registro servicos;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para cadastrar serviço';
  end if;
  if p_nome is null or length(trim(p_nome)) < 2 then
    raise exception 'Nome do serviço é obrigatório';
  end if;
  if p_preco_referencia is null or p_preco_referencia < 0 then
    raise exception 'Preço de referência inválido';
  end if;
  if p_tempo_estimado_minutos is not null and p_tempo_estimado_minutos <= 0 then
    raise exception 'Tempo estimado deve ser positivo';
  end if;

  v_codigo := nullif(trim(p_codigo), '');
  if v_codigo is null then
    v_codigo := gerar_codigo_servico();
  end if;

  insert into servicos (
    codigo, nome, categoria_id, descricao, preco_referencia,
    tempo_estimado_minutos, garantia_dias, checklist_template_id, criado_por
  ) values (
    v_codigo, trim(p_nome), p_categoria_id, p_descricao, p_preco_referencia,
    p_tempo_estimado_minutos, coalesce(p_garantia_dias, 90), p_checklist_template_id, auth.uid()
  )
  returning id into v_novo_id;

  select * into v_registro from servicos where id = v_novo_id;
  perform registrar_auditoria('servicos', v_novo_id, 'criar_servico', null, to_jsonb(v_registro), null);

  return v_novo_id;
end;
$$;

create or replace function rpc_atualizar_servico(
  p_servico_id uuid,
  p_nome text,
  p_preco_referencia numeric,
  p_codigo text default null,
  p_categoria_id uuid default null,
  p_descricao text default null,
  p_tempo_estimado_minutos integer default null,
  p_garantia_dias integer default null,
  p_checklist_template_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atual servicos;
  v_novo servicos;
  v_codigo text;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para editar serviço';
  end if;
  if p_nome is null or length(trim(p_nome)) < 2 then
    raise exception 'Nome do serviço é obrigatório';
  end if;
  if p_preco_referencia is null or p_preco_referencia < 0 then
    raise exception 'Preço de referência inválido';
  end if;
  if p_tempo_estimado_minutos is not null and p_tempo_estimado_minutos <= 0 then
    raise exception 'Tempo estimado deve ser positivo';
  end if;

  select * into v_atual from servicos where id = p_servico_id for update;
  if v_atual.id is null then
    raise exception 'Serviço não encontrado';
  end if;

  v_codigo := coalesce(nullif(trim(p_codigo), ''), v_atual.codigo);

  update servicos set
    codigo = v_codigo,
    nome = trim(p_nome),
    categoria_id = p_categoria_id,
    descricao = p_descricao,
    preco_referencia = p_preco_referencia,
    tempo_estimado_minutos = p_tempo_estimado_minutos,
    garantia_dias = coalesce(p_garantia_dias, v_atual.garantia_dias),
    checklist_template_id = p_checklist_template_id,
    atualizado_em = now(),
    atualizado_por = auth.uid()
  where id = p_servico_id;

  select * into v_novo from servicos where id = p_servico_id;
  perform registrar_auditoria('servicos', p_servico_id, 'atualizar_servico',
    to_jsonb(v_atual), to_jsonb(v_novo), null);
end;
$$;

create or replace function rpc_ativar_servico(p_servico_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atual servicos;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para ativar serviço';
  end if;

  select * into v_atual from servicos where id = p_servico_id for update;
  if v_atual.id is null then
    raise exception 'Serviço não encontrado';
  end if;

  update servicos set ativo = true, atualizado_em = now(), atualizado_por = auth.uid()
  where id = p_servico_id;

  perform registrar_auditoria('servicos', p_servico_id, 'ativar_servico',
    jsonb_build_object('ativo', v_atual.ativo), jsonb_build_object('ativo', true), null);
end;
$$;

create or replace function rpc_inativar_servico(p_servico_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atual servicos;
begin
  if not tem_perfil('suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para inativar serviço';
  end if;

  select * into v_atual from servicos where id = p_servico_id for update;
  if v_atual.id is null then
    raise exception 'Serviço não encontrado';
  end if;

  update servicos set ativo = false, atualizado_em = now(), atualizado_por = auth.uid()
  where id = p_servico_id;

  perform registrar_auditoria('servicos', p_servico_id, 'inativar_servico',
    jsonb_build_object('ativo', v_atual.ativo), jsonb_build_object('ativo', false), null);
end;
$$;
