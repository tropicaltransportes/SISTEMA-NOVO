-- Helpers pgTAP para simular chamador anônimo / autenticado com um perfil
-- específico, sem depender de usuários reais no Auth. NÃO EXECUTADO nesta
-- auditoria (ver supabase/tests/README.md) — escrito seguindo a convenção
-- documentada do Supabase (`request.jwt.claims` + `role`), não verificado
-- neste ambiente por falta de Docker/instância local. Confirme o nome exato
-- da claim lida por `auth.uid()`/`auth.role()` no seu projeto antes de rodar
-- (varia conforme a versão do template `auth` do Supabase).

create schema if not exists tests;

-- Cria um usuário de teste em auth.users + profiles com o perfil desejado,
-- retornando o id gerado.
create or replace function tests.criar_usuario_teste(p_perfil perfil_usuario, p_nome text default 'Usuário Teste')
returns uuid
language plpgsql
security definer
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
  values (v_id, v_id || '@teste.local', crypt('senha-teste-123', gen_salt('bf')), now(), jsonb_build_object('nome', p_nome));
  -- handle_new_user já insere profiles com perfil 'executor'; ajusta para o perfil pedido.
  update profiles set perfil = p_perfil, nome = p_nome where id = v_id;
  return v_id;
end;
$$;

-- Assume a identidade de um usuário autenticado para o restante da transação/teste.
create or replace function tests.autenticar_como(p_user_id uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;

-- Volta para o papel anônimo (sem sessão nenhuma) — é este o caminho usado
-- para reproduzir o achado crítico desta auditoria (bypass de permissão).
create or replace function tests.autenticar_como_anon()
returns void
language sql
as $$
  select set_config('request.jwt.claims', '', true);
  select set_config('role', 'anon', true);
$$;
