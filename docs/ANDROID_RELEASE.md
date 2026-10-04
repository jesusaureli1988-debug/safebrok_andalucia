# Publicación Android de SafeBrok

Versión preparada: `1.2.0+11`.

## 1. Compilar desde CMD

Abre CMD en `D:\safebrok_andalucia` y ejecuta:

```cmd
tools\build_android_release.cmd
```

El resultado será:

```text
build\app\outputs\flutter-apk\app-release.apk
```

El script muestra también el SHA-256 del archivo. Durante la compilación desactiva temporalmente el soporte Flutter para Windows para evitar errores de enlaces entre las unidades C: y D:, y lo vuelve a activar al terminar incluso si falla la compilación.

## 2. Firma: no cambiar para esta actualización

Las APK anteriores de este proyecto están configuradas con la firma de depuración en el tipo `release`. Android solo permite actualizar una app si el nuevo APK usa la misma firma y el mismo `applicationId`.

Para que los usuarios actuales puedan actualizar sin desinstalar:

- no cambies `applicationId` (`com.example.safebrok_andalucia`);
- no cambies todavía `signingConfig`;
- no regeneres ni sustituyas la clave usada por Flutter/Android;
- instala primero el APK encima de una versión anterior en un móvil de prueba.

Antes de migrar a una firma de producción propia hay que planificar la transición: una APK firmada con otra clave no puede actualizar las instalaciones actuales.

## 3. Subir el APK

Usa preferentemente una URL HTTPS de descarga directa (Supabase Storage público, servidor propio o CDN). Evita enlaces de vista previa.

Si se usa Google Drive:

- compartir como `Cualquier persona con el enlace`;
- subir el archivo APK real, no un ZIP;
- probar el enlace desde una ventana privada y desde un móvil sin sesión de Google.

## 4. Probar antes de anunciar

Antes de activar la versión en `app_versions`:

1. Descarga el enlace desde un móvil Android.
2. Comprueba que el archivo pesa más de 1 MB.
3. Comprueba que Android reconoce el archivo como APK.
4. Instálalo encima de la versión anterior, sin desinstalarla.
5. Abre SafeBrok y confirma que mantiene la sesión y los datos.
6. Repite la prueba pulsando el botón `Actualizar ahora` dentro de SafeBrok.

## 5. Activar la actualización

En `app_versions`, crea o actualiza el registro con:

- `version`: `1.2.0+11`;
- `android_url` o `apk_url`: URL HTTPS directa del APK;
- si esas columnas no existen, usa `url`;
- `active`: `true` únicamente después de probar la descarga.

Deja una sola versión activa. El sistema acepta `android_url`, `apk_url` y, por compatibilidad, `url`.

## Comportamiento de respaldo

La aplicación intenta descargar, validar y abrir el APK internamente. Si la descarga es bloqueada, devuelve HTML o Android impide abrir el instalador, el diálogo ofrece `Abrir en navegador` para completar la descarga externamente.