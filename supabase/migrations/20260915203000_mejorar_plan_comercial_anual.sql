alter table public.objetivos_comerciales_anuales
  add column if not exists primas_decesos_vida numeric(14,2) not null default 0,
  add column if not exists anulaciones numeric(14,2) not null default 0,
  add column if not exists bi numeric(14,2) not null default 0;

update public.objetivos_comerciales_anuales
set anulaciones = coalesce(anulaciones_decesos, 0) + coalesce(anulaciones_resto, 0)
where anulaciones = 0
  and (coalesce(anulaciones_decesos, 0) <> 0 or coalesce(anulaciones_resto, 0) <> 0);

alter table public.objetivos_comerciales_anuales
  drop constraint if exists objetivos_comerciales_anuales_usuario_rol_check;

alter table public.objetivos_comerciales_anuales
  add constraint objetivos_comerciales_anuales_usuario_rol_check
  check (
    usuario_rol in (
      'agente',
      'jefe_equipo',
      'jefe_ventas',
      'director_zona',
      'director_nacional'
    )
  );

drop policy if exists "objetivos_anuales_lectura_figuras"
on public.objetivos_comerciales_anuales;

create policy "objetivos_anuales_lectura_figuras"
on public.objetivos_comerciales_anuales
for select
to authenticated
using (
  usuario_auth_id = auth.uid()
  or public.app_can_access_auth_id(usuario_auth_id::text)
);
