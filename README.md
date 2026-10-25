# CorteYa — fases 7 y 8

Una app Android/iOS con marca CorteYa y apariencia de la barbería elegida por QR,
link o código. Estructura por feature: `app`, `core`, `barbershop`, `auth`, `account`.
Incluye reserva, señal y Mis citas contra el contrato acordado de backend 8B.
El modo barbero sigue siendo un placeholder para fase 9.

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
   final es el flujo de reserva. Reenvío se habilita a los 60 segundos.
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

- Push/Firebase cuando corresponda en el backend.
- Despliegue: URLs reales, Universal Links/App Links, Associated Domains,
  `apple-app-site-association`, `assetlinks.json`, firma de publicación e iconos finales.
  Los QR HTTPS del host configurado ya se interpretan dentro del lector, pero el
  sistema operativo aún no abre enlaces HTTPS en la app.

# Fase 8 — reserva, señal y Mis citas

El flujo de reserva usa servicio → barbero → horario →
cotización → confirmación. Incluye pagos Bre-B/Wompi, espera, ticket, calendario,
Mis citas y cancelación con confirmación.

El contrato 8B y la cancelación ya están en develop de corteya-api; ver
[contrato verificado](docs/backend-fase-8B.md). Las pruebas usan fixtures y la app
consume siempre los endpoints reales. Para pagos Wompi comprobar las credenciales
sandbox y el redirect `corteya://pago` configurado en el backend.

Paquetes nuevos verificados en pub.dev: `url_launcher 6.3.3` y
`add_2_calendar 3.1.1`. No se añadieron otros paquetes externos. Wompi sigue la
[documentación oficial de Web Checkout](https://docs.wompi.co/docs/colombia/widget-checkout-web/).

## Probar fase 8

```sh
flutter analyze
flutter test
flutter run --dart-define-from-file=env/dev.json
```

Con backend 8B, tocar Reservar cita o un servicio; elegir barbero, día y hora;
revisar la cotización y confirmar. Probar NONE, Bre-B y Wompi sandbox configurados
por el backend. En Bre-B, copiar llave/referencia, esperar confirmación del staff y
comprobar vencimiento. En Wompi, completar el checkout y volver mediante
`corteya://pago`; un parámetro `status=CONFIRMED` en el enlace no confirma nada.
Retomar desde Mis citas después de cerrar la app, probar reintentos de pago,
cancelación a tiempo/tarde y añadir una cita confirmada al calendario del teléfono.

Las pruebas de widget e integración con mocks cubren los pasos, servicio
preseleccionado, cotización autoritativa, ambos 409, Bre-B, estados de espera,
confirmación de cancelación, polling y regresiones de sesión/horarios de fase 7.
Quedan para dispositivo físico la experiencia del banco/Wompi, permisos y guardado
del calendario; no se realizaron pagos reales ni cancelaciones de datos reales.

TODO: push/Firebase, acción propia de reprogramación,
dominio/Universal Links y publicación. La reprogramación sigue siendo cancelar y
reservar de nuevo.


## Fase 9 — modo barbero

OWNER y BARBER de la barbería actual entran a Agenda, Pendientes, Resumen y Cuenta.
Incluye citas manuales, bloqueos, confirmación/rechazo de señales, asistencia,
cancelación con motivo y registro de devoluciones. OWNER filtra por barbero y ve
el desglose; BARBER queda limitado a su ámbito por el backend. El refresco de
60 segundos se cancela al ocultar la pestaña/ruta o suspender la app.

El OpenAPI se actualizó desde el backend local con fase 9A (PR #8 integrado).
No se añadieron paquetes. Ver [cómo probar y pendientes](docs/fase-09-modo-barbero.md).
