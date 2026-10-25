# Contrato de corteya-api — fase 8B

El contrato 8B ya está implementado en `develop` de corteya-api (PR #7,
commit de integración `29d0431`). Se verificaron los DTO y controladores locales:
catálogo, cotización, detalle de señal, Mis citas y cancelación ya no son pendientes.
Las respuestas de `test/fixtures/booking_backend.dart` son fixtures de pruebas;
la app siempre usa la API real, sin simulaciones activadas en producción.

## Catálogo y ventana

`GET /api/v1/barbershops/{slug}` agrega:

```json
{"bookingWindowDays":14,"address":"Dirección de la barbería","city":"Bogotá"}
```

Los chips van desde hoy en Bogotá hasta `bookingWindowDays - 1`. No hay una ventana
inventada si el backend no la entrega. La dirección para el calendario se consulta
por el slug de la cita, aunque el usuario haya cambiado de barbería.

## Cotizar antes de confirmar

`GET /api/v1/barbershops/{slug}/booking-quote?serviceId=&barberId=&startsAt=`
requiere sesión y no crea citas ni pagos. La fecha lleva offset (la app envía UTC Z).

```json
{
  "priceCop":42000,
  "depositMode":"BREB_MANUAL",
  "depositCop":12000,
  "payAtShopCop":30000,
  "holdMinutes":15,
  "cancellableWithRefundUntil":"2026-10-23T09:00:00-05:00",
  "cancelPolicyText":"Política entregada por la barbería."
}
```

`depositMode` puede ser NONE, BREB_MANUAL o WOMPI. La app no calcula porcentajes de
señal, horas de cancelación ni políticas para el resumen. Verifica que los montos
sean consistentes y usa el `payAtShopCop` recibido. Un 409 en la cotización vuelve a
consultar horarios. POST de creación solo envía serviceId, barberId y startsAt.
El texto de un 409 por límite de pendientes se muestra tal como llega.

## Detalle del pago y reanudación

`GET /api/v1/appointments/{publicToken}` mantiene los campos anteriores de la cita,
la política/fecha límite del PR #6 y agrega:

```json
{
  "deposit":{
    "method":"WOMPI",
    "status":"PENDING",
    "amountCop":12000,
    "reference":"R-XXXX-1",
    "latestAttemptStatus":"DECLINED",
    "canRetry":true,
    "holdExpiresAt":"2026-10-23T10:15:00-05:00",
    "refundStatus":"NONE"
  },
  "paymentInstructions":null
}
```

`latestAttemptStatus`: PENDING, APPROVED, DECLINED, ERROR o VOIDED. Para Bre-B
pendiente, `paymentInstructions` debe permitir retomar la transferencia (mode,
amountCop, reference, expiresAt, brebKey, brebHolderName). Para Wompi, retomar o
reintentar solicita `POST /appointments/{publicToken}/payment-attempts`; el servidor
valida si corresponde. `canRetry` gobierna los reintentos de DECLINED/ERROR.

Las instrucciones Wompi usan el formato ya existente: `checkoutUrl`,
`checkoutParameters` y `expiresAt`, incluidos public-key, currency, amount-in-cents,
reference, signature:integrity, expiration-time y redirect-url. La app conserva
los parámetros firmados exactamente y solo acepta el host HTTPS checkout.wompi.co.
Debe configurarse el redirect del backend para volver a **corteya://pago**, sin
alterar las instrucciones en el cliente. La configuración antigua del backend
`corteya://appointments/{token}` requiere actualización.

El redirect no confirma pagos: ni status, id ni otros parámetros del enlace se
usan para decidir el resultado. El token en espera se guarda ligado al usuario
antes de abrir Wompi y se vuelve a consultar al backend. Si falta esa referencia,
la app abre Mis citas. El polling hace una solicitud a la vez, cada 5 segundos tras
éxito, con backoff de 10/20/40 segundos ante errores; se suspende al cubrir la ruta,
salir, pausar la app o vencer el hold.

## Mis citas y cancelación

Cada elemento de `GET /api/v1/me/appointments` (`upcoming` / `past`) mantiene
`publicToken` e incluye serviceName, barberName, barbershopName, barbershopSlug,
barbershopLogoUrl, startsAt, endsAt, priceCop, depositCop, status, depositStatus,
refundStatus, cancellable y cancellableWithRefundUntil. El cliente combina estos
datos con el estado más reciente del detalle; no interpreta el logo ni el slug de
la barbería seleccionada como si pertenecieran a una cita de otra barbería.

Cancelación implementada en el [PR #6 de corteya-api](https://github.com/geovannymcode/corteya-api/pull/6):
`POST /api/v1/appointments/{publicToken}/cancel`. Respuesta: publicToken, status,
refundStatus, refundAmountCop y **message**. Tras la confirmación explícita, la app
muestra ese message y recarga el estado. Nunca llama endpoints de staff para cancelar.

Las instrucciones para retomar Bre-B llegan dentro de
`deposit.paymentInstructions` en el detalle real. La app admite esa ubicación y
la ubicación superior del acuerdo inicial. El redirect de Wompi sigue siendo una
configuración del despliegue: comprobar `corteya://pago` antes de probar pagos.

## OpenAPI actualizado

`openapi/corteya-api.json` se exportó de `http://localhost:8080/v3/api-docs`
el 25 de octubre de 2026, usando el JAR local compilado con fase 9A.
La fase 9A ya fue integrada a develop del backend mediante el
[PR #8](https://github.com/geovannymcode/corteya-api/pull/8), verificado en GitHub.
El JAR se arrancó desde su checkout local de fase 9A; no se cambió su rama ni se
editaron sus fuentes.

## Modo barbero (fase 9A)

La fase 9 consume agenda, time-off, action-items y summary bajo
`/api/v1/barbershops/{slug}/staff`, y las acciones de citas por ID interno.
`/me.memberships[].barberId` permite enviar el barbero asignado al crear citas o
bloqueos como BARBER. Las consultas sin filtro siguen acotadas por el backend;
OWNER puede filtrar agenda por `barberId`.

Asistencia: desde 15 minutos antes de `startsAt`. Inasistencia: estrictamente
después de `startsAt`. La cancelación de staff requiere motivo y deja la señal
recibida pendiente de devolución. Marcarla devuelta registra una devolución ya
realizada; no transfiere dinero. Un pago tardío de una reserva vencida requiere
cancelar la cita antes de registrar la devolución. Las autorizaciones y los
estados los decide el backend; los errores se muestran con su mensaje.
