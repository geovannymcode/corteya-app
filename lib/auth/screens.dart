import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/formats.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({
    super.key,
    required this.request,
    required this.onSent,
    this.message,
  });
  final Future<void> Function(String) request;
  final void Function(String) onSent;
  final String? message;
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final form = GlobalKey<FormState>();
  final phone = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.request(phone.text);
      if (mounted) widget.onSent(phone.text);
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ingresa a CorteYa')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Tu próxima cita empieza aquí.',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            const Text('Te enviaremos un código para verificar tu celular.'),
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(widget.message!),
              ),
            const SizedBox(height: 24),
            TextFormField(
              controller: phone,
              enabled: !busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Celular',
                prefixText: '+57 ',
              ),
              validator: (value) => validPhone(value ?? '')
                  ? null
                  : 'Ingresa 10 dígitos que empiecen por 3.',
              onFieldSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Enviando…' : 'Enviar código'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!),
              ),
          ],
        ),
      ),
    ),
  );
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.verify,
    required this.resend,
    required this.onVerified,
    this.now = DateTime.now,
  });
  final Future<void> Function(String) verify;
  final Future<void> Function() resend;
  final VoidCallback onVerified;
  final DateTime Function() now;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  Timer? timer;
  int seconds = 60;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    timer?.cancel();
    seconds = 60;
    final deadline = widget.now().add(const Duration(seconds: 60));
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final remaining =
          (deadline.difference(widget.now()).inMilliseconds / 1000).ceil();
      setState(() => seconds = remaining.clamp(0, 60));
      if (seconds == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.verify(code.text);
      if (mounted) {
        TextInput.finishAutofillContext();
        widget.onVerified();
      }
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    if (busy || seconds > 0) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.resend();
      if (mounted) setState(startTimer);
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verifica tu celular')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Escribe el código de 6 dígitos que recibiste.'),
            const SizedBox(height: 24),
            AutofillGroup(
              child: TextFormField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Código de verificación',
                ),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                    ? null
                    : 'Ingresa los 6 dígitos.',
                onFieldSubmitted: (_) => submit(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Verificando…' : 'Verificar código'),
            ),
            TextButton(
              onPressed: busy || seconds > 0 ? null : resend,
              child: Text(seconds > 0 ? 'Reenviar en ${seconds}s' : 'Reenviar'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
  );
}

class NameScreen extends StatefulWidget {
  const NameScreen({super.key, required this.save, required this.onSaved});
  final Future<void> Function(String) save;
  final VoidCallback onSaved;
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(name.text.trim());
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('¿Cómo te llamas?')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: name,
              enabled: !busy,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Escribe tu nombre.' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('Continuar'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
  );
}
