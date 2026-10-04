-- SafeBrok: chat global entre todos los usuarios activos.
-- Expone únicamente los datos mínimos del directorio y mantiene privados
-- los mensajes y archivos para sus dos participantes.
begin;

create or replace function public.chat_usuario_activo(target_auth_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and nullif(btrim(target_auth_id), '') is not null
    and exists (
      select 1
      from public.usuarios u
      where u.auth_id::text = btrim(target_auth_id)
        and lower(btrim(coalesce(u.estado, 'activo'))) not in (
          'inactivo', 'baja', 'desactivado', 'bloqueado', 'suspendido'
        )
    );
$$;

create or replace function public.chat_directorio_usuarios()
returns table (
  id uuid,
  nombre text,
  apellidos text,
  auth_id uuid,
  rol_usuario text
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.nombre::text, u.apellidos::text, u.auth_id, u.rol_usuario::text
  from public.usuarios u
  where auth.uid() is not null
    and u.auth_id is not null
    and u.auth_id <> auth.uid()
    and lower(btrim(coalesce(u.estado, 'activo'))) not in (
      'inactivo', 'baja', 'desactivado', 'bloqueado', 'suspendido'
    )
  order by lower(coalesce(u.nombre, '')), lower(coalesce(u.apellidos, ''));
$$;

revoke all on function public.chat_usuario_activo(text) from public, anon;
revoke all on function public.chat_directorio_usuarios() from public, anon;
grant execute on function public.chat_usuario_activo(text) to authenticated;
grant execute on function public.chat_directorio_usuarios() to authenticated;

drop policy if exists app_chat_insert on public.chat_mensajes;
create policy app_chat_insert on public.chat_mensajes
for insert to authenticated
with check (
  sender_auth_id = auth.uid()::text
  and receiver_auth_id <> auth.uid()::text
  and public.chat_usuario_activo(receiver_auth_id)
);

drop policy if exists app_chat_archivos_insert on storage.objects;
create policy app_chat_archivos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'chat-archivos'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] <> auth.uid()::text
  and public.chat_usuario_activo((storage.foldername(name))[2])
);

commit;