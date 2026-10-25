# Fase 9 — Modo barbero

La membresía se compara con el slug de la barbería seleccionada. OWNER puede ver
toda la agenda y filtrar; BARBER consulta su ámbito y usa su `barberId` al crear
citas y bloqueos. El servidor valida siempre permisos y transiciones.

## Probar

1. Levantar corteya-api con fase 9A y ejecutar la app en Android/iOS:
   `flutter run --dart-define-from-file=env/dev.json`.
2. Iniciar sesión con OWNER de la barbería actual. Comprobar filtro de barberos,
   días, agenda ordenada, bloqueos y las cuatro pestañas. Con BARBER el filtro y
   desglose no aparecen. Una membresía de otra barbería abre el modo cliente.
3. Abrir una cita: confirmar/rechazar una señal Bre-B, marcar asistencia en los
   límites horarios, cancelar indicando motivo y confirmar una devolución por
   monto y nombre. Verificar que solo cambia después de responder el servidor.
4. Crear una cita manual usando sugerencias o una hora elegida; repetir en un
   horario ocupado para obtener 409. Crear un bloqueo que cruce citas y revisar
   la lista de conflictos; eliminar un bloqueo con confirmación.
5. Revisar Pendientes y su contador (depósitos únicos), pagos tardíos y contacto.
   El número aparece solo en modo barbero; WhatsApp y teléfono usan aplicaciones
   del dispositivo y no se registra el número en logs.
6. Seleccionar Día, Semana y Mes en Resumen. Las devoluciones pendientes muestran
   el total actual recibido del servidor, independiente del periodo.
7. Dejar Agenda visible: se consulta cada 60 segundos después de terminar la
   carga. Cambiar a Cuenta, cubrir la ruta o poner la app en segundo plano:
   se cancelan timer y peticiones. Volver reactiva una consulta inmediata.

## Validación automatizada

`flutter analyze` y `flutter test`. `test/staff_test.dart` usa un adaptador HTTP
con respuestas del contrato para comprobar roles, acciones, conflictos, periodos,
contador, enlaces E.164 y suspensión del refresco. Los datos de pruebas no se
activan en producción.

## TODO fuera de alcance

- Push (backend fase 5/5B): sustituir el refresco periódico cuando exista.
- Configuración de barbería y pagos: panel administrativo.
- Señal multimétodo: fase 11.
- Prueba en dispositivos con las aplicaciones WhatsApp/teléfono instaladas.
