import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../core/errors.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool busy = false;
  String? error;
  Future<void> confirm({required bool delete}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(delete ? '¿Borrar tu cuenta?' : '¿Cerrar sesión?'),
        content: Text(
          delete
              ? 'Tu cuenta se borrará y tus datos de cliente serán anonimizados. Esta acción no se puede deshacer.'
              : 'Tendrás que verificar tu celular para entrar de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(delete ? 'Borrar mi cuenta' : 'Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final controller = ref.read(appProvider.notifier);
      if (delete) {
        await controller.deleteAccount();
      } else {
        await controller.logout();
      }
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mi cuenta')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          ref.watch(appProvider).profile?.name ?? '',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: busy ? null : () => confirm(delete: false),
          child: const Text('Cerrar sesión'),
        ),
        TextButton(
          onPressed: busy ? null : () => confirm(delete: true),
          child: const Text('Borrar mi cuenta'),
        ),
        if (error != null) Text(error!),
      ],
    ),
  );
}
