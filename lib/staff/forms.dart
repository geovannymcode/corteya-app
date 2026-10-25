import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../booking/api.dart';
import '../booking/models.dart';
import '../barbershop/models.dart';
import '../core/errors.dart';
import '../core/formats.dart';
import 'api.dart';
import 'models.dart';

class StaffForm extends ConsumerStatefulWidget {
  const StaffForm({
    super.key,
    required this.slug,
    required this.owner,
    required this.assignedBarber,
    required this.day,
    required this.block,
  });
  final String slug;
  final bool owner, block;
  final String? assignedBarber;
  final DateTime day;
  @override
  ConsumerState<StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<StaffForm> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      reason = TextEditingController();
  late DateTime day;
  TimeOfDay time = const TimeOfDay(hour: 12, minute: 0),
      end = const TimeOfDay(hour: 13, minute: 0);
  String? barber, service;
  String reasonType = 'Almuerzo';
  bool busy = false, loadingSlots = false;
  String? error, slotsError;
  List<DateTime> slots = [];
  List<Barber> eligible = [];
  List<dynamic> conflicts = [];
  int selection = 0;
  @override
  void initState() {
    super.initState();
    day = widget.day;
    barber = widget.assignedBarber;
    Future.microtask(loadServices);
  }

  @override
  void dispose() {
    selection++;
    name.dispose();
    phone.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> loadServices() async {
    final services = ref.read(appProvider).content!.services;
    if (widget.block) return;
    if (services.isNotEmpty) {
      setState(() => service = services.first.id);
      await loadSlots();
    }
  }

  Future<void> loadSlots() async {
    if (widget.block || service == null) return;
    final generation = ++selection;
    setState(() {
      loadingSlots = true;
      slotsError = null;
      slots = [];
    });
    try {
      final api = ref.read(bookingApiProvider);
      final available = await api.barbers(widget.slug, service!);
      if (!mounted || selection != generation) return;
      eligible = available
          .where((b) => widget.owner || b.id == widget.assignedBarber)
          .toList();
      if (widget.owner && !eligible.any((b) => b.id == barber)) {
        barber = eligible.firstOrNull?.id;
      }
      if (barber == null) throw StateError('Sin barbero asignado');
      final result = await api.slots(widget.slug, service!, barber!, day);
      if (!mounted || generation != selection) return;
      setState(() => slots = result.values.expand((v) => v).toList()..sort());
    } catch (e) {
      if (mounted && selection == generation) {
        setState(() => slotsError = userMessage(e));
      }
    } finally {
      if (mounted && generation == selection) {
        setState(() => loadingSlots = false);
      }
    }
  }

  String timestamp(TimeOfDay value) =>
      '${dateKey(day)}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00-05:00';
  Future<void> save() async {
    if (busy) return;
    final id = widget.owner ? barber : widget.assignedBarber;
    if (id == null) {
      setState(
        () =>
            error = 'No encontramos tu barbero asignado. Actualiza tu sesión.',
      );
      return;
    }
    if (!widget.block && (service == null || name.text.trim().isEmpty)) {
      setState(
        () => error = 'Elige un servicio y escribe el nombre del cliente.',
      );
      return;
    }
    if (!widget.block &&
        phone.text.trim().isNotEmpty &&
        e164(phone.text) == null) {
      setState(() => error = 'Revisa el celular del cliente.');
      return;
    }
    if (widget.block &&
        (end.hour * 60 + end.minute <= time.hour * 60 + time.minute ||
            reasonType == 'Otro' && reason.text.trim().isEmpty)) {
      setState(
        () => error = 'Revisa el inicio, el fin y el motivo del bloqueo.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      conflicts = [];
    });
    try {
      final api = ref.read(staffApiProvider);
      if (widget.block) {
        await api.block(widget.slug, {
          'barberId': id,
          'startsAt': timestamp(time),
          'endsAt': timestamp(end),
          'reason': reasonType == 'Otro' ? reason.text.trim() : reasonType,
        });
      } else {
        await api.manual(widget.slug, {
          'barberId': id,
          'serviceId': service,
          'startsAt': timestamp(time),
          'customerName': name.text.trim(),
          if (phone.text.trim().isNotEmpty) 'customerPhone': e164(phone.text),
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final body = e is DioException ? e.response?.data : null;
        conflicts = body is Map && body['conflicts'] is List
            ? body['conflicts'] as List
            : [];
        error = conflicts.isNotEmpty
            ? 'No se puede bloquear: tienes ${conflicts.length} citas en ese horario'
            : !widget.block &&
                  e is DioException &&
                  e.response?.statusCode == 409
            ? 'Ya hay una cita en ese horario'
            : userMessage(e);
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(appProvider).content!;
    final barbers = widget.block ? content.barbers : eligible;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.block ? 'Bloquear horas' : 'Nueva cita manual'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!widget.block)
            DropdownButtonFormField<String>(
              initialValue: service,
              decoration: const InputDecoration(labelText: 'Servicio'),
              items: content.services
                  .map(
                    (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() => service = v);
                      loadSlots();
                    },
            ),
          if (widget.owner)
            DropdownButtonFormField<String>(
              key: ValueKey('barber-$barber-${barbers.length}'),
              initialValue: barbers.any((b) => b.id == barber) ? barber : null,
              decoration: const InputDecoration(labelText: 'Barbero'),
              items: barbers
                  .map(
                    (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() => barber = v);
                      loadSlots();
                    },
            ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime(day.year, day.month, day.day),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) {
                      setState(() => day = d);
                      loadSlots();
                    }
                  },
            child: Text('Día: ${dateKey(day)}'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (t != null && mounted) setState(() => time = t);
                  },
            child: Text('Inicio: ${time.format(context)}'),
          ),
          if (!widget.block) ...[
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      final n = bogota(ref.read(clockProvider)());
                      setState(() {
                        day = n;
                        time = TimeOfDay(hour: n.hour, minute: n.minute);
                      });
                      loadSlots();
                    },
              child: const Text('Ahora mismo'),
            ),
            const Text(
              'Horarios libres sugeridos. También puedes escribir otra hora en el selector.',
            ),
            if (loadingSlots) const LinearProgressIndicator(),
            if (slotsError != null) ...[
              Text(slotsError!),
              TextButton(
                onPressed: loadSlots,
                child: const Text('Reintentar horarios'),
              ),
            ],
            if (!loadingSlots && slotsError == null && slots.isEmpty)
              const Text('No hay horarios sugeridos para este día.'),
            Wrap(
              spacing: 8,
              children: slots
                  .map(
                    (s) => ActionChip(
                      label: Text(bogotaTime(s)),
                      onPressed: busy
                          ? null
                          : () {
                              final b = bogota(s);
                              setState(
                                () => time = TimeOfDay(
                                  hour: b.hour,
                                  minute: b.minute,
                                ),
                              );
                            },
                    ),
                  )
                  .toList(),
            ),
            TextField(
              controller: name,
              maxLength: 150,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Nombre del cliente',
              ),
            ),
            TextField(
              controller: phone,
              maxLength: 16,
              enabled: !busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Celular (opcional)',
              ),
            ),
          ] else ...[
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: end,
                      );
                      if (t != null && mounted) setState(() => end = t);
                    },
              child: Text('Fin: ${end.format(context)}'),
            ),
            DropdownButtonFormField<String>(
              initialValue: reasonType,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                'Almuerzo',
                'Imprevisto',
                'Otro',
              ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: busy ? null : (v) => setState(() => reasonType = v!),
            ),
            if (reasonType == 'Otro')
              TextField(
                controller: reason,
                maxLength: 255,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Motivo del bloqueo',
                ),
              ),
          ],
          if (error != null) Text(error!),
          for (final c in conflicts)
            Builder(
              builder: (_) {
                final j = objectMap(c);
                return ListTile(
                  title: Text(
                    '${bogotaTime(instant(j['startsAt']))} – ${bogotaTime(instant(j['endsAt']))}',
                  ),
                );
              },
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Guardando…'
                  : widget.block
                  ? 'Guardar bloqueo'
                  : 'Crear cita',
            ),
          ),
        ],
      ),
    );
  }
}
