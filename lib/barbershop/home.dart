import 'package:flutter/material.dart';

import '../core/formats.dart';
import 'models.dart';

class ShopHome extends StatelessWidget {
  const ShopHome({
    super.key,
    required this.content,
    required this.onBook,
    required this.onChange,
    required this.onAccount,
    this.onService,
    this.onAppointments,
  });
  final ShopContent content;
  final VoidCallback onBook, onChange, onAccount;
  final VoidCallback? onAppointments;
  final void Function(ShopService)? onService;
  @override
  Widget build(BuildContext context) {
    final shop = content.shop;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CorteYa'),
        actions: [
          if (onAppointments != null)
            IconButton(
              onPressed: onAppointments,
              icon: const Icon(Icons.receipt_long),
              tooltip: 'Mis citas',
            ),
          IconButton(
            onPressed: onAccount,
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mi cuenta',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ShopLogo(name: shop.name, url: shop.logoUrl),
            ),
            const SizedBox(height: 24),
            Text(
              shop.name,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              shop.nextChangeAt == null
                  ? shop.statusMessage
                  : '${shop.open ? 'Abierto · cierra' : 'Cerrado · abre ${_day(shop.nextChangeAt!)}'} a las ${bogotaTime(shop.nextChangeAt!)}',
            ),
            const SizedBox(height: 24),
            if (shop.bookingEnabled)
              FilledButton(
                onPressed: onBook,
                child: const Text('Reservar cita'),
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Esta barbería todavía no recibe reservas en línea',
                  ),
                ),
              ),
            const SizedBox(height: 32),
            const Text(
              'Servicios',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (content.services.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aún no hay servicios disponibles.'),
              ),
            for (final service in content.services)
              Card(
                child: ListTile(
                  onTap: shop.bookingEnabled && onService != null
                      ? () => onService!(service)
                      : null,
                  title: Text(service.name),
                  subtitle: Text('${service.durationMinutes} min'),
                  trailing: Text(formatCop(service.priceCop)),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'El equipo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (content.barbers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Aún no hay equipo disponible para estos servicios.',
                ),
              ),
            for (final barber in content.barbers)
              Card(
                child: ListTile(
                  leading: ShopLogo(
                    name: barber.name,
                    url: barber.photoUrl,
                    size: 40,
                  ),
                  title: Text(barber.name),
                ),
              ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onChange,
              child: const Text('Cambiar de barbería'),
            ),
          ],
        ),
      ),
    );
  }

  String _day(DateTime date) {
    final d = bogota(date);
    final now = bogota(DateTime.now());
    final days = DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'hoy';
    if (days == 1) return 'mañana';
    return 'el ${['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'][d.weekday - 1]}';
  }
}

class ShopLogo extends StatelessWidget {
  const ShopLogo({super.key, required this.name, this.url, this.size = 80});
  final String name;
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size / 2, fontWeight: FontWeight.w800),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: url == null || url!.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => fallback,
              ),
            ),
    );
  }
}
