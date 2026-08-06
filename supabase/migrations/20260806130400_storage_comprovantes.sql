-- Fase 2: bucket de Storage para comprovante de autorização de orçamento
-- (cliente externo). Privado — leitura/escrita só para usuário autenticado.

insert into storage.buckets (id, name, public)
values ('comprovantes', 'comprovantes', false)
on conflict (id) do nothing;

create policy "comprovantes_select_autenticado" on storage.objects
  for select
  to authenticated
  using (bucket_id = 'comprovantes');

create policy "comprovantes_upload_gestao" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'comprovantes'
    and current_perfil() in ('encarregado', 'suporte_administrativo', 'administrador_tecnico')
  );
