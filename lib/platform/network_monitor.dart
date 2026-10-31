import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'network_support_stub.dart'
    if (dart.library.io) 'network_support_io.dart'
    as host;

class NetworkInfo {
  const NetworkInfo(this.kind, {this.metered = false});
  final String kind;
  final bool metered;
  factory NetworkInfo.fromMap(Map value) => NetworkInfo(
    value['kind'] is String ? value['kind'] : 'unknown',
    metered: value['metered'] == true,
  );
  bool permits(bool wifiOnly) =>
      kind != 'none' && (!wifiOnly || (kind == 'wifi' && !metered));
  @override
  bool operator ==(Object other) =>
      other is NetworkInfo && kind == other.kind && metered == other.metered;
  @override
  int get hashCode => Object.hash(kind, metered);
}

class NetworkMonitor extends ValueNotifier<NetworkInfo> {
  NetworkMonitor({
    bool? native,
    NetworkInfo initial = const NetworkInfo('unknown'),
  }) : native = native ?? host.androidNetworkAvailable,
       super(initial);
  final bool native;
  static const channel = MethodChannel('io.manxia/network');
  static const events = EventChannel('io.manxia/network-events');
  StreamSubscription<dynamic>? subscription;
  Future<void> start() async {
    if (!native) {
      return;
    }
    try {
      value = NetworkInfo.fromMap(
        await channel
                .invokeMapMethod('state')
                .timeout(const Duration(seconds: 2)) ??
            {},
      );
      subscription = events.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) value = NetworkInfo.fromMap(event);
        },
        onError: (Object _) {
          value = const NetworkInfo('unknown');
        },
      );
    } catch (_) {
      value = const NetworkInfo('unknown');
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }
}
