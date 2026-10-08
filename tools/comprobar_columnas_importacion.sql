-- SOLO LECTURA: ejecutar en SQL Editor de Supabase.
-- Comprueba tipos, obligatoriedad y valores automáticos del esquema real.
select table_name as tabla, column_name as columna, data_type as tipo,
       is_nullable as admite_null, column_default as valor_por_defecto,
       is_identity as identidad, is_generated as generado
from information_schema.columns
where table_schema = 'public'
  and table_name in ('clientes', 'ventas', 'polizas_pendientes_asignacion')
order by table_name, ordinal_position;

-- Restricciones que también pueden rechazar una fila aunque el mapeo sea correcto.
select c.relname as tabla, k.conname as restriccion,
       pg_get_constraintdef(k.oid) as definicion
from pg_constraint k
join pg_class c on c.oid = k.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('clientes', 'ventas', 'polizas_pendientes_asignacion')
order by c.relname, k.conname;
