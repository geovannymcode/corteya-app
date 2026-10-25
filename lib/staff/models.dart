import '../booking/models.dart';
import '../core/formats.dart';

String staffStatus(String status) => switch (status) {
  'PENDING_PAYMENT' => 'Pendiente de señal',
  'CONFIRMED' => 'Confirmada',
  'COMPLETED' => 'Asistió',
  'NO_SHOW' => 'No asistió',
  'CANCELLED' => 'Cancelada',
  'EXPIRED' => 'Vencida',
  _ => 'Estado por verificar',
};
String depositLabel(String? status) => switch (status) {
  'PENDING' => 'Señal pendiente',
  'APPROVED' => 'Señal recibida',
  'LATE_PAYMENT' => 'Pago recibido tarde',
  'VOIDED' => 'Señal anulada',
  'EXPIRED' => 'Señal vencida',
  'DECLINED' => 'Pago rechazado',
  'ERROR' => 'Error de pago',
  _ => 'Sin señal recibida',
};

String? refundLabel(String status) => switch (status) {
  'PENDING' => 'Devolución pendiente',
  'DONE' => 'Señal devuelta',
  'FORFEITED' => 'Señal no reembolsable',
  _ => null,
};

String? e164(String? phone) {
  if (phone == null) return null;
  final value = phone.replaceAll(RegExp(r'[\s()-]'), '');
  final normalized = RegExp(r'^3\d{9}$').hasMatch(value) ? '+57$value' : value;
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized) ? normalized : null;
}

Uri whatsappLink(String phone, String message) {
  final normalized = e164(phone);
  if (normalized == null) throw const FormatException('Celular inválido');
  return Uri.https('wa.me', normalized.substring(1), {'text': message});
}

String reminder(String customer, DateTime startsAt, String shop, DateTime now) {
  final start = bogota(startsAt);
  final tomorrow = bogota(now).add(const Duration(days: 1));
  final when = dateKey(start) == dateKey(tomorrow)
      ? 'mañana'
      : '${dayLabel(start, now: now)} ${start.day}/${start.month}';
  return 'Hola $customer, te recuerdo tu cita de $when a las ${bogotaTime(start)} en $shop.';
}

class StaffAppointment {
  StaffAppointment.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      barberId = j['barberId'] as String,
      customer = j['customerName'] as String,
      phone = j['customerPhone'] as String?,
      service = j['serviceName'] as String,
      barber = j['barberName'] as String,
      start = instant(j['startsAt']),
      end = instant(j['endsAt']),
      status = j['status'] as String,
      depositStatus = j['depositStatus'] as String?,
      refundStatus = j['refundStatus'] as String,
      amount = (objectMap(j['appointment'])['depositCop'] as num).toInt();
  final String id, barberId, customer, service, barber, status, refundStatus;
  final String? phone, depositStatus;
  final DateTime start, end;
  final int amount;
  bool canComplete(DateTime now) =>
      !now.isBefore(start.subtract(const Duration(minutes: 15)));
  bool canNoShow(DateTime now) => now.isAfter(start);
}

class TimeBlock {
  TimeBlock.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      barberId = j['barberId'] as String,
      start = instant(j['startsAt']),
      end = instant(j['endsAt']),
      reason = j['reason'] as String? ?? 'Bloqueo';
  final String id, barberId, reason;
  final DateTime start, end;
}

class ActionItem {
  ActionItem.fromJson(Map<String, dynamic> j)
    : id = j['appointmentId'] as String,
      depositId = j['depositId'] as String,
      customer = j['customerName'] as String,
      phone = j['customerPhone'] as String?,
      start = instant(j['startsAt']),
      amount = (j['amountCop'] as num).toInt(),
      reference = j['reference'] as String;
  final String id, depositId, customer, reference;
  final String? phone;
  final DateTime start;
  final int amount;
}

class ActionItems {
  ActionItems.fromJson(Map<String, dynamic> j)
    : groups = {
        for (final key in ['pendingBreB', 'latePayments', 'pendingRefunds'])
          key: (j[key] as List)
              .map((v) => ActionItem.fromJson(objectMap(v)))
              .toList(),
      };
  final Map<String, List<ActionItem>> groups;
  int get count =>
      groups.values.expand((v) => v).map((v) => v.depositId).toSet().length;
}
