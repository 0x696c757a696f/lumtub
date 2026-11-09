import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'airplay.dart';
import 'cast_device.dart';
import 'chromecast.dart';
import 'dlna.dart';

/// Every DLNA renderer, Chromecast and AirPlay receiver found on the LAN
/// within [timeout]; the stream ends when the search does, and cancelling
/// it stops the search.
Stream<CastDevice> discoverCastDevices({Duration timeout = const Duration(seconds: 6), AirPlayPairings? pairings}) {
  final controller = StreamController<CastDevice>();
  final subscriptions = <StreamSubscription<CastDevice>>[];
  var cancelled = false;
  controller.onListen = () async {
    // Android 17 asks the user before an app may reach the local network.
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('askLocalNetwork');
      } on PlatformException {
        // Searched anyway; nothing is found without it.
      }
      if (cancelled) return;
    }
    var open = 3;
    void done() {
      if (--open == 0) unawaited(controller.close());
    }

    for (final search in [discoverDlna(timeout: timeout), discoverChromecasts(timeout: timeout), discoverAirPlay(timeout: timeout, pairings: pairings)]) {
      subscriptions.add(search.listen(controller.add, onError: (_) {}, onDone: done));
    }
  };
  controller.onCancel = () async {
    cancelled = true;
    for (final s in subscriptions) {
      await s.cancel();
    }
  };
  return controller.stream;
}
