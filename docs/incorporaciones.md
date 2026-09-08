# Módulo de Incorporaciones

## Puesta en marcha

1. Ejecutar `supabase/sql/20260830_incorporaciones.sql` después de `20260810_rls_app_review.sql`.
2. Regenerar/reiniciar la aplicación para cargar el nuevo acceso **Ajustes → Incorporaciones**.
3. Confirmar que existen perfiles `administracion` activos en `usuarios`; reciben los avisos internos.

El bucket `incorporaciones` se crea privado. La aplicación guarda únicamente la ruta del objeto y genera URLs firmadas de 15 minutos al abrir un documento.

## Prueba funcional completa

1. Entrar como responsable y abrir Captación → candidato en estado `SELECCIONADO` → **Iniciar incorporación**.
2. Completar datos, figura, responsable jerárquico y los cinco documentos; enviar.
3. Entrar como Administración en Ajustes → Incorporaciones. Abrir el expediente, iniciar revisión y validar/rechazar cada documento.
4. Si se rechaza, solicitar corrección con observaciones; como responsable, sustituir archivos y reenviar.
5. Validar documentación, adjuntar/publicar contrato y marcar pendiente de firma.
6. Como solicitante, abrir el contrato mediante URL firmada, subir el firmado y enviarlo.
7. Como Administración, completar el alta. `alta_preparada` contiene el payload canónico para el alta Auth/`usuarios`, sin duplicar una segunda ficha operativa.
8. Revisar `incorporacion_historial` y las notificaciones en Inicio.

## Seguridad a comprobar

- Un usuario no puede consultar toda `usuarios`: se reutiliza la RLS jerárquica existente.
- Backend rechaza figura/responsable incompatible aunque se altere la petición del cliente.
- Figura y responsable quedan bloqueados al generarse el contrato; solo Administración puede autorizar el cambio.
- Los objetos de Storage no tienen URL pública y solo son visibles para el solicitante, su estructura autorizada o Administración.
