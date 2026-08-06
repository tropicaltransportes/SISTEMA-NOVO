-- Fase 2: ordens de serviço, execução (múltiplos executores/etapas),
-- checklist configurável de liberação técnica e baixa de estoque vinculada.

create type status_os as enum (
  'aberta', 'em_diagnostico', 'aguardando_aprovacao', 'em_execucao',
  'aguardando_teste', 'concluida', 'liberada', 'reaberta_garantia', 'cancelada'
);
create type tipo_os as enum ('interna', 'externa');
create type etapa_execucao as enum ('diagnostico', 'execucao', 'teste', 'revisao');

create table checklist_templates (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  ativo boolean not null default true
);

create table checklist_template_itens (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references checklist_templates(id) on delete cascade,
  descricao text not null,
  obrigatorio boolean not null default true
);

create index idx_checklist_itens_template on checklist_template_itens (template_id);

create table ordens_servico (
  id uuid primary key default gen_random_uuid(),
  orcamento_id uuid references orcamentos(id), -- obrigatório se tipo='externa'
  veiculo_id uuid not null references veiculos(id),
  cliente_id uuid not null references clientes(id),
  tipo tipo_os not null,
  status status_os not null default 'aberta',
  checklist_template_id uuid references checklist_templates(id),
  os_origem_id uuid references ordens_servico(id), -- preenchido só em retorno de garantia (Fase 4)
  data_abertura timestamptz not null default now(),
  data_liberacao timestamptz,
  criado_por uuid not null references profiles(id),
  constraint os_externa_exige_orcamento check (tipo <> 'externa' or orcamento_id is not null)
);

create index idx_os_status on ordens_servico (status, data_abertura);
create index idx_os_veiculo on ordens_servico (veiculo_id);
create index idx_os_orcamento on ordens_servico (orcamento_id);

create table os_executores (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  usuario_id uuid not null references profiles(id),
  etapa etapa_execucao not null,
  inicio timestamptz not null,
  fim timestamptz,
  observacao text
);

create index idx_os_executores_os on os_executores (os_id);
create index idx_os_executores_usuario on os_executores (usuario_id);

create table os_checklist_respostas (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  template_item_id uuid not null references checklist_template_itens(id),
  ok boolean not null default false,
  respondido_por uuid references profiles(id),
  respondido_em timestamptz,
  unique (os_id, template_item_id)
);

create index idx_os_checklist_os on os_checklist_respostas (os_id);

-- ============================================================
-- RLS
-- ============================================================
alter table checklist_templates enable row level security;
alter table checklist_template_itens enable row level security;
alter table ordens_servico enable row level security;
alter table os_executores enable row level security;
alter table os_checklist_respostas enable row level security;

create policy "checklist_templates_select_autenticado" on checklist_templates
  for select
  using (auth.uid() is not null);

create policy "checklist_templates_insert_gestao" on checklist_templates
  for insert
  with check (current_perfil() in ('encarregado', 'administrador_tecnico'));

create policy "checklist_templates_update_gestao" on checklist_templates
  for update
  using (current_perfil() in ('encarregado', 'administrador_tecnico'))
  with check (current_perfil() in ('encarregado', 'administrador_tecnico'));

create policy "checklist_itens_select_autenticado" on checklist_template_itens
  for select
  using (auth.uid() is not null);

create policy "checklist_itens_insert_gestao" on checklist_template_itens
  for insert
  with check (current_perfil() in ('encarregado', 'administrador_tecnico'));

create policy "checklist_itens_update_gestao" on checklist_template_itens
  for update
  using (current_perfil() in ('encarregado', 'administrador_tecnico'))
  with check (current_perfil() in ('encarregado', 'administrador_tecnico'));

create policy "checklist_itens_delete_gestao" on checklist_template_itens
  for delete
  using (current_perfil() in ('encarregado', 'administrador_tecnico'));

-- ordens_servico: leitura liberada a todos os autenticados (inclusive diretoria,
-- só-leitura). Toda escrita (criação e transições de status) passa pelas RPCs
-- abaixo, que validam consistência com orçamento/veículo e a máquina de estados.
create policy "os_select_autenticado" on ordens_servico
  for select
  using (auth.uid() is not null);

revoke insert, update on ordens_servico from authenticated;

create policy "os_executores_select_autenticado" on os_executores
  for select
  using (auth.uid() is not null);

-- Apontamento de horas: cada executor lança/encerra o próprio apontamento.
create policy "os_executores_insert_proprio" on os_executores
  for insert
  with check (
    usuario_id = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
  );

create policy "os_executores_update_proprio" on os_executores
  for update
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

create policy "os_checklist_select_autenticado" on os_checklist_respostas
  for select
  using (auth.uid() is not null);

-- Resposta de checklist: executor/encarregado respondem, sempre carimbando o
-- próprio usuário; bloqueado se a OS já está concluída/liberada/cancelada.
create policy "os_checklist_insert_resposta" on os_checklist_respostas
  for insert
  with check (
    respondido_por = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (
      select 1 from ordens_servico os
      where os.id = os_checklist_respostas.os_id
        and os.status not in ('concluida', 'liberada', 'cancelada')
    )
  );

create policy "os_checklist_update_resposta" on os_checklist_respostas
  for update
  using (
    current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
    and exists (
      select 1 from ordens_servico os
      where os.id = os_checklist_respostas.os_id
        and os.status not in ('concluida', 'liberada', 'cancelada')
    )
  )
  with check (
    respondido_por = auth.uid()
    and current_perfil() in ('executor', 'encarregado', 'administrador_tecnico')
  );

-- ============================================================
-- Baixa de estoque: a RPC genérica da Fase 1 passa a ser acessível apenas
-- por dono/superuser (chamadas apenas de dentro de outras RPCs SECURITY
-- DEFINER); o cliente autenticado só baixa peça via rpc_baixar_peca_os ou
-- (Fase 2, próxima migration) rpc_criar_venda_avulsa.
-- ============================================================
revoke execute on function rpc_registrar_saida_estoque(uuid, numeric, origem_movimento, uuid) from public;

-- ============================================================
-- RPCs
-- ============================================================

-- Cria a OS validando consistência veículo/cliente/orçamento e convertendo
-- a solicitação de origem, se houver.
create or replace function rpc_criar_os(
  p_veiculo_id uuid,
  p_tipo tipo_os,
  p_orcamento_id uuid default null,
  p_solicitacao_id uuid default null,
  p_checklist_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_veiculo record;
  v_cliente_tipo tipo_cliente;
  v_orc record;
  v_novo_id uuid;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para criar ordem de serviço';
  end if;

  select v.id, v.cliente_id into v_veiculo from veiculos v where v.id = p_veiculo_id and v.deleted_at is null;
  if v_veiculo.id is null then
    raise exception 'Veículo não encontrado';
  end if;

  select tipo into v_cliente_tipo from clientes where id = v_veiculo.cliente_id;
  if p_tipo = 'interna' and v_cliente_tipo <> 'interno' then
    raise exception 'OS interna exige veículo da frota própria (cliente interno)';
  end if;
  if p_tipo = 'externa' and v_cliente_tipo <> 'externo' then
    raise exception 'OS externa exige veículo de cliente externo';
  end if;

  if p_tipo = 'externa' then
    if p_orcamento_id is null then
      raise exception 'OS externa exige orçamento aprovado';
    end if;
    select * into v_orc from orcamentos where id = p_orcamento_id for update;
    if v_orc.id is null then
      raise exception 'Orçamento não encontrado';
    end if;
    if v_orc.status <> 'aprovado' then
      raise exception 'Orçamento precisa estar aprovado para gerar OS';
    end if;
    if v_orc.veiculo_id <> p_veiculo_id then
      raise exception 'Orçamento não pertence ao veículo informado';
    end if;
  end if;

  insert into ordens_servico (orcamento_id, veiculo_id, cliente_id, tipo, checklist_template_id, criado_por)
  values (p_orcamento_id, p_veiculo_id, v_veiculo.cliente_id, p_tipo, p_checklist_template_id, auth.uid())
  returning id into v_novo_id;

  if p_solicitacao_id is not null then
    perform marcar_solicitacao_convertida(p_solicitacao_id, 'convertida_os');
  end if;

  return v_novo_id;
end;
$$;

-- Define/troca o checklist técnico da OS enquanto ela ainda está ativa
-- (permite montar a OS sem checklist e associar depois, ou corrigir escolha).
create or replace function rpc_definir_checklist_os(p_os_id uuid, p_checklist_template_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para definir checklist da OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada, checklist não pode mais ser alterado';
  end if;

  update ordens_servico set checklist_template_id = p_checklist_template_id where id = p_os_id;
end;
$$;

-- Transições "simples" da máquina de estados (sem gate adicional). Concluída,
-- Liberada e Reaberta (garantia) têm RPCs próprias porque exigem validação
-- extra (checklist, condição financeira, prazo de garantia).
create or replace function rpc_transicionar_os(p_os_id uuid, p_novo_status status_os)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_permitido boolean := false;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para transicionar OS';
  end if;

  if p_novo_status in ('concluida', 'liberada', 'reaberta_garantia') then
    raise exception 'Use a RPC específica para esta transição (rpc_concluir_os / rpc_liberar_os)';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;

  v_permitido := (v_status, p_novo_status) in (
    ('aberta', 'em_diagnostico'),
    ('em_diagnostico', 'aguardando_aprovacao'),
    ('em_diagnostico', 'em_execucao'),
    ('aguardando_aprovacao', 'em_execucao'),
    ('em_execucao', 'aguardando_teste'),
    ('aberta', 'cancelada'),
    ('em_diagnostico', 'cancelada'),
    ('aguardando_aprovacao', 'cancelada')
  );

  if not v_permitido then
    raise exception 'Transição % -> % não é permitida', v_status, p_novo_status;
  end if;

  update ordens_servico set status = p_novo_status where id = p_os_id;
end;
$$;

-- Conclusão técnica: exige checklist definido e todos os itens obrigatórios
-- respondidos com ok=true.
create or replace function rpc_concluir_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_pendente boolean;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para concluir OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'aguardando_teste' then
    raise exception 'Somente OS em Aguardando Teste podem ser concluídas';
  end if;
  if v_os.checklist_template_id is null then
    raise exception 'OS sem checklist técnico definido — associe um checklist antes de concluir';
  end if;

  select exists (
    select 1 from checklist_template_itens cti
    where cti.template_id = v_os.checklist_template_id
      and cti.obrigatorio
      and not exists (
        select 1 from os_checklist_respostas r
        where r.template_item_id = cti.id and r.os_id = p_os_id and r.ok = true
      )
  ) into v_pendente;

  if v_pendente then
    raise exception 'Existem itens obrigatórios do checklist pendentes';
  end if;

  update ordens_servico set status = 'concluida' where id = p_os_id;
end;
$$;

-- Liberação: OS interna sempre liberável; OS externa depende de condição
-- financeira (Fase 3 — cobranças/quitação/termo), ainda não implementada.
create or replace function rpc_liberar_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para liberar OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'concluida' then
    raise exception 'Somente OS concluída pode ser liberada';
  end if;
  if v_os.tipo = 'externa' then
    raise exception 'Liberação de OS externa depende do módulo financeiro (Fase 3), ainda não implementado';
  end if;

  update ordens_servico set status = 'liberada', data_liberacao = now() where id = p_os_id;
end;
$$;

-- Baixa de peça consumida na OS (diagnóstico ou execução). Wrapper com
-- validação de perfil/status em torno da RPC genérica de saída de estoque.
create or replace function rpc_baixar_peca_os(p_os_id uuid, p_peca_id uuid, p_quantidade numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
begin
  if current_perfil() not in ('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para baixar peça em OS';
  end if;

  select status into v_status from ordens_servico where id = p_os_id;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status not in ('em_diagnostico', 'em_execucao') then
    raise exception 'Peças só podem ser baixadas com a OS em diagnóstico ou execução';
  end if;

  perform rpc_registrar_saida_estoque(p_peca_id, p_quantidade, 'os', p_os_id);
end;
$$;
