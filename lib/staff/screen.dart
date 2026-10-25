import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/screen.dart';
import '../app/state.dart';
import '../auth/profile.dart';
import '../booking/api.dart';
import '../booking/models.dart';
import '../booking/payment.dart' show paymentRouteObserver;
import '../core/errors.dart';
import '../core/formats.dart';
import 'api.dart';
import 'forms.dart';
import 'models.dart';
import 'refresh.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen>
    with WidgetsBindingObserver, RouteAware {
  int tab = 0;
  late DateTime day;
  String period = 'DAY';
  String? barber;
  bool foreground = true, visible = true, busy = true, mutating = false;
  Object? error;
  List<StaffAppointment> appointments = [];
  List<TimeBlock> blocks = [];
  ActionItems? items;
  Map<String, dynamic>? summary;
  late final StaffRefresh refresher;
  ModalRoute<void>? route;
  String get slug => ref.read(appProvider).content!.shop.slug;
  Membership get membership => ref
      .read(appProvider)
      .profile!
      .memberships
      .firstWhere(
        (m) => m.barbershopSlug == slug && ['OWNER', 'BARBER'].contains(m.role),
      );
  bool get owner => membership.role == 'OWNER';
  StaffApi get api => ref.read(staffApiProvider);
  DateTime now() => ref.read(clockProvider)();
  @override
  void initState() {
    super.initState();
    day = bogota(now());
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    refresher = StaffRefresh(load);
    Future.microtask(sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (next != route) {
      if (route != null) paymentRouteObserver.unsubscribe(this);
      route = next;
      if (next is PageRoute<void>) paymentRouteObserver.subscribe(this, next);
    }
  }

  void sync() =>
      refresher.setActive(mounted && foreground && visible && tab != 3);
  @override
  void didPushNext() {
    visible = false;
    sync();
  }

  @override
  void didPopNext() {
    visible = true;
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    refresher.dispose();
    paymentRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load(CancelToken cancel) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selectedTab = tab;
      final actions = await api.actions(slug, cancel);
      List<StaffAppointment>? a;
      List<TimeBlock>? b;
      Map<String, dynamic>? s;
      if (selectedTab == 0) {
        a = await api.agenda(slug, day, owner ? barber : null, cancel);
        b = await api.blocks(slug, day, cancel);
      } else if (selectedTab == 2) {
        s = await api.summary(slug, period, day, cancel);
      }
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        items = actions;
        if (a != null) appointments = a;
        if (b != null) blocks = b;
        if (s != null) summary = s;
      });
    } catch (e) {
      if (mounted && !cancel.isCancelled) setState(() => error = e);
    } finally {
      if (mounted && !cancel.isCancelled) setState(() => busy = false);
    }
  }

  void selectTab(int value) {
    refresher.setActive(false);
    setState(() {
      tab = value;
      error = null;
      busy = value != 3;
    });
    sync();
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> action(
    String id,
    String action,
    String title,
    String message, {
    String? reason,
  }) async {
    if (mutating || !await confirm(title, message) || !mounted) return;
    setState(() => mutating = true);
    try {
      await api.act(slug, id, action, reason: reason);
      if (!mounted) return;
      await refresher.refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    } finally {
      if (mounted) setState(() => mutating = false);
    }
  }

  Future<void> contact(
    String? phone,
    String customer,
    DateTime startsAt, {
    bool call = false,
    String? message,
  }) async {
    final normalized = e164(phone);
    if (normalized == null) return;
    final uri = call
        ? Uri(scheme: 'tel', path: normalized)
        : whatsappLink(
            normalized,
            message ??
                reminder(
                  customer,
                  startsAt,
                  ref.read(appProvider).content!.shop.name,
                  now(),
                ),
          );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No disponible');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos abrir la aplicación de contacto.'),
          ),
        );
      }
    }
  }

  Widget contactButtons(
    String? phone,
    String customer,
    DateTime start, {
    String? message,
  }) => Wrap(
    spacing: 8,
    children: [
      TextButton(
        onPressed: e164(phone) == null
            ? null
            : () => contact(phone, customer, start, message: message),
        child: const Text('Escribir por WhatsApp'),
      ),
      TextButton(
        onPressed: e164(phone) == null
            ? null
            : () => contact(phone, customer, start, call: true),
        child: const Text('Llamar'),
      ),
    ],
  );
  Future<void> detail(StaffAppointment a) async {
    // Dialog lives above this route; stop periodic reads while it is open.
    refresher.setActive(false);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(a.customer),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a.service} · ${a.barber}'),
              Text('${dateKey(bogota(a.start))} · ${bogotaTime(a.start)}'),
              Text(staffStatus(a.status)),
              Text(depositLabel(a.depositStatus)),
              if (refundLabel(a.refundStatus) != null)
                Text(refundLabel(a.refundStatus)!),
              if (a.phone != null) Text(a.phone!),
              contactButtons(a.phone, a.customer, a.start),
              if (items?.groups['pendingBreB']?.any((v) => v.id == a.id) ==
                  true) ...[
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    action(
                      a.id,
                      'deposit/confirm',
                      '¿Sí llegó la señal?',
                      'Confirma que recibiste ${formatCop(a.amount)} de ${a.customer}.',
                    );
                  },
                  child: Text('Sí me llegó ${formatCop(a.amount)}'),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(c);
                    action(
                      a.id,
                      'deposit/reject',
                      '¿No llegó la señal?',
                      'La reserva será cancelada y el horario quedará libre.',
                    );
                  },
                  child: const Text('No me llegó'),
                ),
              ],
              if (a.status == 'CONFIRMED') ...[
                FilledButton(
                  onPressed: a.canComplete(now())
                      ? () {
                          Navigator.pop(c);
                          action(
                            a.id,
                            'complete',
                            '¿Asistió?',
                            'Registrar la asistencia de ${a.customer}.',
                          );
                        }
                      : null,
                  child: const Text('Asistió'),
                ),
                if (!a.canComplete(now()))
                  const Text(
                    'Puedes marcar asistencia desde 15 minutos antes del inicio',
                  ),
                OutlinedButton(
                  onPressed: a.canNoShow(now())
                      ? () {
                          Navigator.pop(c);
                          action(
                            a.id,
                            'no-show',
                            '¿No asistió?',
                            'Registrar la inasistencia de ${a.customer}.',
                          );
                        }
                      : null,
                  child: const Text('No asistió'),
                ),
                if (!a.canNoShow(now()))
                  const Text(
                    'Puedes marcar inasistencia después de la hora de inicio',
                  ),
              ],
              if (['PENDING_PAYMENT', 'CONFIRMED'].contains(a.status) ||
                  a.depositStatus == 'LATE_PAYMENT')
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    cancelAppointment(a.id);
                  },
                  child: const Text('Cancelar cita'),
                ),
              if (a.refundStatus == 'PENDING')
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    action(
                      a.id,
                      'deposit/refunded',
                      'Marcar como devuelta',
                      '¿Ya le devolviste ${formatCop(a.amount)} a ${a.customer}?',
                    );
                  },
                  child: const Text('Marcar como devuelta'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (mounted) sync();
  }

  Future<void> cancelAppointment(String id) async {
    final text = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Cancelar cita'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'La señal recibida, si existe, quedará pendiente de devolución.',
              ),
              TextField(
                controller: text,
                maxLength: 500,
                onChanged: (_) => update(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: text.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(c, text.text.trim()),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    // Wait until the dialog has detached its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (reason != null && mounted) {
      await action(
        id,
        'cancel',
        '¿Cancelar cita?',
        'La señal recibida quedará para devolver.',
        reason: reason,
      );
    }
  }

  Future<void> form(bool block) async {
    refresher.setActive(false);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StaffForm(
          slug: slug,
          owner: owner,
          assignedBarber: membership.barberId,
          day: day,
          block: block,
        ),
      ),
    );
    if (mounted) sync();
  }

  Widget dateSelector() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Día anterior',
        onPressed: () {
          setState(() => day = day.subtract(const Duration(days: 1)));
          refresher.refresh();
        },
        icon: const Icon(Icons.chevron_left),
      ),
      TextButton(
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: DateTime(day.year, day.month, day.day),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null && mounted) {
            setState(() => day = d);
            refresher.refresh();
          }
        },
        child: Text(DateFormat('EEE d MMM yyyy', 'es_CO').format(day)),
      ),
      IconButton(
        tooltip: 'Día siguiente',
        onPressed: () {
          setState(() => day = day.add(const Duration(days: 1)));
          refresher.refresh();
        },
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Widget agenda() {
    final content = ref.read(appProvider).content!;
    final filtered = blocks
        .where((b) => !owner || barber == null || b.barberId == barber)
        .toList();
    final timeline = <({DateTime start, Widget tile})>[
      for (final a in appointments)
        (
          start: a.start,
          tile: Card(
            child: ListTile(
              onTap: mutating ? null : () => detail(a),
              leading: Text(bogotaTime(a.start)),
              title: Text('${a.customer} · ${a.service}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (owner) Text(a.barber),
                  Wrap(
                    spacing: 4,
                    children: [
                      Chip(label: Text(staffStatus(a.status))),
                      Chip(label: Text(depositLabel(a.depositStatus))),
                      if (refundLabel(a.refundStatus) != null)
                        Chip(label: Text(refundLabel(a.refundStatus)!)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      for (final b in filtered)
        (
          start: b.start,
          tile: Card(
            child: ListTile(
              leading: const Icon(Icons.block),
              title: Text(
                '${bogotaTime(b.start)} – ${bogotaTime(b.end)} · ${b.reason}',
              ),
              subtitle: owner
                  ? Text(
                      content.barbers
                          .where((v) => v.id == b.barberId)
                          .map((v) => v.name)
                          .join(),
                    )
                  : null,
              trailing: IconButton(
                tooltip: 'Eliminar bloqueo',
                icon: const Icon(Icons.delete_outline),
                onPressed: mutating
                    ? null
                    : () async {
                        if (!await confirm('¿Eliminar bloqueo?', b.reason) ||
                            !mounted) {
                          return;
                        }
                        try {
                          await api.deleteBlock(slug, b.id);
                          await refresher.refresh();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(userMessage(e))),
                            );
                          }
                        }
                      },
              ),
            ),
          ),
        ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return Column(
      children: [
        dateSelector(),
        if (owner)
          DropdownButton<String>(
            value: barber,
            hint: const Text('Todos los barberos'),
            items: [
              const DropdownMenuItem<String>(child: Text('Todos los barberos')),
              ...content.barbers.map(
                (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
              ),
            ],
            onChanged: (v) {
              setState(() => barber = v);
              refresher.refresh();
            },
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => form(false),
              icon: const Icon(Icons.add),
              label: const Text('Nueva cita'),
            ),
            OutlinedButton.icon(
              onPressed: () => form(true),
              icon: const Icon(Icons.block),
              label: const Text('Bloquear horas'),
            ),
          ],
        ),
        if (timeline.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No tienes citas hoy'),
          ),
        ...timeline.map((v) => v.tile),
      ],
    );
  }

  Widget pending() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (items?.count == 0)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text('No tienes pendientes'),
        ),
      for (final group in const {
        'pendingBreB': 'Señales por confirmar',
        'latePayments': 'Pagos tardíos',
        'pendingRefunds': 'Devoluciones pendientes',
      }.entries) ...[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            group.value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final item in items?.groups[group.key] ?? <ActionItem>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item.customer} · ${formatCop(item.amount)}'),
                  Text(item.reference),
                  if (group.key == 'latePayments')
                    const Text(
                      'El dinero llegó después de vencer la reserva. Revisa la devolución con el cliente.',
                    ),
                  if (group.key == 'pendingBreB')
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: mutating
                              ? null
                              : () => action(
                                  item.id,
                                  'deposit/confirm',
                                  '¿Sí llegó la señal?',
                                  'Confirma que recibiste ${formatCop(item.amount)} de ${item.customer}.',
                                ),
                          child: Text('Sí me llegó ${formatCop(item.amount)}'),
                        ),
                        TextButton(
                          onPressed: mutating
                              ? null
                              : () => action(
                                  item.id,
                                  'deposit/reject',
                                  '¿No llegó la señal?',
                                  'La reserva será cancelada y el horario quedará libre.',
                                ),
                          child: const Text('No me llegó'),
                        ),
                      ],
                    )
                  else ...[
                    contactButtons(
                      item.phone,
                      item.customer,
                      item.start,
                      message:
                          'Hola ${item.customer}, te escribo de ${ref.read(appProvider).content!.shop.name} para coordinar la devolución de tu señal de ${formatCop(item.amount)}.',
                    ),
                    if (group.key == 'latePayments') ...[
                      const Text(
                        'Si la reserva venció, cancélala con un motivo antes de registrar la devolución.',
                      ),
                      TextButton(
                        onPressed: mutating
                            ? null
                            : () => cancelAppointment(item.id),
                        child: const Text('Cancelar cita con motivo'),
                      ),
                    ],
                    TextButton(
                      onPressed: mutating
                          ? null
                          : () => action(
                              item.id,
                              'deposit/refunded',
                              'Marcar como devuelta',
                              '¿Ya le devolviste ${formatCop(item.amount)} a ${item.customer}?',
                            ),
                      child: const Text('Marcar como devuelta'),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    ],
  );
  Widget report() {
    final metrics = summary == null ? null : objectMap(summary!['metrics']);
    return Column(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'DAY', label: Text('Día')),
            ButtonSegment(value: 'WEEK', label: Text('Semana')),
            ButtonSegment(value: 'MONTH', label: Text('Mes')),
          ],
          selected: {period},
          onSelectionChanged: (v) {
            setState(() => period = v.first);
            refresher.refresh();
          },
        ),
        dateSelector(),
        if (metrics != null) ...[
          for (final entry in {
            'Citas': '${metrics['totalAppointments']}',
            'Completadas': '${metrics['completed']}',
            'No asistieron': '${metrics['noShows']}',
            'Tasa de no-show': '${metrics['noShowRate']}%',
            'Señales recibidas': formatCop(
              (metrics['depositsReceivedCop'] as num).toInt(),
            ),
            'Facturación estimada': formatCop(
              (metrics['estimatedRevenueCop'] as num).toInt(),
            ),
            'Devoluciones pendientes (total actual)':
                '${metrics['pendingRefunds']} · ${formatCop((metrics['pendingRefundsCop'] as num).toInt())}',
          }.entries)
            Card(
              child: ListTile(
                title: Text(entry.key),
                trailing: Text(entry.value),
              ),
            ),
          if (owner) ...[
            const Text('Por barbero'),
            for (final row in summary!['barbers'] as List)
              Builder(
                builder: (_) {
                  final j = objectMap(row);
                  final m = objectMap(j['metrics']);
                  final total = (metrics['totalAppointments'] as num)
                      .toDouble();
                  return ListTile(
                    title: Text(j['barberName'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['totalAppointments']} citas · ${m['completed']} completadas',
                        ),
                        LinearProgressIndicator(
                          value: total <= 0
                              ? 0
                              : ((m['totalAppointments'] as num) / total).clamp(
                                  0,
                                  1,
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    if (state.content == null ||
        state.profile?.staffOf(state.content!.shop.slug) != true) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(state.content!.shop.name),
        actions: [
          IconButton(
            tooltip: 'Cambiar de barbería',
            onPressed: () => ref.read(appProvider.notifier).changeShop(),
            icon: const Icon(Icons.store_outlined),
          ),
        ],
      ),
      body: tab == 3
          ? const AccountScreen()
          : RefreshIndicator(
              onRefresh: refresher.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (busy && visible && foreground)
                    const LinearProgressIndicator(),
                  if (error != null) ...[
                    Text(userMessage(error!)),
                    TextButton(
                      onPressed: refresher.refresh,
                      child: const Text('Reintentar'),
                    ),
                  ] else if (!busy || items != null)
                    switch (tab) {
                      0 => agenda(),
                      1 => pending(),
                      _ => report(),
                    },
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: selectTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${items?.count ?? 0}'),
              isLabelVisible: (items?.count ?? 0) > 0,
              child: const Icon(Icons.pending_actions),
            ),
            label: 'Pendientes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart),
            label: 'Resumen',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}
