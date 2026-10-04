-- Refuerza la exclusión de cualquier variante descriptiva de estados no activos.
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
        and lower(btrim(coalesce(u.estado, 'activo')))
          !~ '^(inactiv|baja|desactiv|bloquead|suspendid)'
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
    and lower(btrim(coalesce(u.estado, 'activo')))
      !~ '^(inactiv|baja|desactiv|bloquead|suspendid)'
  order by lower(coalesce(u.nombre, '')), lower(coalesce(u.apellidos, ''));
$$;

commit;