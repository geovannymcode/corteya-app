import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/state.dart';
import '../core/errors.dart';
import '../core/formats.dart';
import 'api.dart';
import 'models.dart';
import 'poller.dart';
import 'wompi.dart';

final checkoutLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.inAppBrowserView),
);
final paymentRouteObserver = RouteObserver<ModalRoute<void>>();

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.token,
    this.initial,
    this.overrideInstructions,
  });
  final String token;
  final Appointment? initial;
  final PaymentInstructions? overrideInstructions;
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  Appointment? appointment;
  PaymentInstructions? instructions;
  Object? error;
  bool busy = true;
  bool opening = false;
  Timer? timer;
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
      final result =
          widget.initial ??
          await ref.read(bookingApiProvider).appointment(widget.token);
      if (!mounted) return;
      if (result.status != 'PENDING_PAYMENT') {
        context.go('/appointments/${widget.token}');
        return;
      }
      setState(() {
        appointment = result;
        instructions = widget.overrideInstructions ?? result.instructions;
        busy = false;
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (tick) {
        if (instructions != null &&
            !ref.read(clockProvider)().isBefore(instructions!.expiresAt)) {
          tick.cancel();
        }
        if (mounted) setState(() {});
      });
      if (instructions?.mode == 'WOMPI') await openCheckout();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> openCheckout() async {
    if (opening ||
        instructions == null ||
        !ref.read(clockProvider)().isBefore(instructions!.expiresAt)) {
      return;
    }
    setState(() {
      opening = true;
      error = null;
    });
    try {
      await ref
          .read(pendingPaymentProvider)
          .save(ref.read(appProvider).profile!.id, widget.token);
      final payment = instructions!;
      final uri = wompiCheckoutUri(payment.checkoutUrl!, payment.parameters!);
      if (!await ref.read(checkoutLauncherProvider)(uri)) {
        throw StateError('Checkout unavailable');
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copiado')));
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = instructions;
    final remaining =
        payment?.expiresAt.difference(ref.read(clockProvider)()).inSeconds ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paga tu señal'),
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
            if (!busy && payment == null) ...[
              const Text(
                'Consulta el estado de tu reserva para retomar el pago.',
              ),
              FilledButton(
                onPressed: () =>
                    context.go('/appointments/${widget.token}/wait'),
                child: const Text('Consultar estado'),
              ),
            ],
            if (payment != null) ...[
              Text(
                formatCop(payment.amountCop),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                remaining > 0
                    ? 'Tiempo restante: ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
                    : 'Tu reserva venció. Si ya pagaste, la barbería lo revisará',
              ),
              const SizedBox(height: 24),
              if (payment.mode == 'BREB_MANUAL') ...[
                const Text(
                  'Envía desde tu banco o Nequi por Bre-B y escribe la referencia',
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Llave Bre-B'),
                  subtitle: Text(payment.brebKey ?? 'No disponible'),
                  trailing: IconButton(
                    tooltip: 'Copiar llave',
                    onPressed: payment.brebKey == null
                        ? null
                        : () => copy(payment.brebKey!),
                    icon: const Icon(Icons.copy),
                  ),
                ),
                Text('Titular: ${payment.holder ?? 'No disponible'}'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Referencia'),
                  subtitle: Text(payment.reference),
                  trailing: IconButton(
                    tooltip: 'Copiar referencia',
                    onPressed: () => copy(payment.reference),
                    icon: const Icon(Icons.copy),
                  ),
                ),
                FilledButton(
                  onPressed: remaining > 0
                      ? () => context.go('/appointments/${widget.token}/wait')
                      : null,
                  child: const Text('Ya transferí'),
                ),
              ] else if (payment.mode == 'WOMPI') ...[
                const Text(
                  'Completa el pago en Wompi. Al regresar verificaremos el estado con la barbería.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: remaining > 0 && !opening ? openCheckout : null,
                  child: Text(opening ? 'Abriendo…' : 'Abrir Wompi'),
                ),
                TextButton(
                  onPressed: () =>
                      context.go('/appointments/${widget.token}/wait'),
                  child: const Text('Ya volví: consultar pago'),
                ),
              ],
              if (remaining <= 0)
                FilledButton(
                  onPressed: () => context.go('/appointments'),
                  child: const Text('Mis citas'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({
    super.key,
    required this.token,
    required this.onConfirmed,
  });
  final String token;
  final void Function(Appointment) onConfirmed;
  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen>
    with WidgetsBindingObserver, RouteAware {
  late final AppointmentPoller poller;
  bool routed = false, retrying = false, visible = true;
  Object? retryError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    poller = AppointmentPoller(
      api: ref.read(bookingApiProvider),
      token: widget.token,
      now: ref.read(clockProvider),
    );
    poller.addListener(changed);
    Future.microtask(updateActivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) paymentRouteObserver.subscribe(this, route);
  }

  void updateActivity() {
    if (mounted) {
      poller.setActive(
        visible &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => updateActivity();
  @override
  void didPushNext() {
    visible = false;
    updateActivity();
  }

  @override
  void didPopNext() {
    visible = true;
    updateActivity();
  }

  void changed() {
    if (!mounted) return;
    if (poller.appointment?.status == 'CONFIRMED' && !routed) {
      routed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onConfirmed(poller.appointment!);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    paymentRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    poller.removeListener(changed);
    poller.dispose();
    super.dispose();
  }

  Future<void> retry() async {
    if (retrying) return;
    setState(() {
      retrying = true;
      retryError = null;
    });
    try {
      final payment = await ref.read(bookingApiProvider).retry(widget.token);
      if (mounted) {
        context.go('/appointments/${widget.token}/payment', extra: payment);
      }
    } catch (e) {
      if (mounted) setState(() => retryError = e);
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = poller.appointment;
    final expired = poller.expired || a?.status == 'EXPIRED';
    final failed = ['DECLINED', 'ERROR'].contains(a?.attemptStatus);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estamos verificando tu pago'),
        leading: BackButton(onPressed: () => context.go('/appointments')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (poller.busy) const Center(child: CircularProgressIndicator()),
            if (poller.error != null) ...[
              Text(userMessage(poller.error!)),
              TextButton(
                onPressed: poller.refresh,
                child: const Text('Reintentar consulta'),
              ),
            ],
            if (expired) ...[
              const Text(
                'Tu reserva venció. Si ya pagaste, la barbería lo revisará',
              ),
              FilledButton(
                onPressed: () => context.go('/booking'),
                child: const Text('Volver a reservar'),
              ),
            ] else if (a?.status == 'CANCELLED') ...[
              Text(
                a?.json['cancellationMessage'] as String? ?? 'Tu cita fue cancelada. Revisa el detalle para consultar la señal.',
              ),
              TextButton(
                onPressed: () => context.go('/appointments/${widget.token}'),
                child: const Text('Ver detalle'),
              ),
            ] else if (a != null &&
                a.status != 'PENDING_PAYMENT' &&
                a.status != 'CONFIRMED') ...[
              Text(appointmentStatusText(a.status)),
              TextButton(
                onPressed: () => context.go('/appointments/${widget.token}'),
                child: const Text('Ver detalle'),
              ),
            ] else if (failed) ...[
              const Text('El pago no se aprobó'),
              if (a?.canRetry == true)
                FilledButton(
                  onPressed: retrying ? null : retry,
                  child: const Text('Intentar de nuevo'),
                ),
            ] else ...[
              const SizedBox(height: 32),
              const Text(
                'Esperamos la confirmación de la barbería. Puedes volver a Mis citas sin perder tu reserva.',
              ),
              if (a?.instructions?.mode == 'BREB_MANUAL')
                TextButton(
                  onPressed: () => context.go(
                    '/appointments/${widget.token}/payment',
                    extra: a,
                  ),
                  child: const Text('Ver datos de transferencia'),
                ),
            ],
            if (retryError != null) Text(userMessage(retryError!)),
          ],
        ),
      ),
    );
  }
}

class PaymentReturnScreen extends ConsumerStatefulWidget {
  const PaymentReturnScreen({super.key});
  @override
  ConsumerState<PaymentReturnScreen> createState() =>
      _PaymentReturnScreenState();
}

class _PaymentReturnScreenState extends ConsumerState<PaymentReturnScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      String? token;
      try {
        final user = ref.read(appProvider).profile?.id;
        if (user != null) {
          token = await ref.read(pendingPaymentProvider).read(user);
        }
      } catch (_) {
        /* Retomar desde Mis citas. */
      }
      if (mounted) {
        context.go(
          token == null ? '/appointments' : '/appointments/$token/wait',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
