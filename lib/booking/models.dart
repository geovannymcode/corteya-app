import '../core/formats.dart';

Map<String, dynamic> objectMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
DateTime instant(Object? value) {
  final text = value as String;
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
    throw const FormatException('Fecha sin offset');
  }
  return DateTime.parse(text);
}

DateTime? optionalInstant(Object? value) =>
    value == null ? null : instant(value);
String dateKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String dayLabel(DateTime value, {DateTime? now}) {
  final day = bogota(value);
  final today = bogota(now ?? DateTime.now());
  if (day.year == today.year &&
      day.month == today.month &&
      day.day == today.day) {
    return 'hoy';
  }
  return 'el ${['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'][day.weekday - 1]}';
}

String freeAtText(DateTime? value, DateTime now) => value == null
    ? 'Sin horarios esta semana'
    : 'Libre ${dayLabel(value, now: now)} a las ${bogotaTime(value)}';
String appointmentStatusText(String status) => switch (status) {
  'PENDING_PAYMENT' => 'Pendiente de pago',
  'CONFIRMED' => 'Confirmada',
  'CANCELLED' => 'Cancelada',
  'EXPIRED' => 'Vencida',
  'COMPLETED' => 'Finalizada',
  'NO_SHOW' => 'No asististe',
  _ => 'Estado por verificar',
};

class BookingQuote {
  BookingQuote.fromJson(Map<String, dynamic> j)
    : priceCop = j['priceCop'] as int,
      depositCop = j['depositCop'] as int,
      payAtShopCop = j['payAtShopCop'] as int,
      depositMode = j['depositMode'] as String,
      holdMinutes = j['holdMinutes'] as int,
      until = optionalInstant(j['cancellableWithRefundUntil']),
      policy = j['cancelPolicyText'] as String {
    if (priceCop < 0 ||
        depositCop < 0 ||
        depositCop > priceCop ||
        payAtShopCop != priceCop - depositCop ||
        !['NONE', 'BREB_MANUAL', 'WOMPI'].contains(depositMode) ||
        policy.trim().isEmpty) {
      throw const FormatException('Cotización no válida');
    }
  }
  final int priceCop, depositCop, payAtShopCop, holdMinutes;
  final String depositMode, policy;
  final DateTime? until;
}

class PaymentInstructions {
  PaymentInstructions.fromJson(Map<String, dynamic> j)
    : mode = j['mode'] as String,
      amountCop = j['amountCop'] as int,
      reference = j['reference'] as String,
      expiresAt = instant(j['expiresAt']),
      brebKey = j['brebKey'] as String?,
      holder = j['brebHolderName'] as String?,
      checkoutUrl = j['checkoutUrl'] as String?,
      parameters = j['checkoutParameters'] == null
          ? null
          : Map<String, String>.from(j['checkoutParameters'] as Map);
  final String mode, reference;
  final int amountCop;
  final DateTime expiresAt;
  final String? brebKey, holder, checkoutUrl;
  final Map<String, String>? parameters;
}

class Appointment {
  Appointment.fromJson(this.json)
    : token = json['publicToken'] as String,
      status = json['status'] as String,
      startsAt = instant(json['startsAt']),
      endsAt = instant(json['endsAt']);
  final Map<String, dynamic> json;
  final String token, status;
  final DateTime startsAt, endsAt;
  String get serviceName =>
      json['serviceName'] as String? ?? 'Servicio de tu cita';
  String get barberName =>
      json['barberName'] as String? ?? 'Barbero de tu cita';
  String get shopName => json['barbershopName'] as String? ?? 'Tu barbería';
  String? get shopSlug => json['barbershopSlug'] as String?;
  int? get priceCop => json['priceCop'] as int?;
  int get depositCop => json['depositCop'] as int;
  Map<String, dynamic>? get deposit =>
      json['deposit'] == null ? null : objectMap(json['deposit']);
  DateTime? get holdExpiresAt =>
      optionalInstant(deposit?['holdExpiresAt'] ?? json['holdExpiresAt']);
  DateTime? get until => optionalInstant(json['cancellableWithRefundUntil']);
  String? get policy => json['cancelPolicyText'] as String?;
  String? get refundStatus =>
      deposit?['refundStatus'] as String? ?? json['refundStatus'] as String?;
  String? get attemptStatus => deposit?['latestAttemptStatus'] as String?;
  bool get canRetry => deposit?['canRetry'] == true;
  bool get cancellable => json['cancellable'] == true;
  PaymentInstructions? get instructions =>
      (json['paymentInstructions'] ?? deposit?['paymentInstructions']) == null
      ? null
      : PaymentInstructions.fromJson(
          objectMap(
            json['paymentInstructions'] ?? deposit?['paymentInstructions'],
          ),
        );
}

class MyAppointments {
  const MyAppointments(this.upcoming, this.past);
  final List<Appointment> upcoming, past;
}
