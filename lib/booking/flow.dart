import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/state.dart';
import '../core/errors.dart';
import '../core/formats.dart';
import 'api.dart';
import 'controller.dart';
import 'models.dart';

class BookingFlow extends ConsumerStatefulWidget {
  const BookingFlow({super.key, this.serviceId});
  final String? serviceId;
  @override
  ConsumerState<BookingFlow> createState() => _BookingFlowState();
}

class _BookingFlowState extends ConsumerState<BookingFlow> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final services = ref.read(appProvider).content?.services;
      final selected = services
          ?.where((s) => s.id == widget.serviceId)
          .firstOrNull;
      if (selected != null) {
        ref.read(bookingProvider.notifier).selectService(selected);
      }
    });
  }

  Future<void> confirm() async {
    final result = await ref.read(bookingProvider.notifier).confirm();
    if (result == null || !mounted) return;
    if (result.status == 'CONFIRMED') {
      context.go('/appointments/${result.token}');
      return;
    }
    try {
      await ref
          .read(pendingPaymentProvider)
          .save(ref.read(appProvider).profile!.id, result.token);
    } catch (_) {
      /* Mis citas sigue siendo la fuente para retomar sin caché local. */
    }
    if (mounted) {
      context.go('/appointments/${result.token}/payment', extra: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(appProvider).content!;
    final state = ref.watch(bookingProvider);
    final controller = ref.read(bookingProvider.notifier);
    final window = content.shop.bookingWindowDays;
    final now = bogota(ref.read(clockProvider)());
    final today = DateTime.utc(now.year, now.month, now.day);
    final quote = state.quote;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (state.quote != null) {
              controller.backTo(3);
            } else if (state.step > 1) {
              controller.backTo(state.step - 1);
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          quote != null
              ? 'Revisa tu reserva'
              : ['¿Qué te hacemos?', '¿Con quién?', '¿Cuándo?'][state.step - 1],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            LinearProgressIndicator(value: state.step / 3),
            const SizedBox(height: 12),
            Text('Paso ${state.step} de 3'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state.service != null)
                  ActionChip(
                    label: Text(state.service!.name),
                    onPressed: () => controller.backTo(1),
                  ),
                if (state.barber != null)
                  ActionChip(
                    label: Text(state.barber!.name),
                    onPressed: () => controller.backTo(2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.slotTaken) const Text('Ese horario acaba de ser tomado'),
            if (state.error != null) ...[
              Text(userMessage(state.error!)),
              TextButton(
                onPressed: state.loading
                    ? null
                    : () {
                        if (state.step == 2) {
                          controller.selectService(state.service!);
                        } else if (state.quote != null) {
                          controller.selectSlot(state.slot!);
                        } else {
                          controller.selectDay(state.day!);
                        }
                      },
                child: const Text('Reintentar'),
              ),
            ],
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (quote != null) ...[
              Text(
                state.service!.name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(state.barber!.name),
              Text(
                '${DateFormat('EEEE d MMMM', 'es_CO').format(bogota(state.slot!))} · ${bogotaTime(state.slot!)}',
              ),
              const SizedBox(height: 24),
              _money('Precio', quote.priceCop),
              _money('Señal a pagar ahora', quote.depositCop),
              _money('A pagar en la barbería', quote.payAtShopCop),
              const SizedBox(height: 24),
              Text(quote.policy),
              if (quote.until != null)
                Text(
                  'Puedes cancelar sin perder la señal hasta ${DateFormat('EEEE d MMMM', 'es_CO').format(bogota(quote.until!))} a las ${bogotaTime(quote.until!)}.',
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.loading ? null : confirm,
                child: const Text('Confirmar reserva'),
              ),
            ] else if (state.step == 1) ...[
              if (content.services.isEmpty)
                const Text('Esta barbería aún no tiene servicios disponibles.'),
              for (final service in content.services)
                Card(
                  child: ListTile(
                    onTap: () => controller.selectService(service),
                    title: Text(service.name),
                    subtitle: Text('${service.durationMinutes} min'),
                    trailing: Text(formatCop(service.priceCop)),
                  ),
                ),
            ] else if (state.step == 2 && !state.loading) ...[
              if (state.barbers.isEmpty && state.error == null)
                const Text('No hay barberos disponibles para este servicio.'),
              for (final barber in state.barbers)
                Opacity(
                  opacity: barber.nextAvailableAt == null ? 0.45 : 1,
                  child: Card(
                    child: ListTile(
                      enabled: barber.nextAvailableAt != null,
                      onTap: barber.nextAvailableAt == null
                          ? null
                          : () => controller.selectBarber(barber),
                      title: Text(barber.name),
                      subtitle: Text(
                        freeAtText(
                          barber.nextAvailableAt,
                          ref.read(clockProvider)(),
                        ),
                      ),
                    ),
                  ),
                ),
            ] else if (state.step == 3) ...[
              if (window == null || window < 1)
                const Text(
                  'No pudimos cargar la ventana de reservas de esta barbería. Intenta de nuevo más tarde.',
                )
              else ...[
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: window,
                    separatorBuilder: (_, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final day = today.add(Duration(days: i));
                      return ChoiceChip(
                        label: Text(DateFormat('EEE d', 'es_CO').format(day)),
                        selected: state.day == day,
                        onSelected: state.loading
                            ? null
                            : (_) => controller.selectDay(day),
                      );
                    },
                  ),
                ),
                if (!state.loading &&
                    state.error == null &&
                    state.slots.values.every((v) => v.isEmpty))
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No hay horarios disponibles este día. Elige otro.',
                    ),
                  ),
                for (final group in [
                  ('morning', 'Mañana'),
                  ('afternoon', 'Tarde'),
                ])
                  if (state.slots[group.$1]?.isNotEmpty == true) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        group.$2,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final slot in state.slots[group.$1]!)
                          ActionChip(
                            label: Text(bogotaTime(slot)),
                            onPressed: state.loading
                                ? null
                                : () => controller.selectSlot(slot),
                          ),
                      ],
                    ),
                  ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _money(String name, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        Text(
          formatCop(value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
