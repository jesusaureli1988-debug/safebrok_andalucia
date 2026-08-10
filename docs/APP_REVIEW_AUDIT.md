# Auditoría de App Review de SafeBrok

Fecha: 10 de agosto de 2026. Proyecto Supabase enlazado: `ytmxjavihwylrswphczc` (`safebrok_andalucia`).

## Resultado ejecutivo

El backend remoto fue auditado y endurecido el 10 de agosto de 2026. La migración `supabase/sql/20260810_rls_app_review.sql` se validó primero dentro de una transacción revertida y después se aplicó definitivamente al proyecto de producción. La cuenta estable de revisión y su escenario sintético también quedaron creados y comprobados mediante una sesión autenticada simulada.

La estrategia segura es una cuenta real con rol `director_nacional`, sin MFA, SMS ni confirmaciones pendientes, y un conjunto de datos sintéticos aislado. No se usará `service_role` en Flutter. Las operaciones privilegiadas seguirán limitadas a Edge Functions autenticadas.

## Hallazgos confirmados

1. El alta pública permitía escoger roles jerárquicos, incluido director de zona. Dependía de RLS para no convertirse en escalada de privilegios y además activaba el requisito de eliminación de cuenta de Apple. Se retiró de la pantalla de acceso: SafeBrok es una red privada y las cuentas se provisionan administrativamente.
2. No existía eliminación de cuenta dentro de la app. Al retirar el registro público, la app ya no ofrece creación de cuenta al usuario final. Si se vuelve a activar el alta, antes debe implementarse eliminación conforme a 5.1.1(v).
3. El cierre de sesión navegaba a `/login`, ruta no registrada en `MaterialApp`. Se sustituyó por navegación directa y limpieza del historial.
4. La splash bloqueaba al revisor durante nueve segundos en cada arranque. Se redujo a tres.
5. iOS permitía tráfico arbitrario mediante `NSAllowsArbitraryLoads=true`. Se eliminó; los servicios usados son HTTPS.
6. iOS declaraba ubicación sin existir una dependencia ni llamadas de geolocalización. Se eliminó esa declaración para no solicitar o declarar datos no usados.
7. Había acciones visibles sin implementar (`Notificaciones`, banco y transferencia). Se retiraron de navegación hasta que tengan un flujo real. Esto evita presentar funciones incompletas, no oculta funciones activas.
8. La normalización de roles estaba duplicada y no era uniforme. Se creó `AppRole`; login, router, shell y ajustes usan ahora valores canónicos.
9. Tres Edge Functions estaban marcadas con `verify_jwt=false`. Las funciones invocadas por usuarios (`safebrok-ia`, `enviar-push`, `enviar-tpv-recibo` y `enviar-factura-nomina`) quedan declaradas con JWT obligatorio. Las funciones de cron mantienen `verify_jwt=false` únicamente cuando validan `CRON_SECRET` o combinan cron y validación manual de JWT.
10. Los remitentes `onboarding@resend.dev` y `facturas@tudominio.com` son marcadores no aptos para producción. Deben sustituirse por dominios verificados antes de probar envíos con Apple.
11. No hay Remote Config ni feature flags por plataforma. Firebase solo se inicializa en Android/iOS para notificaciones. La navegación funcional no cambia específicamente para iOS.
12. El permiso push se solicita durante el arranque, antes de que el usuario vea contexto. No bloquea el acceso si se deniega, pero conviene moverlo a una acción explicativa posterior al login.

## Matriz de roles

| Rol | Inicio | Chat | Negocio | SafeCloud | Ajustes | Administración |
|---|---:|---:|---:|---:|---:|---:|
| director_nacional | Sí | Sí | Sí | Sí | Sí | Sí |
| administracion | Sí | Sí | Sí | Sí | Sí | Sí |
| director_zona | Sí | Sí | Sí | Sí | Sí | Sí |
| jefe_ventas | Sí | Sí | Sí | Sí | Sí | Sí |
| jefe_equipo | Sí | Sí | Sí | Sí | Sí | No |
| agente | Sí | Sí | Sí | Sí | Sí | No |

La cuenta de Apple debe usar `director_nacional`, el rol que expone el catálogo funcional más amplio. El acceso a filas debe seguir dependiendo de RLS, no de que un botón esté oculto.

## Rutas principales para Apple

1. Login → Inicio: indicadores, objetivos, accesos por rol y ranking.
2. Chat: conversación interna y adjuntos.
3. Negocio: ventas, clientes, recibos, visitas, gestiones, referencias, producción e informes.
4. SafeCloud: carpetas, archivos, subida, descarga, compartir y eliminación.
5. Ajustes → Perfil / Seguridad / Incidencias / Soporte / Información.
6. Ajustes → Panel de administración: usuarios, producción, recibos, clientes, nóminas, facturas y configuración autorizada.

## Condiciones de la cuenta de revisión

- Identidad Auth confirmada y no bloqueada.
- Perfil `usuarios.auth_id` enlazado exactamente con `auth.users.id`.
- `rol_usuario='director_nacional'`, `estado='activo'`, sin espacios ni variantes.
- Contraseña estable hasta que Apple finalice la revisión; no exigir cambio inicial.
- Sin MFA, OTP, SMS, CAPTCHA interactivo ni allowlist de IP/dispositivo.
- Datos exclusivamente sintéticos: nombres de ejemplo, correos reservados y documentos sin datos personales reales.
- Al menos un registro representativo en usuarios, clientes, ventas, recibos, tareas, visitas, incidencias, chat y SafeCloud.
- Edge Functions y buckets desplegados en el mismo proyecto que consume la build.
- No borrar, renombrar ni desactivar la cuenta mientras la versión esté en revisión.

## Estado remoto verificado

- Proyecto: `ytmxjavihwylrswphczc`, rama de producción.
- Antes de la corrección: 31 tablas públicas tenían RLS desactivada y 3 tablas adicionales tenían RLS sin políticas.
- Después de la corrección: 0 tablas públicas sin RLS, 49 políticas `app_*` y 2 columnas de aislamiento de revisión.
- Integridad: se conservaron los 104 perfiles y 107 usuarios Auth existentes. Después se añadieron únicamente las 2 identidades Auth sintéticas autorizadas.
- Prueba de roles: un director nacional real conserva visibilidad de 104 perfiles, 508 clientes y 493 ventas; un agente probado queda limitado a su perfil, 2 clientes y 2 ventas.
- Prueba de Apple: la cuenta de revisión obtiene `director_nacional`, `es_cuenta_revision=true` y solo ve 2 perfiles sintéticos, 2 clientes, 2 ventas, 1 visita, 1 gestión y la conversación de demostración.
- No se almacenó `service_role`, ninguna contraseña ni otro secreto en Flutter o en Git.

## Infraestructura adicional cerrada

- Los buckets `chat-archivos`, `cv_candidatos` y `gestiones-archivos` son privados y cuentan con 12 políticas de objetos. Los nuevos registros guardan referencias `storage://` y los enlaces antiguos se transforman en URL firmadas de corta duración.
- Se verificó de extremo a extremo con la cuenta de Apple: subida autorizada, generación de URL firmada, descarga HTTP 200 y eliminación del objeto temporal.
- Las fuentes locales de `enviar-tpv-recibo`, `enviar-factura-nomina` y `enviar-push` validan usuario y permisos dentro de la función. La configuración local mantiene JWT obligatorio.

## Operaciones que no se pueden completar desde Windows

- Desplegar las nuevas versiones de Edge Functions requiere iniciar sesión con Supabase CLI o un token personal; el Dashboard actual solo permite descargar, probar y consultar código desplegado.
- El archivo iOS debe generarse en macOS con Xcode. El proyecto ya incluye `ios/Podfile`, Bundle ID `com.safebrok`, Firebase iOS, entitlement push y build `1.1.0+8`.
- Los remitentes de correo de ejemplo deben sustituirse por dominios verificados antes de probar esos envíos con Apple.
