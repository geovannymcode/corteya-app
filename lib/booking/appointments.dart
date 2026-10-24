import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/errors.dart';
import '../barbershop/home.dart';
import '../core/formats.dart';
import 'api.dart';
import 'models.dart';
import 'wompi.dart';

final calendarWriterProvider = Provider<Future<bool> Function(Event)>(
  (ref) => Add2Calendar.addEvent2Cal,
);
String cancellationConsequence(Appointment a, DateTime now) {
  if (a.depositCop == 0) {
    return 'Tu cita se cancelará. No hay señal por devolver.';
  }
  if (a.status == 'PENDING_PAYMENT') {
    return 'Se liberará tu horario. Si ya transferiste, comunícate con la barbería para revisar el pago.';
  }
  final until = a.until;
  if (until == null) {
    throw const FormatException('Falta la política de cancelación');
  }
  return !now.isAfter(until)
      ? 'Cancelas a tiempo: la barbería te devolverá ${formatCop(a.depositCop)}.'
      : 'Cancelas fuera del plazo: la señal no es reembolsable.';
}

class MyAppointmentsScreen extends ConsumerStatefulWidget {
  const MyAppointmentsScreen({super.key});
  @override
  ConsumerState<MyAppointmentsScreen> createState() =>
      _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends ConsumerState<MyAppointmentsScreen> {
  MyAppointments? rows;
  Object? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(bookingApiProvider).mine();
      if (mounted) setState(() => rows = result);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mis citas'),
      leading: BackButton(onPressed: () => context.go('/home')),
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          if (busy) const Center(child: CircularProgressIndicator()),
          if (error != null) ...[
            Text(userMessage(error!)),
            TextButton(onPressed: load, child: const Text('Reintentar')),
          ],
          if (rows != null)
            for (final section in [
              ('Próximas', rows!.upcoming),
              ('Pasadas', rows!.past),
            ]) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  section.$1,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (section.$2.isEmpty)
                Text(
                  section.$1 == 'Próximas'
                      ? 'No tienes citas próximas.'
                      : 'Aún no tienes citas pasadas.',
                ),
              for (final a in section.$2)
                Card(
                  child: ListTile(
                    onTap: () async {
                      await context.push('/appointments/${a.token}');
                      if (mounted) load();
                    },
                    leading: ShopLogo(
                      name: a.shopName,
                      url: a.json['barbershopLogoUrl'] as String?,
                      size: 40,
                    ),
                    title: Text('${a.serviceName} · ${a.shopName}'),
                    subtitle: Text(
                      '${DateFormat('d MMM', 'es_CO').format(bogota(a.startsAt))} · ${bogotaTime(a.startsAt)}\n${appointmentStatusText(a.status)}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
            ],
        ],
      ),
    ),
  );
}

class AppointmentScreen extends ConsumerStatefulWidget {
  const AppointmentScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends ConsumerState<AppointmentScreen> {
  Appointment? appointment;
  Object? error;
  String? message;
  bool busy = true, acting = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final a = await ref.read(bookingApiProvider).appointment(widget.token);
      if (mounted) setState(() => appointment = a);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    final a = appointment!;
    String consequence;
    try {
      consequence = cancellationConsequence(a, ref.read(clockProvider)());
    } catch (e) {
      setState(() => error = e);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cancelar tu cita?'),
        content: Text(consequence),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Conservar cita'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => acting = true);
    try {
      final result = await ref.read(bookingApiProvider).cancel(widget.token);
      if (!mounted) return;
      setState(() => message = result);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> calendar() async {
    final a = appointment!;
    setState(() => acting = true);
    try {
      final slug = a.shopSlug;
      if (slug == null) throw const FormatException('Falta la dirección');
      final shop = await ref.read(bookingApiProvider).shop(slug);
      if ((shop.address ?? '').trim().isEmpty) {
        throw const FormatException('Falta la dirección');
      }
      final event = Event(
        title: '${a.serviceName} · ${a.shopName}',
        description: 'Con ${a.barberName}',
        location: [
          shop.address,
          shop.city,
        ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
        startDate: a.startsAt.toUtc(),
        endDate: a.endsAt.toUtc(),
        timeZone: 'America/Bogota',
      );
      final saved = await ref.read(calendarWriterProvider)(event);
      if (mounted) {
        setState(
          () => message = saved
              ? 'Revisa y guarda la cita en tu calendario.'
              : 'No se pudo abrir el calendario.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> resume() async {
    final a = appointment!;
    if (a.instructions?.mode == 'BREB_MANUAL') {
      context.go('/appointments/${a.token}/payment', extra: a);
      return;
    }
    setState(() => acting = true);
    try {
      final payment = await ref.read(bookingApiProvider).retry(a.token);
      if (mounted) {
        context.go('/appointments/${a.token}/payment', extra: payment);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          a?.status == 'CONFIRMED'
              ? 'Tu cita está confirmada'
              : 'Detalle de tu cita',
        ),
        leading: BackButton(onPressed: () => context.go('/appointments')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (busy) const Center(child: CircularProgressIndicator()),
            if (error != null) ...[
              Text(userMessage(error!)),
              TextButton(onPressed: load, child: const Text('Reintentar')),
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  message!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (a != null) ...[
              ClipPath(
                clipper: const TicketClipper(),
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.shopName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(appointmentStatusText(a.status)),
                      const Divider(height: 40),
                      Text(
                        a.serviceName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text('Con ${a.barberName}'),
                      const SizedBox(height: 16),
                      Text(
                        DateFormat(
                          'EEEE d MMMM',
                          'es_CO',
                        ).format(bogota(a.startsAt)),
                      ),
                      Text(
                        bogotaTime(a.startsAt),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Divider(height: 40),
                      Text(
                        '${a.status == 'CONFIRMED' ? 'Señal pagada' : 'Señal'}: ${formatCop(a.depositCop)}',
                      ),
                      if (a.priceCop != null)
                        Text(
                          'A pagar en la barbería: ${formatCop(remainingCop(a.priceCop!, a.depositCop))}',
                        )
                      else
                        const Text(
                          'El precio aún no está disponible. Vuelve a consultar.',
                        ),
                      if (a.refundStatus == 'PENDING')
                        const Text('La devolución de tu señal está pendiente.'),
                      if (a.refundStatus == 'DONE')
                        const Text(
                          'La barbería registró la devolución de tu señal.',
                        ),
                      if (a.refundStatus == 'FORFEITED')
                        const Text(
                          'La señal no es reembolsable según la política de cancelación.',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (a.status == 'CONFIRMED')
                OutlinedButton(
                  onPressed: acting ? null : calendar,
                  child: const Text('Añadir al calendario'),
                ),
              if (a.status == 'PENDING_PAYMENT') ...[
                FilledButton(
                  onPressed: () => context.go('/appointments/${a.token}/wait'),
                  child: const Text('Verificar pago'),
                ),
                if (a.instructions?.mode == 'BREB_MANUAL' ||
                    a.deposit?['method'] == 'WOMPI' &&
                        (a.canRetry || a.attemptStatus == 'PENDING'))
                  OutlinedButton(
                    onPressed: acting ? null : resume,
                    child: const Text('Retomar pago'),
                  ),
              ],
              if (a.cancellable &&
                  ['PENDING_PAYMENT', 'CONFIRMED'].contains(a.status) &&
                  ref.read(clockProvider)().isBefore(a.startsAt))
                TextButton(
                  onPressed: acting ? null : cancel,
                  child: const Text('Cancelar cita'),
                ),
              if (a.policy != null) Text(a.policy!),
              if (a.status == 'EXPIRED')
                const Text(
                  'Tu reserva venció. Si ya pagaste, la barbería lo revisará',
                ),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Listo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TicketClipper extends CustomClipper<Path> {
  const TicketClipper();
  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      );
    final cuts = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(0, size.height * .42), radius: 12),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, size.height * .42),
          radius: 12,
        ),
      );
    return Path.combine(PathOperation.difference, base, cuts);
  }

  @override
  bool shouldReclip(covariant TicketClipper oldClipper) => false;
}
