import 'dart:async';

import 'package:dio/dio.dart';

/// Refreshes only while visible and resumed; cancels work when either changes.
class StaffRefresh {
  StaffRefresh(this.load);
  final Future<void> Function(CancelToken) load;
  Timer? _timer;
  CancelToken? _request;
  bool _active = false, _disposed = false;
  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _timer?.cancel();
    _request?.cancel();
    if (active) {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (!_active || _disposed) return;
    _timer?.cancel();
    _request?.cancel();
    final request = CancelToken();
    _request = request;
    try {
      await load(request);
    } finally {
      if (!_disposed && _active && identical(_request, request)) {
        _timer = Timer(const Duration(seconds: 60), refresh);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _request?.cancel();
  }
}
