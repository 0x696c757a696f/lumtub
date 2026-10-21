import 'dart:async';

import 'cast_device.dart';
import 'chromecast.dart';
import 'dlna.dart';

/// Every DLNA renderer and Chromecast found on the LAN within [timeout];
/// the stream ends when the search does, and cancelling it stops the search.
Stream<CastDevice> discoverCastDevices({Duration timeout = const Duration(seconds: 6)}) {
  final controller = StreamController<CastDevice>();
  final subscriptions = <StreamSubscription<CastDevice>>[];
  controller.onListen = () {
    var open = 2;
    void done() {
      if (--open == 0) unawaited(controller.close());
    }

    for (final search in [discoverDlna(timeout: timeout), discoverChromecasts(timeout: timeout)]) {
      subscriptions.add(search.listen(controller.add, onError: (_) {}, onDone: done));
    }
  };
  controller.onCancel = () async {
    for (final s in subscriptions) {
      await s.cancel();
    }
  };
  return controller.stream;
}
