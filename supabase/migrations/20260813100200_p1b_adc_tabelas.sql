-- ETAPA 5 (P1-B) — ADC-001..008: adicionais durante a OS.
--
-- Fluxo modelado (instrução do dono do projeto, item 5/6):
--   OS em execução -> necessidade identificada -> adicional criado (cabeçalho,
--   motivo) -> item(ns) incluído(s) com preço -> decisão por item (aprovado/
--   parcialmente aprovado/rejeitado) -> só item aprovado é executável/cobrável.
--
-- Split de responsabilidade (BR-010, "preço é definido/autorizado pelo
-- encarregado" + instrução item 13):
--   - identificar necessidade (abrir o cabeçalho do adicional, com motivo):
--     executor, encarregado, administrador_tecnico.
--   - incluir item com preço (precificar): encarregado, administrador_tecnico
--     — executor NUNCA define/altera preço, nem do adicional.
--   - decidir item (registrar decisão do cliente, com meio estruturado —
--     mesmo padrão APR-004/005/006): encarregado, suporte_administrativo,
--     administrador_tecnico — mesma união de perfis que já registrava
--     autorização/aprovação de orçamento no P1-A/Fase 2. Executor nunca
--     aprova (instrução item 13, explícito).
create table os_adicionais (
  id uuid primary key default gen_random_uuid(),
  os_id uuid not null references ordens_servico(id),
  numero int not null,
  motivo text not null,
  status text not null default 'aguardando_aprovacao'
    constraint os_adicionais_status_check check (status in ('aguardando_aprovacao', 'aprovado', 'parcialmente_aprovado', 'rejeitado')),
  idempotency_key uuid,
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now(),
  unique (os_id, numero)
);

create index idx_os_adicionais_os on os_adicionais (os_id);
-- ADC-008: dupla criação por clique/retry com a mesma chave nunca duplica.
create unique index ux_os_adicionais_idempotency on os_adicionais (os_id, idempotency_key) where idempotency_key is not null;

create table os_adicional_itens (
  id uuid primary key default gen_random_uuid(),
  adicional_id uuid not null references os_adicionais(id) on delete cascade,
  peca_id uuid references pecas(id), -- null = item de mão de obra
  descricao text not null,
  quantidade numeric(10,3) not null check (quantidade > 0),
  valor_unitario numeric(12,2) not null check (valor_unitario >= 0),
  valor_total numeric(12,2) generated always as (quantidade * valor_unitario) stored,
  justificativa text,
  status_aprovacao text not null default 'pendente'
    constraint os_adicional_itens_status_aprovacao_check check (status_aprovacao in ('pendente', 'aprovado', 'rejeitado')),
  meio_aprovacao text
    constraint os_adicional_itens_meio_aprovacao_check check (meio_aprovacao in ('sistema', 'email', 'verbal_documentado')),
  autorizado_por_nome text,
  autorizado_em timestamptz,
  registrado_por uuid references profiles(id),
  comprovante_path text,
  observacao text,
  execucao_status text not null default 'pendente'
    constraint os_adicional_itens_execucao_status_check check (execucao_status in ('pendente', 'parcial', 'executado', 'cancelado')),
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_os_adicional_itens_adicional on os_adicional_itens (adicional_id);
create index idx_os_adicional_itens_status_aprovacao on os_adicional_itens (status_aprovacao);

-- ============================================================
-- estoque_movimentos: baixa de peça de item ADICIONAL aponta para o item
-- adicional (não para orcamento_item_id) — origem sempre identificável
-- (instrução item 8). Um movimento nunca referencia os dois ao mesmo tempo.
-- ============================================================
alter table estoque_movimentos add column if not exists os_adicional_item_id uuid references os_adicional_itens(id);
create index if not exists idx_estoque_mov_os_adicional_item on estoque_movimentos (os_adicional_item_id);
alter table estoque_movimentos add constraint estoque_mov_nao_mistura_origem_item
  check (not (orcamento_item_id is not null and os_adicional_item_id is not null));

-- ============================================================
-- RLS
-- ============================================================
alter table os_adicionais enable row level security;
alter table os_adicional_itens enable row level security;

create policy "os_adicionais_select_autenticado" on os_adicionais
  for select using (current_user_ativo());
create policy "os_adicional_itens_select_autenticado" on os_adicional_itens
  for select using (current_user_ativo());

-- Escrita exclusivamente via RPC (SECURITY DEFINER) abaixo — mesmo padrão de
-- orcamentos/ordens_servico/os_garantia_itens.
revoke insert, update, delete on os_adicionais from authenticated;
revoke insert, update, delete on os_adicional_itens from authenticated;

-- ============================================================
-- Recalcula os_adicionais.status a partir dos itens — mesma máquina de
-- estados do orçamento (item 2), aplicada ao adicional:
--   algum item pendente          -> 'aguardando_aprovacao'
--   todos aprovados              -> 'aprovado'
--   todos rejeitados             -> 'rejeitado'
--   mistura aprovado+rejeitado   -> 'parcialmente_aprovado'
-- ============================================================
create or replace function recalcular_status_os_adicional(p_adicional_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
  v_pendentes int;
  v_aprovados int;
  v_rejeitados int;
  v_novo text;
begin
  perform 1 from os_adicionais where id = p_adicional_id for update;

  select count(*),
         count(*) filter (where status_aprovacao = 'pendente'),
         count(*) filter (where status_aprovacao = 'aprovado'),
         count(*) filter (where status_aprovacao = 'rejeitado')
    into v_total, v_pendentes, v_aprovados, v_rejeitados
    from os_adicional_itens where adicional_id = p_adicional_id;

  if v_total = 0 or v_pendentes > 0 then
    v_novo := 'aguardando_aprovacao';
  elsif v_aprovados = v_total then
    v_novo := 'aprovado';
  elsif v_rejeitados = v_total then
    v_novo := 'rejeitado';
  else
    v_novo := 'parcialmente_aprovado';
  end if;

  update os_adicionais set status = v_novo where id = p_adicional_id and status is distinct from v_novo;
end;
$$;

revoke execute on function recalcular_status_os_adicional(uuid) from public, anon, authenticated;

-- ============================================================
-- ADC-001/ADC-008: cria o cabeçalho do adicional (identificação da
-- necessidade). Numeração sequencial por OS (AD-001, AD-002, ...), atribuída
-- sob o lock de ordens_servico (FOR UPDATE), o que também serializa criações
-- concorrentes da mesma OS — sem isso, dois adicionais concorrentes
-- poderiam colidir no mesmo número. idempotency_key opcional protege contra
-- duplo clique/retry de rede na própria criação.
-- ============================================================
create or replace function rpc_criar_os_adicional(
  p_os_id uuid,
  p_motivo text,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status status_os;
  v_numero int;
  v_novo_id uuid;
  v_existente uuid;
begin
  if not tem_perfil('executor', 'encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para identificar necessidade de adicional';
  end if;

  if p_motivo is null or length(trim(p_motivo)) < 5 then
    raise exception 'Motivo do adicional é obrigatório (mínimo de 5 caracteres)';
  end if;

  select status into v_status from ordens_servico where id = p_os_id for update;
  if v_status is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — não é possível abrir adicional';
  end if;

  if p_idempotency_key is not null then
    select id into v_existente from os_adicionais where os_id = p_os_id and idempotency_key = p_idempotency_key;
    if v_existente is not null then
      return v_existente; -- ADC-008: retry idempotente devolve o mesmo adicional já criado
    end if;
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero from os_adicionais where os_id = p_os_id;

  insert into os_adicionais (os_id, numero, motivo, idempotency_key, criado_por)
  values (p_os_id, v_numero, p_motivo, p_idempotency_key, auth.uid())
  returning id into v_novo_id;

  perform registrar_auditoria('os_adicionais', v_novo_id, 'criar_adicional', null,
    jsonb_build_object('os_id', p_os_id, 'numero', v_numero, 'motivo', p_motivo), null);

  return v_novo_id;
end;
$$;

-- ============================================================
-- ADC-001 (item)/ADC-005 (imutabilidade pós-decisão): inclui item precificado
-- no adicional. Só permitido enquanto NENHUM item do adicional já foi
-- decidido — alterar valor/quantidade depois de decidido exige um adicional
-- NOVO (novo ciclo de aprovação), nunca edição do item existente (não existe
-- RPC de UPDATE de item de adicional, e a RLS não concede UPDATE direto —
-- ver revoke acima).
-- ============================================================
create or replace function rpc_incluir_item_os_adicional(
  p_adicional_id uuid,
  p_peca_id uuid,
  p_descricao text,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_justificativa text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adicional record;
  v_os_status status_os;
  v_tem_decidido boolean;
  v_novo_id uuid;
begin
  if not tem_perfil('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para precificar/incluir item de adicional';
  end if;

  if p_descricao is null or length(trim(p_descricao)) < 2 then
    raise exception 'Descrição do item é obrigatória';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade deve ser positiva';
  end if;
  if p_valor_unitario is null or p_valor_unitario < 0 then
    raise exception 'Valor unitário inválido';
  end if;

  select a.id, a.os_id, a.status into v_adicional from os_adicionais a where a.id = p_adicional_id for update;
  if v_adicional.id is null then
    raise exception 'Adicional não encontrado';
  end if;

  select status into v_os_status from ordens_servico where id = v_adicional.os_id;
  if v_os_status in ('concluida', 'liberada', 'cancelada') then
    raise exception 'OS já encerrada — não é possível incluir item de adicional';
  end if;

  select exists (
    select 1 from os_adicional_itens where adicional_id = p_adicional_id and status_aprovacao <> 'pendente'
  ) into v_tem_decidido;
  if v_tem_decidido then
    raise exception 'Este adicional já tem item decidido — inclusão de novo item bloqueada; abra um novo adicional (rpc_criar_os_adicional) para itens adicionais depois da decisão';
  end if;

  if p_peca_id is not null then
    if not exists (select 1 from pecas where id = p_peca_id) then
      raise exception 'Peça não encontrada';
    end if;
  end if;

  insert into os_adicional_itens (adicional_id, peca_id, descricao, quantidade, valor_unitario, justificativa, criado_por)
  values (p_adicional_id, p_peca_id, p_descricao, p_quantidade, p_valor_unitario, p_justificativa, auth.uid())
  returning id into v_novo_id;

  perform registrar_auditoria('os_adicional_itens', v_novo_id, 'incluir_item_adicional', null,
    jsonb_build_object('adicional_id', p_adicional_id, 'descricao', p_descricao, 'quantidade', p_quantidade, 'valor_unitario', p_valor_unitario), p_justificativa);

  perform recalcular_status_os_adicional(p_adicional_id);

  return v_novo_id;
end;
$$;

-- ============================================================
-- ADC-003/ADC-004: decisão POR ITEM do adicional, com meio estruturado
-- (mesmo padrão APR-004/005/006 do orçamento). Idempotente para retry
-- (cenário M) e bloqueia decisão conflitante concorrente (cenário N) —
-- mesmo desenho de rpc_decidir_item_orcamento.
-- ============================================================
create or replace function rpc_decidir_item_os_adicional(
  p_item_id uuid,
  p_decisao text,
  p_meio_aprovacao text,
  p_autorizado_por_nome text,
  p_comprovante_path text default null,
  p_observacao text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
begin
  if not tem_perfil('encarregado', 'suporte_administrativo', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para registrar decisão de item de adicional';
  end if;

  if p_decisao not in ('aprovado', 'rejeitado') then
    raise exception 'Decisão inválida: % (use aprovado ou rejeitado)', p_decisao;
  end if;
  if p_meio_aprovacao not in ('sistema', 'email', 'verbal_documentado') then
    raise exception 'Meio de aprovação inválido: % (use sistema, email ou verbal_documentado)', p_meio_aprovacao;
  end if;
  if p_autorizado_por_nome is null or length(trim(p_autorizado_por_nome)) < 2 then
    raise exception 'Nome de quem autorizou (cliente/responsável) é obrigatório';
  end if;
  if p_meio_aprovacao = 'email' then
    if p_comprovante_path is null or trim(p_comprovante_path) = '' then
      raise exception 'Aprovação via e-mail exige evidência (comprovante_path) — DOC-005';
    end if;
    if not storage_objeto_existe('comprovantes', p_comprovante_path) then
      raise exception 'Comprovante informado não foi encontrado no Storage (bucket comprovantes, path %) — envie o arquivo antes de registrar a decisão', p_comprovante_path;
    end if;
  end if;
  if p_meio_aprovacao = 'verbal_documentado' and (p_observacao is null or length(trim(p_observacao)) < 10) then
    raise exception 'Aprovação verbal documentada exige observação com detalhe suficiente para rastreabilidade (mínimo de 10 caracteres)';
  end if;

  select oai.id, oai.adicional_id, oai.status_aprovacao into v_item
    from os_adicional_itens oai where oai.id = p_item_id for update;
  if v_item.id is null then
    raise exception 'Item de adicional não encontrado';
  end if;

  if v_item.status_aprovacao = p_decisao then
    return; -- ADC-008/cenário M: retry idempotente
  end if;

  if v_item.status_aprovacao <> 'pendente' then
    raise exception 'Item de adicional já decidido anteriormente (%) — decisão não pode ser revertida/trocada', v_item.status_aprovacao;
  end if;

  update os_adicional_itens
    set status_aprovacao = p_decisao,
        meio_aprovacao = p_meio_aprovacao,
        autorizado_por_nome = p_autorizado_por_nome,
        autorizado_em = now(),
        registrado_por = auth.uid(),
        comprovante_path = p_comprovante_path,
        observacao = p_observacao
    where id = p_item_id;

  perform registrar_auditoria('os_adicional_itens', p_item_id, 'decisao_item_adicional',
    jsonb_build_object('status_aprovacao', 'pendente'),
    jsonb_build_object('status_aprovacao', p_decisao, 'meio_aprovacao', p_meio_aprovacao, 'autorizado_por_nome', p_autorizado_por_nome),
    p_observacao);

  perform recalcular_status_os_adicional(v_item.adicional_id);
end;
$$;
