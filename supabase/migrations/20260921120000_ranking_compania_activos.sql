-- Lectura mínima para rankings de compañía autorizada por el propietario.
-- No devuelve correo, teléfono, documentación ni datos de acceso.
create or replace function public.app_ranking_usuarios_activos()
returns table (
  id uuid,
  auth_id uuid,
  nombre text,
  apellidos text,
  rol_usuario text,
  parent_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.auth_id, u.nombre, u.apellidos, u.rol_usuario, u.parent_id
  from public.usuarios as u
  where auth.uid() is not null
    and u.auth_id is not null
    and lower(btrim(coalesce(u.estado, 'activo'))) not in
      ('baja', 'inactivo', 'inactiva', 'bloqueado', 'bloqueada',
       'desactivado', 'desactivada', 'suspendido', 'suspendida')
$$;

revoke all on function public.app_ranking_usuarios_activos() from public, anon;
grant execute on function public.app_ranking_usuarios_activos() to authenticated;
comment on function public.app_ranking_usuarios_activos() is
  'Censo mínimo de usuarios activos para rankings globales, sin datos de contacto.';