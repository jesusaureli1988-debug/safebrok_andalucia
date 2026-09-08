-- SafeBrok · administración segura de usuarios y accesos.
begin;
create table if not exists public.usuarios_accesos_auditoria(
 id bigint generated always as identity primary key,
 actor_usuario_id uuid not null references public.usuarios(id),
 objetivo_usuario_id uuid references public.usuarios(id),
 objetivo_email text,
 accion text not null check(accion in('create','update_assignment','deactivate','reactivate','resend_access')),
 detalle jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists usuarios_accesos_auditoria_created_idx on public.usuarios_accesos_auditoria(created_at desc);

create or replace function public.usuario_rol_normalizado(v text) returns text
language sql immutable set search_path='' as $$
 select lower(trim(replace(replace(coalesce(v,''),'-','_'),' ','_')))
$$;
create or replace function public.usuario_responsable_valido(p_rol text,p_parent_id uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare permitidos text[];rol_padre text;estado_padre text;
begin
 permitidos:=case public.usuario_rol_normalizado(p_rol)
  when 'director_nacional' then array[]::text[]
  when 'director_zona' then array['director_nacional']
  when 'jefe_ventas' then array['director_zona','director_nacional']
  when 'jefe_equipo' then array['jefe_ventas','director_zona','director_nacional']
  when 'agente' then array['jefe_equipo','jefe_ventas','director_zona','director_nacional']
  else null end;
 if permitidos is null then return false; end if;
 if cardinality(permitidos)=0 then return p_parent_id is null; end if;
 if p_parent_id is null then return false; end if;
 select public.usuario_rol_normalizado(rol_usuario),public.usuario_rol_normalizado(coalesce(estado,'activo'))
 into rol_padre,estado_padre from public.usuarios where id=p_parent_id;
 return rol_padre=any(permitidos) and estado_padre not in('bloqueado','inactivo','desactivado');
end $$;
create or replace function public.usuario_validar_jerarquia() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 new.rol_usuario:=public.usuario_rol_normalizado(new.rol_usuario);
 if not public.usuario_responsable_valido(new.rol_usuario,new.parent_id) then
  raise exception 'Relación rol/responsable no válida';
 end if;
 if new.parent_id=new.id then raise exception 'Un usuario no puede depender de sí mismo'; end if;
 if exists(
  with recursive descendientes as(
   select id,parent_id from public.usuarios where parent_id=new.id
   union all select u.id,u.parent_id from public.usuarios u join descendientes d on u.parent_id=d.id
  ) select 1 from descendientes where id=new.parent_id
 ) then raise exception 'La asignación generaría un ciclo jerárquico'; end if;
 return new;
end $$;
drop trigger if exists usuario_validar_jerarquia_trg on public.usuarios;
create trigger usuario_validar_jerarquia_trg before insert or update of rol_usuario,parent_id
on public.usuarios for each row execute function public.usuario_validar_jerarquia();

alter table public.usuarios_accesos_auditoria enable row level security;
drop policy if exists usuarios_accesos_auditoria_select on public.usuarios_accesos_auditoria;
create policy usuarios_accesos_auditoria_select on public.usuarios_accesos_auditoria
for select to authenticated using(public.app_can_manage_global());
revoke all on public.usuarios_accesos_auditoria from public,anon,authenticated;
grant select on public.usuarios_accesos_auditoria to authenticated;
revoke all on function public.usuario_responsable_valido(text,uuid) from public,anon;
grant execute on function public.usuario_responsable_valido(text,uuid) to authenticated;
commit;
