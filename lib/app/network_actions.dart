part of 'app_controller.dart';

/// The network proxy and its local bridge.
/// The route change in progress or last done; the next one waits for it.
Future<void> _bridgeTail = Future.value();

extension NetworkActions on AppController {
  /// Reads the proxy setting again; for 跟随系统 also the Windows proxy,
  /// which a proxy tool may have turned on or off since.
  Future<void> _refreshProxy({bool ifStale = false}) async {
    final now = DateTime.now();
    if (ifStale && now.difference(_proxyRead) < const Duration(seconds: 30)) return;
    _proxyRead = now;
    final next = await NetworkProxy.resolve(settings.proxyMode, settings.proxyAddress);
    await _routeThroughBridge(next);
    appHttpOverrides.endpoint = proxyEndpoint;
    appHttpOverrides.useEnvironment = settings.proxyMode == ProxyMode.system;
    NativeHttp.configure(
      proxy: nativeProxy(next.url),
      system: settings.proxyMode == ProxyMode.system,
      dns: DnsServer.of(settings.dnsServer, settings.dnsCustomUrl),
      roots: settings.certificateRoots,
      quantum: settings.postQuantum,
    );
    if (next.url != proxy.url) logInfo(next.url == null ? 'Network: direct connection' : 'Network: using proxy ${next.redacted}');
    proxy = next;
    final player = this.player;
    if (player != null) await _applyProxy(player);
  }

  /// Starts, replaces or stops the bridge so it matches [next].
  Future<void> _routeThroughBridge(NetworkProxy next) {
    // One at a time: two refreshes at once would each start a bridge and
    // only one of them would be kept.
    final run = _bridgeTail.then((_) => _routeNow(next));
    _bridgeTail = run.catchError((Object _) {});
    return run;
  }

  Future<void> _routeNow(NetworkProxy next) async {
    final old = _bridge;
    if (next.isSocks && next.url == _bridgeFor && old != null) return;
    _bridge = null;
    _bridgeFor = next.url;
    if (next.isSocks) {
      try {
        _bridge = await SocksBridge.start(next.url!);
      } catch (e) {
        logError('Could not start the local SOCKS bridge; requests will fail rather than go direct', e);
      }
    }
    proxyEndpoint = next.isSocks ? (_bridge?.hostPort ?? '127.0.0.1:1') : next.isHttp ? next.hostPort : null;
    await old?.close();
  }

  /// libmpv's streams can only use an HTTP proxy.
  Future<void> _applyProxy(Player player) async {
    final platform = player.platform;
    if (platform is NativePlayer) await platform.setProperty('http-proxy', proxyEndpoint == null ? '' : 'http://$proxyEndpoint');
  }
}
