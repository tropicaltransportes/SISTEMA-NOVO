-- Fase 1: identidade e perfis
create extension if not exists pgcrypto;

create type perfil_usuario as enum (
  'executor',
  'encarregado',
  'suporte_administrativo',
  'diretoria',
  'administrador_tecnico'
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  perfil perfil_usuario not null default 'executor',
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

-- Helper usado por todas as políticas RLS do projeto: evita repetir a
-- subconsulta EXISTS em profiles em cada policy. SECURITY DEFINER para
-- poder ler profiles independente das políticas de profiles em si.
create or replace function current_perfil()
returns perfil_usuario
language sql
stable
security definer
set search_path = public
as $$
  select perfil from profiles where id = auth.uid()
$$;

-- Auto-cria a linha em profiles quando um usuário é convidado/criado no Auth.
-- Perfil padrão 'executor'; administrador_tecnico ajusta o perfil correto depois.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, nome, perfil)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', new.email), 'executor');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

alter table profiles enable row level security;

-- SELECT: qualquer usuário autenticado pode ler o diretório de perfis
-- (necessário para exibir "executor responsável", atribuições etc.)
create policy "profiles_select_autenticado" on profiles
  for select
  using (auth.uid() is not null);

-- UPDATE: cada usuário só edita o próprio nome; perfil (role) só é alterado
-- por administrador_tecnico.
create policy "profiles_update_proprio_nome" on profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid() and perfil = current_perfil());

create policy "profiles_update_admin" on profiles
  for update
  using (current_perfil() = 'administrador_tecnico')
  with check (current_perfil() = 'administrador_tecnico');

-- Nenhuma policy de INSERT/DELETE direto: criação só via trigger de signup,
-- exclusão de usuário é feita via Supabase Auth (cascade cuida do profiles).
