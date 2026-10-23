import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import 'router.dart';
import 'state.dart';
import 'theme.dart';

class CorteYaApp extends ConsumerStatefulWidget {
  const CorteYaApp({super.key});
  @override
  ConsumerState<CorteYaApp> createState() => _CorteYaAppState();
}

class _CorteYaAppState extends ConsumerState<CorteYaApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appProvider.notifier).start());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return MaterialApp.router(
      title: 'CorteYa',
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: shopTheme(state.content?.shop),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        if (state.startupError != null) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(userMessage(state.startupError!)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.read(appProvider.notifier).start(),
                        child: const Text('Reintentar'),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(appProvider.notifier).changeShop(),
                        child: const Text('Cambiar de barbería'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return child!;
      },
    );
  }
}
