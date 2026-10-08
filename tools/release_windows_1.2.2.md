# SafeBrok Windows 1.2.2 (13)

## Correcciones

- Un solo instalador, sin envolver ni ejecutar instaladores antiguos.
- AppId y carpeta instalada conservados, para sustituir la misma instalación.
- Acceso directo público del escritorio siempre apunta a `safebrok_andalucia.exe`, no a Setup ni a una URL.
- Al arrancar, una instalación normal repara únicamente un `SafeBrok.lnk` privado existente que apunte a otro ejecutable. No borra instaladores ni datos.
- Dependencias de Visual C++ junto a la aplicación, incluidas MSVCP140 y vcruntime140.
- Runtime x64 de Visual C++ 14.51.36231, correspondiente al compilador seleccionado por Flutter, no una versión anterior incompatible.
- Actualización desde la app: descarga con progreso, comprobación del formato EXE, permiso normal de Windows y ejecución silenciosa.
- La app solo se cierra tras confirmar que Windows inició el instalador. Si se cancela el permiso, permanece abierta.
- Un helper no elevado espera al instalador y reabre SafeBrok con el usuario original; no abre una segunda copia desde el instalador.
- Un import antiguo del servicio de actualización redirige al servicio único, no al navegador.
- El compilador del instalador rechaza EXEs cuya versión real no coincida con 1.2.2.13.
- El nombre del paquete contiene versión y build. Windows usa esa versión propia para no ofrecer un instalador anterior cuando la fila general avanza por Android.

## Publicación, después de comprobar el archivo generado

Archivo previsto: `D:\safebrok_andalucia\releases\SafeBrokSetup_1.2.2_13.exe`.

Subir el ARCHIVO al bucket `actualizaciones`, carpeta `windows`, manteniendo ese nombre.

URL pública que funcionará DESPUÉS de subir el archivo:

`https://ytmxjavihwylrswphczc.supabase.co/storage/v1/object/public/actualizaciones/windows/SafeBrokSetup_1.2.2_13.exe`

Columna `windows_url`: esa URL. Columna `version`: `1.2.2+13`.

La versión anunciada y la app dentro del instalador deben coincidir. Si se anuncia una versión nueva pero windows_url sigue descargando una anterior, se repite el aviso de actualizar.

No se ha subido nada ni cambiado app_versions automáticamente. No usar la URL antes de subir el archivo y probar su descarga.

Windows puede solicitar permiso de administrador o avisar del editor no reconocido; no se omiten UAC ni SmartScreen. El flujo completo de instalación debe probarse en un equipo real antes de activar la actualización general.

## Validación

Las 44 pruebas Flutter han pasado. Las pruebas PowerShell usan instalador/registro simulados: no instalan nada ni alteran el escritorio.

Compilación de Windows y compilación del instalador terminadas con código 0. El análisis de los archivos modificados terminó sin errores (quedan recomendaciones/advertencias).

Versión real del ejecutable: `1.2.2+13`. Versión numérica del instalador: `1.2.2.13`. El control de versiones impidió empaquetar el EXE anterior 1.2.1.

Instalador generado: 17.301.630 bytes. SHA-256: `0D249AFF395DF25604F58E47650F82C0D1ABA1746A705BA7312D3924DAEB9F0C`.

Las dependencias MSVCP140.dll, VCRUNTIME140.dll y VCRUNTIME140_1.dll identificadas en el ejecutable están incluidas en el instalador. No se ha instalado el paquete sobre la app de este ordenador; falta la prueba real de actualización antes de activarlo para todos.

La comprobación anónima de app_versions fue rechazada por los permisos de Supabase. No se han cambiado esos permisos ni se han usado credenciales privilegiadas; no se ha confirmado la fila activa actual.

Compilación técnica: fuentes pequeñas en NTFS (C), por los enlaces de plugins; salida pesada en `D:\safebrok_andalucia\build_windows_1.2.2_13`. El disco D es exFAT. No se han borrado datos de D.
