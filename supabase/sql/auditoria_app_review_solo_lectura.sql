-- SafeBrok / App Review: auditoría remota de solo lectura.
-- Ejecutar en Supabase SQL Editor. Este archivo no modifica nada.

-- 1. Tablas públicas sin RLS o sin políticas.
select
  n.nspname as esquema,
  c.relname as tabla,
  c.relrowsecurity as rls_activo,
  count(p.policyname) as numero_politicas
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p
  on p.schemaname = n.nspname and p.tablename = c.relname
where c.relkind in ('r', 'p')
  and n.nspname in ('public', 'storage')
group by n.nspname, c.relname, c.relrowsecurity
order by n.nspname, c.relname;

-- 2. Definición efectiva de todas las políticas.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

-- 3. Roles inválidos, variantes y perfiles sin identidad Auth.
select lower(trim(replace(rol_usuario, '-', '_'))) as rol_normalizado,
       count(*) as usuarios
from public.usuarios
group by 1
order by 1;

select u.id, u.auth_id, u.email, u.rol_usuario, u.estado
from public.usuarios u
left join auth.users a on a.id = u.auth_id
where a.id is null or u.auth_id is null;

select a.id, a.email, a.email_confirmed_at, a.banned_until,
       a.last_sign_in_at, a.raw_app_meta_data, a.raw_user_meta_data
from auth.users a
left join public.usuarios u on u.auth_id = a.id
where u.id is null;

-- 4. Funciones con SECURITY DEFINER y privilegios expuestos.
select
  n.nspname as esquema,
  p.proname as funcion,
  p.prosecdef as security_definer,
  pg_get_userbyid(p.proowner) as propietario,
  p.proacl as privilegios,
  pg_get_function_identity_arguments(p.oid) as argumentos
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;

-- 5. Buckets y políticas de Storage. Los buckets con public=true son públicos
-- aunque la tabla de metadatos tenga RLS.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
order by id;

select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by policyname;

-- 6. Tablas que la app usa pero que no existen en el esquema público.
with usadas(tabla) as (values
 ('actividad_agentes'), ('agenda_eventos'), ('agentes'), ('alertas'),
 ('anulaciones_poliza'), ('anulaciones_polizas'), ('app_versions'),
 ('candidatos_captacion'), ('chat_mensajes'), ('cierres_produccion'),
 ('clientes'), ('comisiones_aseguradoras'), ('comisiones_producto_compania'),
 ('comisiones_productos'), ('contactos_diarios'),
 ('contactos_diarios_jefe_equipo'), ('contactos_positivos_detalle'),
 ('cv_candidatos'), ('detalle_nomina'), ('dispositivos_push'), ('facturas'),
 ('formacion_agentes'), ('gestiones_asignadas'), ('gestiones_poliza'),
 ('historial_reasignaciones'), ('ia_conversaciones'), ('ia_mensajes'),
 ('incidencias'), ('informes_comerciales_generados'), ('integracion_agentes'),
 ('nominas_facturas'), ('nominas_facturas_lineas'), ('nominas_mensuales'),
 ('nominas_polizas_revision'), ('notificaciones'),
 ('objetivos_comerciales_anuales'), ('planificacion_equipo'),
 ('planificacion_semanal_equipo'), ('programaciones_informes_comerciales'),
 ('recibos'), ('recibos_comentarios'), ('recibos_pagos'),
 ('referencias_viables'), ('reuniones'), ('safecloud'), ('safecloud_items'),
 ('safecloud_shares'), ('seguimiento_clientes'), ('tareas'), ('usuarios'),
 ('ventas'), ('visitas')
)
select u.tabla
from usadas u
left join information_schema.tables t
  on t.table_schema = 'public' and t.table_name = u.tabla
where t.table_name is null
order by u.tabla;

-- 7. Comprobar límites de API y grants anónimos accidentales.
select table_schema, table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema in ('public', 'storage')
order by table_schema, table_name, privilege_type;
