-- SafeBrok: cierre integral de RLS y aislamiento de App Review.
-- Diseñado contra el esquema remoto ytmxjavihwylrswphczc auditado el 2026-08-10.
-- Ejecutar como una única transacción. No crea usuarios Auth ni datos.

begin;

alter table public.usuarios
  add column if not exists es_cuenta_revision boolean not null default false,
  add column if not exists es_dato_revision boolean not null default false;

create index if not exists idx_usuarios_revision
  on public.usuarios (es_cuenta_revision, es_dato_revision, auth_id);

create or replace function public.app_current_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select lower(trim(replace(coalesce(u.rol_usuario, ''), '-', '_')))
  from public.usuarios u
  where u.auth_id = auth.uid()
  limit 1
$$;

create or replace function public.app_is_review_account()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select u.es_cuenta_revision
    from public.usuarios u
    where u.auth_id = auth.uid()
    limit 1
  ), false)
$$;

create or replace function public.app_can_manage_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not public.app_is_review_account()
    and public.app_current_role() in ('director_nacional', 'administracion')
$$;

create or replace function public.app_can_access_auth_id(target_auth_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  requester_id uuid;
  requester_role text;
  requester_is_review boolean;
begin
  if auth.uid() is null or nullif(trim(target_auth_id), '') is null then
    return false;
  end if;

  if target_auth_id = auth.uid()::text then
    return true;
  end if;

  select u.id,
         lower(trim(replace(coalesce(u.rol_usuario, ''), '-', '_'))),
         u.es_cuenta_revision
  into requester_id, requester_role, requester_is_review
  from public.usuarios u
  where u.auth_id = auth.uid()
  limit 1;

  if requester_id is null then return false; end if;

  if requester_is_review then
    return exists (
      select 1 from public.usuarios u
      where u.auth_id::text = target_auth_id
        and (u.es_dato_revision or u.es_cuenta_revision)
    );
  end if;

  if requester_role in ('director_nacional', 'administracion') then
    return true;
  end if;

  return exists (
    with recursive estructura as (
      select u.id, u.auth_id
      from public.usuarios u
      where u.id = requester_id
      union all
      select child.id, child.auth_id
      from public.usuarios child
      join estructura parent on child.parent_id = parent.id
    )
    select 1 from estructura e where e.auth_id::text = target_auth_id
  );
end
$$;

create or replace function public.app_can_access_user_id(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios u
    where u.id = target_user_id
      and public.app_can_access_auth_id(u.auth_id::text)
  )
$$;

revoke all on function public.app_current_role() from public, anon;
revoke all on function public.app_is_review_account() from public, anon;
revoke all on function public.app_can_manage_global() from public, anon;
revoke all on function public.app_can_access_auth_id(text) from public, anon;
revoke all on function public.app_can_access_user_id(uuid) from public, anon;
grant execute on function public.app_current_role() to authenticated;
grant execute on function public.app_is_review_account() to authenticated;
grant execute on function public.app_can_manage_global() to authenticated;
grant execute on function public.app_can_access_auth_id(text) to authenticated;
grant execute on function public.app_can_access_user_id(uuid) to authenticated;

-- La app privada no necesita acceso PostgREST anónimo.
revoke all on all tables in schema public from anon;

-- Activa RLS en todas las tablas públicas que la auditoría encontró abiertas.
alter table public.actividad_agentes enable row level security;
alter table public.agenda_eventos enable row level security;
alter table public.alertas enable row level security;
alter table public.anulaciones_poliza enable row level security;
alter table public.app_versions enable row level security;
alter table public.candidatos_captacion enable row level security;
alter table public.chat_mensajes enable row level security;
alter table public.clientes enable row level security;
alter table public.comisiones_productos enable row level security;
alter table public.contactos_diarios_jefe_equipo enable row level security;
alter table public.detalle_nomina enable row level security;
alter table public.formacion_agentes enable row level security;
alter table public.gestiones_asignadas enable row level security;
alter table public.gestiones_poliza enable row level security;
alter table public.incidencias enable row level security;
alter table public.integracion_agentes enable row level security;
alter table public.nominas_facturas enable row level security;
alter table public.nominas_facturas_lineas enable row level security;
alter table public.nominas_mensuales enable row level security;
alter table public.planificacion_equipo enable row level security;
alter table public.planificacion_semanal_equipo enable row level security;
alter table public.profiles enable row level security;
alter table public.recibos enable row level security;
alter table public.recibos_comentarios enable row level security;
alter table public.recibos_pagos enable row level security;
alter table public.referencias_viables enable row level security;
alter table public.reuniones enable row level security;
alter table public.seguimiento_clientes enable row level security;
alter table public.usuarios enable row level security;
alter table public.ventas enable row level security;
alter table public.visitas enable row level security;

-- Perfiles y jerarquía.
drop policy if exists app_usuarios_select on public.usuarios;
create policy app_usuarios_select on public.usuarios for select to authenticated
using (public.app_can_access_auth_id(auth_id::text));
drop policy if exists app_usuarios_insert on public.usuarios;
create policy app_usuarios_insert on public.usuarios for insert to authenticated
with check (public.app_can_manage_global());
drop policy if exists app_usuarios_update on public.usuarios;
create policy app_usuarios_update on public.usuarios for update to authenticated
using (auth_id = auth.uid() or public.app_can_manage_global())
with check (auth_id = auth.uid() or public.app_can_manage_global());
drop policy if exists app_usuarios_delete on public.usuarios;
create policy app_usuarios_delete on public.usuarios for delete to authenticated
using (public.app_can_manage_global());

drop policy if exists app_profiles_select on public.profiles;
create policy app_profiles_select on public.profiles for select to authenticated
using (id = auth.uid() or public.app_can_manage_global());
drop policy if exists app_profiles_update on public.profiles;
create policy app_profiles_update on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

-- Registros con propietario Auth directo.
drop policy if exists app_actividad_all on public.actividad_agentes;
create policy app_actividad_all on public.actividad_agentes for all to authenticated
using (public.app_can_access_auth_id(auth_id))
with check (auth_id = auth.uid()::text);

drop policy if exists app_agenda_all on public.agenda_eventos;
create policy app_agenda_all on public.agenda_eventos for all to authenticated
using (public.app_can_access_auth_id(auth_id::text))
with check (public.app_can_access_auth_id(auth_id::text));

drop policy if exists app_clientes_all on public.clientes;
create policy app_clientes_all on public.clientes for all to authenticated
using (public.app_can_access_auth_id(auth_id::text))
with check (public.app_can_access_auth_id(auth_id::text));

drop policy if exists app_contactos_jefe_all on public.contactos_diarios_jefe_equipo;
create policy app_contactos_jefe_all on public.contactos_diarios_jefe_equipo for all to authenticated
using (public.app_can_access_auth_id(auth_id::text))
with check (public.app_can_access_auth_id(auth_id::text));

drop policy if exists app_incidencias_all on public.incidencias;
create policy app_incidencias_all on public.incidencias for all to authenticated
using (public.app_can_access_auth_id(auth_id))
with check (public.app_can_access_auth_id(auth_id));

drop policy if exists app_referencias_all on public.referencias_viables;
create policy app_referencias_all on public.referencias_viables for all to authenticated
using (public.app_can_access_auth_id(auth_id))
with check (public.app_can_access_auth_id(auth_id));

drop policy if exists app_seguimiento_all on public.seguimiento_clientes;
create policy app_seguimiento_all on public.seguimiento_clientes for all to authenticated
using (public.app_can_access_auth_id(auth_id))
with check (public.app_can_access_auth_id(auth_id));

drop policy if exists app_visitas_all on public.visitas;
create policy app_visitas_all on public.visitas for all to authenticated
using (public.app_can_access_auth_id(auth_id::text))
with check (public.app_can_access_auth_id(auth_id::text));

drop policy if exists app_ventas_all on public.ventas;
create policy app_ventas_all on public.ventas for all to authenticated
using (public.app_can_access_auth_id(agente_auth_id::text))
with check (public.app_can_access_auth_id(agente_auth_id::text));

-- Comunicación y avisos.
drop policy if exists app_chat_select on public.chat_mensajes;
create policy app_chat_select on public.chat_mensajes for select to authenticated
using (sender_auth_id = auth.uid()::text or receiver_auth_id = auth.uid()::text);
drop policy if exists app_chat_insert on public.chat_mensajes;
create policy app_chat_insert on public.chat_mensajes for insert to authenticated
with check (sender_auth_id = auth.uid()::text
  and public.app_can_access_auth_id(receiver_auth_id));
drop policy if exists app_chat_update on public.chat_mensajes;
create policy app_chat_update on public.chat_mensajes for update to authenticated
using (receiver_auth_id = auth.uid()::text)
with check (receiver_auth_id = auth.uid()::text);

drop policy if exists app_alertas_select on public.alertas;
create policy app_alertas_select on public.alertas for select to authenticated
using (auth_id_destino = auth.uid() or auth_id_origen = auth.uid());
drop policy if exists app_alertas_insert on public.alertas;
create policy app_alertas_insert on public.alertas for insert to authenticated
with check (auth_id_origen = auth.uid()
  and public.app_can_access_auth_id(auth_id_destino::text));
drop policy if exists app_alertas_update on public.alertas;
create policy app_alertas_update on public.alertas for update to authenticated
using (auth_id_destino = auth.uid()) with check (auth_id_destino = auth.uid());

drop policy if exists app_gestiones_asignadas_select on public.gestiones_asignadas;
create policy app_gestiones_asignadas_select on public.gestiones_asignadas for select to authenticated
using (asignado_a_auth_id = auth.uid()::text
  or asignado_por_auth_id = auth.uid()::text
  or reportada_por_auth_id = auth.uid()::text);
drop policy if exists app_gestiones_asignadas_insert on public.gestiones_asignadas;
create policy app_gestiones_asignadas_insert on public.gestiones_asignadas for insert to authenticated
with check (asignado_por_auth_id = auth.uid()::text
  and public.app_can_access_auth_id(asignado_a_auth_id));
drop policy if exists app_gestiones_asignadas_update on public.gestiones_asignadas;
create policy app_gestiones_asignadas_update on public.gestiones_asignadas for update to authenticated
using (asignado_a_auth_id = auth.uid()::text or asignado_por_auth_id = auth.uid()::text)
with check (asignado_a_auth_id = auth.uid()::text or asignado_por_auth_id = auth.uid()::text);

drop policy if exists app_reuniones_select on public.reuniones;
create policy app_reuniones_select on public.reuniones for select to authenticated
using (creador_auth_id = auth.uid()::text
  or invitados ? auth.uid()::text
  or invitados @> jsonb_build_array(auth.uid()::text));
drop policy if exists app_reuniones_insert on public.reuniones;
create policy app_reuniones_insert on public.reuniones for insert to authenticated
with check (creador_auth_id = auth.uid()::text);
drop policy if exists app_reuniones_update_delete on public.reuniones;
create policy app_reuniones_update_delete on public.reuniones for all to authenticated
using (creador_auth_id = auth.uid()::text)
with check (creador_auth_id = auth.uid()::text);

-- Formación, integración y planificación enlazadas a usuarios.id.
drop policy if exists app_formacion_all on public.formacion_agentes;
create policy app_formacion_all on public.formacion_agentes for all to authenticated
using (public.app_can_access_user_id(agente_id))
with check (public.app_can_access_user_id(agente_id));
drop policy if exists app_integracion_all on public.integracion_agentes;
create policy app_integracion_all on public.integracion_agentes for all to authenticated
using (public.app_can_access_user_id(agente_id))
with check (public.app_can_access_user_id(agente_id));
drop policy if exists app_planificacion_all on public.planificacion_equipo;
create policy app_planificacion_all on public.planificacion_equipo for all to authenticated
using (public.app_can_access_user_id(agente_id) or public.app_can_access_user_id(jefe_id))
with check (public.app_can_access_user_id(agente_id) or public.app_can_access_user_id(jefe_id));
drop policy if exists app_planificacion_semanal_all on public.planificacion_semanal_equipo;
create policy app_planificacion_semanal_all on public.planificacion_semanal_equipo for all to authenticated
using (public.app_can_access_user_id(agente_id) or public.app_can_access_user_id(jefe_id))
with check (public.app_can_access_user_id(agente_id) or public.app_can_access_user_id(jefe_id));

-- Captación: creador o persona asignada dentro del alcance.
drop policy if exists app_candidatos_all on public.candidatos_captacion;
create policy app_candidatos_all on public.candidatos_captacion for all to authenticated
using (public.app_can_access_auth_id(auth_id::text)
  or public.app_can_access_auth_id(asignado_auth_id::text))
with check (public.app_can_access_auth_id(auth_id::text)
  or public.app_can_access_auth_id(asignado_auth_id::text));

-- Pólizas, recibos y gestiones derivadas.
drop policy if exists app_anulaciones_select on public.anulaciones_poliza;
create policy app_anulaciones_select on public.anulaciones_poliza for select to authenticated
using (exists (select 1 from public.ventas v where v.id = venta_id
  and public.app_can_access_auth_id(v.agente_auth_id::text)));
drop policy if exists app_anulaciones_write on public.anulaciones_poliza;
create policy app_anulaciones_write on public.anulaciones_poliza for all to authenticated
using (exists (select 1 from public.ventas v where v.id = venta_id
  and public.app_can_access_auth_id(v.agente_auth_id::text)))
with check (exists (select 1 from public.ventas v where v.id = venta_id
  and public.app_can_access_auth_id(v.agente_auth_id::text)));

drop policy if exists app_gestiones_poliza_all on public.gestiones_poliza;
create policy app_gestiones_poliza_all on public.gestiones_poliza for all to authenticated
using (exists (select 1 from public.ventas v where v.id = venta_id
  and public.app_can_access_auth_id(v.agente_auth_id::text)))
with check (exists (select 1 from public.ventas v where v.id = venta_id
  and public.app_can_access_auth_id(v.agente_auth_id::text)));

drop policy if exists app_recibos_all on public.recibos;
create policy app_recibos_all on public.recibos for all to authenticated
using (public.app_can_access_auth_id(agente))
with check (public.app_can_access_auth_id(agente));
drop policy if exists app_recibos_comentarios_all on public.recibos_comentarios;
create policy app_recibos_comentarios_all on public.recibos_comentarios for all to authenticated
using (exists (select 1 from public.recibos r where r.poliza = recibos_comentarios.poliza
  and public.app_can_access_auth_id(r.agente)))
with check (exists (select 1 from public.recibos r where r.poliza = recibos_comentarios.poliza
  and public.app_can_access_auth_id(r.agente)));
drop policy if exists app_recibos_pagos_all on public.recibos_pagos;
create policy app_recibos_pagos_all on public.recibos_pagos for all to authenticated
using (exists (select 1 from public.recibos r where r.poliza = recibos_pagos.poliza
  and public.app_can_access_auth_id(r.agente)))
with check (exists (select 1 from public.recibos r where r.poliza = recibos_pagos.poliza
  and public.app_can_access_auth_id(r.agente)));

-- Nóminas y facturas: usuario propio/estructura. Las líneas heredan la factura.
drop policy if exists app_nominas_all on public.nominas_mensuales;
create policy app_nominas_all on public.nominas_mensuales for all to authenticated
using (public.app_can_access_auth_id(auth_id))
with check (public.app_can_access_auth_id(auth_id));
drop policy if exists app_detalle_nomina_all on public.detalle_nomina;
create policy app_detalle_nomina_all on public.detalle_nomina for all to authenticated
using (exists (select 1 from public.nominas_mensuales n where n.id = nomina_id
  and public.app_can_access_auth_id(n.auth_id)))
with check (exists (select 1 from public.nominas_mensuales n where n.id = nomina_id
  and public.app_can_access_auth_id(n.auth_id)));
drop policy if exists app_nominas_facturas_all on public.nominas_facturas;
create policy app_nominas_facturas_all on public.nominas_facturas for all to authenticated
using (public.app_can_access_auth_id(usuario_auth_id))
with check (public.app_can_access_auth_id(usuario_auth_id));
drop policy if exists app_nominas_lineas_all on public.nominas_facturas_lineas;
create policy app_nominas_lineas_all on public.nominas_facturas_lineas for all to authenticated
using (exists (select 1 from public.nominas_facturas f where f.id = factura_id
  and public.app_can_access_auth_id(f.usuario_auth_id)))
with check (exists (select 1 from public.nominas_facturas f where f.id = factura_id
  and public.app_can_access_auth_id(f.usuario_auth_id)));

-- Catálogos globales: lectura autenticada; escritura solo dirección real.
drop policy if exists app_versions_read on public.app_versions;
create policy app_versions_read on public.app_versions for select to authenticated using (true);
drop policy if exists app_versions_manage on public.app_versions;
create policy app_versions_manage on public.app_versions for all to authenticated
using (public.app_can_manage_global()) with check (public.app_can_manage_global());
drop policy if exists app_comisiones_productos_read on public.comisiones_productos;
create policy app_comisiones_productos_read on public.comisiones_productos for select to authenticated using (true);
drop policy if exists app_comisiones_productos_manage on public.comisiones_productos;
create policy app_comisiones_productos_manage on public.comisiones_productos for all to authenticated
using (public.app_can_manage_global()) with check (public.app_can_manage_global());
drop policy if exists app_comisiones_compania_read on public.comisiones_producto_compania;
create policy app_comisiones_compania_read on public.comisiones_producto_compania for select to authenticated using (true);
drop policy if exists app_comisiones_compania_manage on public.comisiones_producto_compania;
create policy app_comisiones_compania_manage on public.comisiones_producto_compania for all to authenticated
using (public.app_can_manage_global()) with check (public.app_can_manage_global());

-- Tablas internas de cron: solo service_role (que omite RLS).
alter table public.avisos_push_programados enable row level security;
alter table public.notificaciones_objetivos_enviadas enable row level security;

-- La cuenta de revisión puede recibir sus propios hitos sin leer los de producción.
drop policy if exists app_objetivos_enviados_select on public.notificaciones_objetivos_enviadas;
create policy app_objetivos_enviados_select on public.notificaciones_objetivos_enviadas
for select to authenticated using (auth_id = auth.uid());

commit;
