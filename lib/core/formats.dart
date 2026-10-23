import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

bool validPhone(String value) => RegExp(r'^3\d{9}$').hasMatch(value);
String formatCop(int value) => NumberFormat.currency(
  locale: 'es_CO',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '\u00a4#,##0',
).format(value);
tz.TZDateTime bogota(DateTime value) =>
    tz.TZDateTime.from(value, tz.getLocation('America/Bogota'));
String bogotaTime(DateTime value) {
  final date = bogota(value);
  return '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'a. m.' : 'p. m.'}';
}
