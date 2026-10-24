import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/state.dart';
import '../core/errors.dart';
import 'links.dart';

class ShopPicker extends ConsumerStatefulWidget {
  const ShopPicker({super.key});
  @override
  ConsumerState<ShopPicker> createState() => _ShopPickerState();
}

class _ShopPickerState extends ConsumerState<ShopPicker> {
  final code = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> select(String input) async {
    if (busy) return;
    final slug = shopSlug(
      input,
      appLinkHost: ref.read(configProvider).appLinkHost,
    );
    if (slug == null) {
      setState(
        () => error = 'Escribe un código o escanea un QR válido de CorteYa.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(appProvider.notifier).selectShop(slug);
    } catch (e) {
      if (mounted) {
        setState(() => error = userMessage(e, barbershopLookup: true));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          const Text(
            'CorteYa',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 32),
          const Text(
            'Tu barbería.\nTu estilo.',
            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          const Text('Escanea el QR de tu barbería'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final result = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const ScannerScreen()),
                    );
                    if (result != null && mounted) await select(result);
                  },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear QR'),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: code,
            enabled: !busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Código de la barbería',
            ),
            onSubmitted: busy ? null : select,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : () => select(code.text),
            child: Text(busy ? 'Buscando…' : 'Entrar con código'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!, semanticsLabel: error),
            ),
        ],
      ),
    ),
  );
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool returned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanea el QR')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Usamos la cámara únicamente para leer el QR de tu barbería. También puedes volver y escribir su código.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final value = capture.barcodes.firstOrNull?.rawValue;
              if (!returned && value != null) {
                returned = true;
                Navigator.pop(context, value);
              }
            },
            errorBuilder: (context, error) => const Center(
              child: Text(
                'No pudimos abrir la cámara. Revisa el permiso en Ajustes o vuelve para escribir el código.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
