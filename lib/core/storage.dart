import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.accessToken, this.refreshToken);
  final String accessToken;
  final String refreshToken;
  factory Tokens.fromJson(Map<String, dynamic> json) =>
      Tokens(json['accessToken'] as String, json['refreshToken'] as String);
  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

class TokenStore {
  TokenStore([this.storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage storage;
  Future<Tokens?> read() async {
    final value = await storage.read(key: 'session');
    if (value == null) return null;
    try {
      return Tokens.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } on Object {
      await clear();
      return null;
    }
  }

  // A single value keeps both rotated credentials together.
  Future<void> write(Tokens tokens) =>
      storage.write(key: 'session', value: jsonEncode(tokens.toJson()));
  Future<void> clear() => storage.delete(key: 'session');
}

class ShopPreferences {
  static const channel = MethodChannel('com.geovannycode.corteya/preferences');
  Future<String?> read() => channel.invokeMethod<String>('readSlug');
  Future<void> write(String? slug) =>
      channel.invokeMethod<void>('writeSlug', slug);
}
