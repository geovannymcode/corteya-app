import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/screen.dart';
import '../auth/screens.dart';
import '../barbershop/home.dart';
import '../barbershop/links.dart';
import '../barbershop/picker.dart';
import '../core/errors.dart';
import '../booking/flow.dart';
import '../booking/payment.dart';
import '../booking/appointments.dart';
import '../booking/models.dart';
import 'state.dart';

class RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

String landing(AppState state) => state.content == null
    ? '/'
    : state.profile?.staffOf(state.content!.shop.slug) == true
    ? '/staff'
    : '/home';
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh();
  var bookingRequested = false;
  var appointmentsRequested = false;
  var paymentReturnRequested = false;
  String? pendingServiceId;
  ref.listen(appProvider, (_, next) => refresh.refresh());
  final router = GoRouter(
    refreshListenable: refresh,
    observers: [paymentRouteObserver],
    redirect: (context, route) {
      final state = ref.read(appProvider);
      final path = route.uri.path;
      if (route.uri.scheme == 'corteya' && route.uri.host == 'pago') {
        paymentReturnRequested = true;
        return '/pago';
      }
      if (route.uri.hasScheme) {
        final slug = shopSlug(
          route.uri.toString(),
          appLinkHost: ref.read(configProvider).appLinkHost,
        );
        if (slug != null) return '/b/$slug';
        return '/';
      }
      if (!state.ready) {
        return path == '/loading'
            ? null
            : '/loading?from=${Uri.encodeComponent(route.uri.toString())}';
      }
      if (path == '/loading') {
        final from = route.uri.queryParameters['from'];
        final slug = from == null
            ? null
            : shopSlug(from, appLinkHost: ref.read(configProvider).appLinkHost);
        if (slug != null) return '/b/$slug';
        final incoming = from == null ? null : Uri.tryParse(from);
        if (incoming?.path == '/pago') {
          paymentReturnRequested = true;
          return '/pago';
        }
        if (incoming != null && incoming.path.startsWith('/b/')) {
          return incoming.path;
        }
        return landing(state);
      }
      if (path.startsWith('/b/')) {
        bookingRequested = false;
        return null;
      }
      final wantsBooking =
          bookingRequested || route.uri.queryParameters['next'] == 'booking';
      final destination =
          paymentReturnRequested || route.uri.queryParameters['next'] == 'pago'
          ? '/pago'
          : appointmentsRequested ||
                route.uri.queryParameters['next'] == 'appointments'
          ? '/appointments'
          : wantsBooking &&
                state.content?.shop.bookingEnabled == true &&
                state.profile?.staffOf(state.content?.shop.slug) != true
          ? '/booking${pendingServiceId == null ? '' : '?service=${Uri.encodeComponent(pendingServiceId!)}'}'
          : landing(state);
      if (state.profile != null && (state.profile!.name ?? '').trim().isEmpty) {
        if (path == '/name') return null;
        return paymentReturnRequested
            ? '/name?next=pago'
            : appointmentsRequested
            ? '/name?next=appointments'
            : wantsBooking
            ? '/name?next=booking'
            : '/name';
      }
      if (state.profile != null &&
          (bookingRequested ||
              appointmentsRequested ||
              paymentReturnRequested)) {
        bookingRequested = false;
        appointmentsRequested = false;
        paymentReturnRequested = false;
        pendingServiceId = null;
        return path == destination ? null : destination;
      }
      if (state.profile == null &&
          ([
                '/account',
                '/name',
                '/booking',
                '/staff',
                '/pago',
              ].contains(path) ||
              path.startsWith('/appointments'))) {
        return path == '/pago'
            ? '/login?next=pago'
            : path.startsWith('/appointments')
            ? '/login?next=appointments'
            : path == '/booking'
            ? '/login?next=booking'
            : '/login';
      }
      if (state.profile != null && ['/login', '/otp', '/name'].contains(path)) {
        return destination;
      }
      if (path == '/booking' && state.content?.shop.bookingEnabled != true) {
        return landing(state);
      }
      if (state.content == null &&
          ['/home', '/staff', '/booking'].contains(path)) {
        return '/';
      }
      if (path == '/' && state.content != null) return landing(state);
      if (path == '/home' &&
          state.profile?.staffOf(state.content?.shop.slug) == true) {
        return '/staff';
      }
      if (path == '/staff' &&
          state.profile?.staffOf(state.content?.shop.slug) != true) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, route) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/', builder: (_, route) => const ShopPicker()),
      GoRoute(
        path: '/b/:slug',
        builder: (_, route) => LinkEntry(slug: route.pathParameters['slug']!),
      ),
      // Flutter can retain the host of corteya://b/{slug} in the incoming URI.
      GoRoute(
        path: '/home',
        builder: (context, route) {
          final state = ref.read(appProvider);
          return ShopHome(
            content: state.content!,
            onBook: () {
              pendingServiceId = null;
              bookingRequested = state.profile == null;
              context.push(
                state.profile == null ? '/login?next=booking' : '/booking',
              );
            },
            onService: (service) {
              pendingServiceId = service.id;
              bookingRequested = state.profile == null;
              context.push(
                state.profile == null
                    ? '/login?next=booking'
                    : '/booking?service=${Uri.encodeComponent(service.id)}',
              );
            },
            onAppointments: () {
              appointmentsRequested = state.profile == null;
              bookingRequested = false;
              context.push(
                state.profile == null
                    ? '/login?next=appointments'
                    : '/appointments',
              );
            },
            onChange: () {
              bookingRequested = false;
              ref.read(appProvider.notifier).changeShop();
            },
            onAccount: () {
              bookingRequested = false;
              context.push(state.profile == null ? '/login' : '/account');
            },
          );
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, route) => PhoneScreen(
          message: ref.read(appProvider).message,
          request: ref.read(appProvider.notifier).requestOtp,
          onSent: (phone) => context.push(
            route.uri.queryParameters['next'] == null
                ? '/otp'
                : '/otp?next=${route.uri.queryParameters['next']}',
            extra: phone,
          ),
        ),
      ),
      GoRoute(
        path: '/otp',
        redirect: (context, route) => route.extra is String ? null : '/login',
        builder: (context, route) {
          final phone = route.extra! as String;
          return OtpScreen(
            verify: (code) =>
                ref.read(appProvider.notifier).verifyOtp(phone, code),
            resend: () => ref.read(appProvider.notifier).requestOtp(phone),
            onVerified: () {},
          );
        },
      ),
      GoRoute(
        path: '/name',
        builder: (context, route) => NameScreen(
          save: ref.read(appProvider.notifier).rename,
          onSaved: () {},
        ),
      ),
      GoRoute(path: '/account', builder: (_, route) => const AccountScreen()),
      GoRoute(
        path: '/booking',
        builder: (_, route) =>
            BookingFlow(serviceId: route.uri.queryParameters['service']),
      ),
      GoRoute(
        path: '/appointments',
        builder: (_, route) => const MyAppointmentsScreen(),
      ),
      GoRoute(
        path: '/appointments/:token/payment',
        builder: (_, route) => PaymentScreen(
          token: route.pathParameters['token']!,
          initial: route.extra is Appointment
              ? route.extra! as Appointment
              : null,
          overrideInstructions: route.extra is PaymentInstructions
              ? route.extra! as PaymentInstructions
              : null,
        ),
      ),
      GoRoute(
        path: '/appointments/:token/wait',
        builder: (context, route) => WaitingScreen(
          token: route.pathParameters['token']!,
          onConfirmed: (a) => context.go('/appointments/${a.token}'),
        ),
      ),
      GoRoute(
        path: '/appointments/:token',
        builder: (_, route) =>
            AppointmentScreen(token: route.pathParameters['token']!),
      ),
      GoRoute(
        path: '/pago',
        builder: (_, route) => const PaymentReturnScreen(),
      ),
      GoRoute(
        path: '/staff',
        builder: (context, route) => Scaffold(
          appBar: AppBar(
            title: const Text('Modo barbero'),
            actions: [
              IconButton(
                onPressed: () => context.push('/account'),
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pronto podrás administrar tu agenda aquí.'),
                TextButton(
                  onPressed: () => ref.read(appProvider.notifier).changeShop(),
                  child: const Text('Cambiar de barbería'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/:slug',
        builder: (_, route) => LinkEntry(slug: route.pathParameters['slug']!),
      ),
    ],
    errorBuilder: (context, route) => const PlaceholderScreen(
      title: 'Enlace no válido',
      message: 'Vuelve a abrir el QR o escribe el código de tu barbería.',
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
  });
  final String title, message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
    ),
  );
}

class LinkEntry extends ConsumerStatefulWidget {
  const LinkEntry({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<LinkEntry> createState() => _LinkEntryState();
}

class _LinkEntryState extends ConsumerState<LinkEntry> {
  String? error;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(covariant LinkEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      error = null;
      Future.microtask(load);
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    final slug = widget.slug;
    try {
      if (shopSlug(widget.slug) == null) throw const FormatException();
      await ref.read(appProvider.notifier).selectShop(slug);
      if (mounted && widget.slug == slug) {
        context.go(landing(ref.read(appProvider)));
      }
    } catch (e) {
      if (mounted && widget.slug == slug) {
        setState(() => error = userMessage(e, barbershopLookup: true));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tu barbería')),
    body: Center(
      child: error == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.all(24), child: Text(error!)),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Escribir otro código'),
                ),
              ],
            ),
    ),
  );
}
