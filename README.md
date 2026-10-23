# CorteYa — fase 7

Una app Android/iOS con marca CorteYa y apariencia de la barbería elegida por QR,
link o código. Estructura por feature: `app`, `core`, `barbershop`, `auth`, `account`.
No incluye todavía reservas/pagos ni operación del barbero.

## Ejecutar

Flutter **3.47.7 estable**, Dart **3.13.5**. Versiones de paquetes verificadas en
pub.dev el 23 de octubre de 2026; las resoluciones están en `pubspec.lock`.

```sh
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

Levanta `corteya-api` en el puerto 8080. `API_BASE_URL` vacío en dev selecciona
`http://10.0.2.2:8080` para el emulador Android y `http://localhost:8080` para el
simulador iOS. Para un teléfono físico u otra URL crea un override ignorado:

```json
{"APP_ENV":"dev","API_BASE_URL":"http://TU_IP_LOCAL:8080","APP_LINK_HOST":"corteya.invalid"}
```

Guárdalo como `env/dev.local.json` y ejecútalo con
`flutter run --dart-define-from-file=env/dev.local.json`. No incluyas secretos.
Android permite HTTP solo en debug. iOS permite redes locales para el simulador.
Certificación y producción tienen dominios `.invalid`: **no son ambientes
operativos**. TODO despliegue: reemplazar URLs y `APP_LINK_HOST`.

## Probar manualmente

1. Abre la app sin barbería guardada. Escanea un QR `corteya://b/barberia-piloto`
   o escribe `barberia-piloto`, si usas la semilla dev del backend. No hay datos
   de prueba fijos en el cliente.
2. Revisa nombre, inicial/logo, colores, horarios de Bogotá, servicios en COP y
   equipo. Reinicia para comprobar que recuerda la barbería. Prueba un código
   inexistente y “Cambiar de barbería”.
3. Toca “Reservar cita”: valida el celular, solicita un OTP real del backend,
   introduce sus seis dígitos y completa el nombre si hace falta. El destino
   final es un placeholder. Reenvío se habilita a los 60 segundos.
4. Con sesión de OWNER/BARBER de la barbería actual, comprueba “Modo barbero”.
   Una membresía de otra barbería debe mostrar el home del cliente.
5. En “Mi cuenta”, prueba cancelar las confirmaciones, cerrar sesión y borrar
   una cuenta de prueba. Borrar la cuenta es irreversible.
6. Prueba cámara denegada, conexión interrumpida y mensajes ProblemDetail de
   OTP (429/503). Usa los controles del backend para alternar `bookingEnabled`.

Deep links de prueba (sustituye el slug por uno existente):

```sh
adb shell am start -a android.intent.action.VIEW -d 'corteya://b/barberia-piloto' com.geovannycode.corteya
xcrun simctl openurl booted 'corteya://b/barberia-piloto'
```

## Contrato y seguridad

`openapi/corteya-api.json` es una copia de `http://localhost:8080/v3/api-docs`
obtenida el 23 de octubre de 2026. No se genera ni inventa el contrato. Los modelos
son manuales y solo cubren los endpoints usados en esta fase. El OpenAPI servido
no documenta los cuerpos 200 del catálogo público: esos modelos se contrastaron
con los DTO/controladores y las respuestas reales de la barbería piloto.

**Dependencia del backend:** `/api/v1/me` debe incluir `barbershopSlug` y
`barbershopName` en cada membership. El contrato local obtenido ya los contiene;
se requiere el PR correspondiente en `develop` de `corteya-api`. Un backend antiguo
sin slug nunca activa el modo barbero por conjetura. La comparación se hace por
slug y rol OWNER/BARBER, sin exponer el ID de la barbería en el catálogo público.

Los tokens se guardan juntos en Keychain/Keystore mediante
`flutter_secure_storage`; el último slug se guarda en UserDefaults/SharedPreferences
mediante un canal nativo. El refresh tiene una única operación compartida entre
401 concurrentes y maneja los 401 que llegan después de la rotación. Si falla,
limpia tokens y vuelve al login. No se reintenta automáticamente un refresh fallido.
El logger existe solo en debug/dev y registra únicamente método HTTP y estado,
sin URL, cabeceras, cuerpos ni excepciones. No se incluyen llaves de Wompi.

Bricolage Grotesque está empaquetada en `assets/fonts` con su licencia OFL.
El tema usa los colores del backend con fallbacks de CorteYa; el color del texto
sobre cada acento se elige por contraste de luminancia.

## Verificación

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug --dart-define-from-file=env/dev.json
flutter build apk --debug --dart-define-from-file=env/dev.json
```

La suite cubre formatos, validación, contraste, errores, OTP, home, sesión,
refresh concurrente y tardío, arranque, roles por slug y navegación con deep links.
El mínimo iOS es 15.0 con Flutter actualizado. Los permisos de cámara, orientación
vertical, bundle ID `com.geovannycode.corteya` y nombre CorteYa están configurados.

## TODO de fases posteriores

- Fase 8: reserva real y pagos.
- Fase 9: modo barbero.
- Push/Firebase cuando corresponda en el backend.
- Despliegue: URLs reales, Universal Links/App Links, Associated Domains,
  `apple-app-site-association`, `assetlinks.json`, firma de publicación e iconos finales.
  Los QR HTTPS del host configurado ya se interpretan dentro del lector, pero el
  sistema operativo aún no abre enlaces HTTPS en la app.
- Confirmar incorporación del PR de memberships del backend en `develop`.
