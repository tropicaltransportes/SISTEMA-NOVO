-- Fase 2: solicitações de serviço (porta de entrada antes de orçamento/OS)

create type status_solicitacao as enum ('aberta', 'em_analise', 'convertida_orcamento', 'convertida_os', 'cancelada');

create table solicitacoes_servico (
  id uuid primary key default gen_random_uuid(),
  veiculo_id uuid not null references veiculos(id),
  descricao text not null,
  status status_solicitacao not null default 'aberta',
  criado_por uuid not null references profiles(id),
  criado_em timestamptz not null default now()
);

create index idx_solicitacoes_veiculo on solicitacoes_servico (veiculo_id);
create index idx_solicitacoes_status on solicitacoes_servico (status);

alter table solicitacoes_servico enable row level security;

create policy "solicitacoes_select_autenticado" on solicitacoes_servico
  for select
  using (auth.uid() is not null);

-- Qualquer perfil operacional pode abrir uma solicitação (executor, encarregado,
-- suporte administrativo); diretoria é somente-leitura em todo o módulo.
create policy "solicitacoes_insert_operacional" on solicitacoes_servico
  for insert
  with check (
    current_perfil() in ('executor', 'encarregado', 'suporte_administrativo', 'administrador_tecnico')
    and criado_por = auth.uid()
    and status = 'aberta'
  );

-- Edição de descrição/status restrita a encarregado/suporte administrativo, e só
-- enquanto a solicitação não foi convertida (conversão é feita por trigger a partir
-- de orçamento/OS, nunca por UPDATE direto do cliente nesses dois status).
create policy "solicitacoes_update_gestao" on solicitacoes_servico
  for update
  using (
    current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico')
    and status in ('aberta', 'em_analise')
  )
  with check (
    current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico')
    and status in ('aberta', 'em_analise')
  );

revoke update on solicitacoes_servico from authenticated;
grant update (descricao, status) on solicitacoes_servico to authenticated;

-- Helper reaproveitado pelas migrations seguintes (orçamentos/OS) para marcar a
-- solicitação de origem como convertida, sem exigir policy de UPDATE adicional
-- para quem cria orçamento/OS (roda como dono da função).
create or replace function marcar_solicitacao_convertida(p_solicitacao_id uuid, p_novo_status status_solicitacao)
returns void
language sql
security definer
set search_path = public
as $$
  update solicitacoes_servico
    set status = p_novo_status
    where id = p_solicitacao_id and status in ('aberta', 'em_analise');
$$;
