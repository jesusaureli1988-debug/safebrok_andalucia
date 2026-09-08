-- Permite asignar como responsable directo a cualquier figura de SafeBrok.
-- El trigger usuario_validar_jerarquia conserva la protección contra autorreferencias y ciclos.
begin;

create or replace function public.usuario_responsable_valido(
  p_rol text,
  p_parent_id uuid
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  rol_normalizado text;
begin
  rol_normalizado := public.usuario_rol_normalizado(p_rol);

  if rol_normalizado not in (
    'director_nacional',
    'director_zona',
    'jefe_ventas',
    'jefe_equipo',
    'agente',
    'administracion',
    'admin'
  ) then
    return false;
  end if;

  if p_parent_id is null then
    return true;
  end if;

  return exists (
    select 1
    from public.usuarios
    where id = p_parent_id
  );
end;
$$;

commit;