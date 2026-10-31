import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class FollowReminder {
  static const channel = MethodChannel('io.manxia/follow-reminder');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<Map<String, dynamic>> load() async {
    if (!supported) return {'available': false};
    return Map<String, dynamic>.from(
      await channel.invokeMapMethod('get') ?? {},
    );
  }

  static Future<Map<String, dynamic>> save({
    required bool enabled,
    required List<int> days,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async => Map<String, dynamic>.from(
    await channel.invokeMapMethod('configure', {
          'enabled': enabled,
          'days': days,
          'hour': hour,
          'minute': minute,
          'title': title,
          'body': body,
        }) ??
        {},
  );
}
