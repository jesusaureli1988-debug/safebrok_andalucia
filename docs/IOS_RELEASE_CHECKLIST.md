# Compilación y entrega iOS de SafeBrok

Estado preparado: versión `1.1.0`, build `8`, Bundle ID `com.safebrok`, iOS mínimo 13.0.

## Flujo principal: Codemagic

El repositorio ya contiene el workflow `ios-release`, que reutiliza la integración `Codemagic Safebrok`, el perfil `safebrok_appstore_push` y el certificado `safebrok_distribution` usados por la versión anterior.

El workflow ejecuta paquetes, análisis, pruebas de roles, CocoaPods, asignación de perfiles, compilación firmada del IPA y publicación en App Store Connect. La build configurada es la 8.

Antes de iniciarlo, confirmar en Codemagic que el certificado y el perfil no estén caducados. Si la build 8 ya aparece en App Store Connect, cambiar `--build-number` en `codemagic.yaml` y `pubspec.yaml` al siguiente número.

## Alternativa: preparar el proyecto en un Mac

```bash
flutter doctor -v
flutter clean
flutter pub get
cd ios
pod install --repo-update
cd ..
flutter test
flutter analyze
flutter build ipa --release --build-name=1.1.0 --build-number=8
open ios/Runner.xcworkspace
```

No abrir `Runner.xcodeproj`: con CocoaPods debe abrirse `Runner.xcworkspace`.

## Xcode

1. Seleccionar `Runner` > `Signing & Capabilities`.
2. Elegir el Team de la cuenta Apple Developer de SafeBrok.
3. Confirmar Bundle Identifier `com.safebrok` y firma automática.
4. Confirmar las capacidades `Push Notifications` y `Background Modes` con `Remote notifications`.
5. Seleccionar `Any iOS Device (arm64)` y ejecutar `Product > Archive`.
6. En Organizer, ejecutar primero `Validate App` y resolver todos los errores y avisos relevantes.
7. Elegir `Distribute App > App Store Connect > Upload`.

Si el build 8 ya existe en App Store Connect, incrementar el número sin cambiar la versión, por ejemplo `--build-number=9`.

## App Store Connect

- Esperar a que el procesamiento del build termine y comprobar que no quede ningún aviso.
- Completar la URL de política de privacidad y las respuestas de App Privacy conforme a los datos realmente tratados.
- En App Review Information introducir la cuenta `appreview@safebrok.es` y su contraseña estable.
- Pegar las notas de `docs/APP_STORE_CONNECT_NOTES.md`.
- Probar el build exacto desde TestFlight antes de enviarlo a revisión.
- No borrar la cuenta, cambiar su contraseña ni vaciar sus datos hasta que finalice la revisión.

## Validaciones ya realizadas

- 3/3 pruebas automatizadas de roles superadas.
- Archivos modificados analizados sin errores; permanecen avisos de estilo heredados.
- Login real de App Review probado contra Supabase.
- RLS, datos sintéticos aislados y Storage privado comprobados en producción.

La generación y firma final del `.ipa` no puede hacerse en Windows: Apple exige las herramientas de Xcode en macOS para producir y archivar la aplicación iOS.
