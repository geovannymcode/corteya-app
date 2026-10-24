import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// One request at a time. Losing visibility cancels both timers and HTTP work.
class AppointmentPoller extends ChangeNotifier {
  AppointmentPoller({
    required this.api,
    required this.token,
    required this.now,
    DateTime? holdExpiresAt,
  }) : _deadline = holdExpiresAt;
  final BookingApi api;
  final String token;
  final DateTime Function() now;
  Appointment? appointment;
  Object? error;
  bool busy = false, expired = false;
  bool _active = false, _disposed = false;
  int _generation = 0, _failures = 0;
  DateTime? _deadline;
  Timer? _next, _expiry;
  CancelToken? _request;
  void setActive(bool active) {
    if (_disposed) return;
    if (!active) {
      _active = false;
      ++_generation;
      _next?.cancel();
      _expiry?.cancel();
      _request?.cancel();
      busy = false;
      return;
    }
    if (_active) return;
    _active = true;
    if (_deadline != null && !now().isBefore(_deadline!)) {
      expired = true;
      notifyListeners();
      return;
    }
    _fetch();
  }

  void refresh() {
    if (!_disposed && _active && !busy && !expired) {
      _next?.cancel();
      _fetch();
    }
  }

  bool get _terminal =>
      appointment != null && appointment!.status != 'PENDING_PAYMENT';
  void _armExpiry() {
    _expiry?.cancel();
    if (_deadline == null) return;
    final duration = _deadline!.difference(now());
    if (duration <= Duration.zero) {
      _expire();
    } else {
      _expiry = Timer(duration, _expire);
    }
  }

  void _expire() {
    if (_disposed || !_active) return;
    expired = true;
    ++_generation;
    _next?.cancel();
    _request?.cancel();
    busy = false;
    notifyListeners();
  }

  Future<void> _fetch() async {
    if (!_active || _disposed || busy || expired || _terminal) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    _request = CancelToken();
    _armExpiry();
    if (expired) return;
    notifyListeners();
    try {
      final result = await api.appointment(token, cancelToken: _request);
      if (_disposed || !_active || generation != _generation) return;
      appointment = result;
      _deadline = result.holdExpiresAt ?? _deadline;
      _failures = 0;
      if (_terminal) {
        _expiry?.cancel();
      } else {
        _armExpiry();
      }
    } catch (e) {
      if (_disposed || !_active || generation != _generation) return;
      if (e is! DioException || !CancelToken.isCancel(e)) {
        error = e;
        _failures++;
      }
    } finally {
      if (!_disposed && _active && generation == _generation) {
        busy = false;
        notifyListeners();
        if (!expired && !_terminal) {
          final seconds = (5 * (1 << _failures.clamp(0, 3))).clamp(5, 40);
          _next = Timer(Duration(seconds: seconds), _fetch);
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _active = false;
    _next?.cancel();
    _expiry?.cancel();
    _request?.cancel();
    super.dispose();
  }
}
