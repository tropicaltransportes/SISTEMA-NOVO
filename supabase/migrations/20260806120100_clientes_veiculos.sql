-- Fase 1: cadastro de clientes e veículos
create type tipo_cliente as enum ('interno', 'externo');

create table clientes (
  id uuid primary key default gen_random_uuid(),
  tipo tipo_cliente not null,
  nome text not null,
  documento text, -- CPF/CNPJ; null para o registro interno da frota própria
  telefone text,
  email text,
  deleted_at timestamptz
);

-- Registro único representando a própria Tropical Transportes (frota própria).
insert into clientes (tipo, nome, documento)
values ('interno', 'Tropical Transportes (Frota Própria)', null);

create table veiculos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  placa text not null,
  prefixo text,
  modelo text,
  ano int,
  deleted_at timestamptz,
  criado_em timestamptz not null default now()
);

create unique index uq_veiculos_placa_ativo on veiculos (placa) where deleted_at is null;
create index idx_veiculos_placa on veiculos (placa) where deleted_at is null;
create index idx_veiculos_prefixo on veiculos (prefixo) where deleted_at is null;
create index idx_veiculos_cliente on veiculos (cliente_id) where deleted_at is null;

alter table clientes enable row level security;
alter table veiculos enable row level security;

-- SELECT: todo usuário autenticado (dado interno de operação, não sensível)
create policy "clientes_select_autenticado" on clientes
  for select
  using (auth.uid() is not null);

create policy "veiculos_select_autenticado" on veiculos
  for select
  using (auth.uid() is not null);

-- INSERT/UPDATE: encarregado e suporte administrativo mantêm o cadastro
create policy "clientes_insert_cadastro" on clientes
  for insert
  with check (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'));

create policy "clientes_update_cadastro" on clientes
  for update
  using (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'))
  with check (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'));

create policy "veiculos_insert_cadastro" on veiculos
  for insert
  with check (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'));

create policy "veiculos_update_cadastro" on veiculos
  for update
  using (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'))
  with check (current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico'));

-- Sem policy de DELETE em nenhuma das duas tabelas: exclusão física é sempre
-- negada pelo RLS (soft delete via UPDATE de deleted_at é o único caminho).
